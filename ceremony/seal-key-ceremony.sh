#!/usr/bin/env bash
# seal-key-ceremony.sh
#
# Provision ONE pico-hsm dongle with the OpenBao pkcs11 seal key.
#
# Run once per dongle, with exactly ONE dongle connected. The two units
# are indistinguishable at the PKCS#11 layer, so connecting both makes
# reader selection ambiguous -- the script refuses in that case.
#
# The DKEK share is transient by design and is never escrowed anywhere:
# provisioning a replacement dongle later means creating a fresh random
# share on that device and re-wrapping the same escrowed PEM under it.
#
# THIS IS DESTRUCTIVE. `sc-hsm-tool --initialize` erases all keys on the
# device.
#
# Generate the PEM once with `generate`, escrow it in your password
# manager, then run `provision` once per dongle with the same PEM on
# stdin, so every dongle gets an identical key.
#
#   ./seal-key-ceremony.sh generate > seal.pem         # once; escrow this, then shred it
#   ./seal-key-ceremony.sh preflight                   # checks only, touches nothing
#   SO_PIN=… USER_PIN=… ./seal-key-ceremony.sh provision < seal.pem
#
# or, straight from a password manager so the PEM never touches disk:
#   ./seal-key-ceremony.sh generate | <your-manager> store …
#   <your-manager> read … | SO_PIN=… USER_PIN=… ./seal-key-ceremony.sh provision
#
# With both dongles on a hub, isolate the target by powering off the
# other port (uhubctl), or just pass the reader index:
#   READER_INDEX=2 ./seal-key-ceremony.sh provision
#
set -euo pipefail

KEY_LABEL="bao-seal"
TOKEN_LABEL="bao"                # ignored by the firmware; see README
SCSH_SHA256="1e5a065b7888a660a088956d110ce5539e85b76cf3c3f02eb57e4d3104bcf280"
SCSH_ZIP="${SCSH_ZIP:-$(dirname "$0")/scsh-3.18.77.zip}"
SCSH_IMPORT_JS="$(dirname "$0")/import-seal-key.js"
PKCS11_MODULE="${PKCS11_MODULE:-/opt/homebrew/lib/opensc-pkcs11.so}"

RAMDISK=""
WORKDIR=""

log()  { printf '\n=== %s\n' "$*"; }
die()  { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }

cleanup() {
    local rc=$?
    if [ -n "$RAMDISK" ]; then
        log "tearing down ramdisk (key material never touched disk)"
        # The volume was mounted with raw mount(8), so DiskArbitration
        # never learns of it: diskutil can't resolve it and hdiutil gets
        # EBUSY while it's mounted. Raw umount first, then detach.
        if [ -n "$WORKDIR" ]; then
            umount "$WORKDIR" 2>/dev/null || true
        fi
        hdiutil detach "$RAMDISK" >/dev/null 2>&1 || \
            hdiutil detach "$RAMDISK" -force >/dev/null 2>&1 || \
            echo "WARNING: ramdisk $RAMDISK still attached -- run: umount $WORKDIR && hdiutil detach $RAMDISK" >&2
        if [ -n "$WORKDIR" ]; then
            rmdir "$WORKDIR" 2>/dev/null || true
        fi
    fi
    exit $rc
}
trap cleanup EXIT INT TERM

# --- key generation -------------------------------------------------------
generate() {
    openssl genrsa 4096 2>/dev/null
}

# --- preflight ----------------------------------------------------------
preflight() {
    log "tooling"
    for t in openssl sc-hsm-tool pkcs11-tool opensc-tool java unzip shasum; do
        command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
        printf '  ok  %s\n' "$t"
    done

    log "PINs present"
    [ -n "${SO_PIN:-}" ]   || die "SO_PIN not set -- export it before running provision"
    [ -n "${USER_PIN:-}" ] || die "USER_PIN not set -- export it before running provision"
    echo "  ok  SO_PIN and USER_PIN set"

    [ -f "$SCSH_ZIP" ]       || die "vendored scsh not found: $SCSH_ZIP"
    local zip_sha
    zip_sha=$(shasum -a 256 "$SCSH_ZIP" | awk '{print $1}')
    [ "$zip_sha" == "$SCSH_SHA256" ] || die "scsh zip sha256 mismatch: $SCSH_ZIP (see SCSH-PROVENANCE.md)"
    [ -f "$SCSH_IMPORT_JS" ] || die "import template not found: $SCSH_IMPORT_JS"

    log "finding target dongle"
    local readers
    readers=$(opensc-tool --list-readers 2>&1)
    if [ -n "${READER_INDEX:-}" ]; then
        READER="$READER_INDEX"
        echo "  using READER_INDEX=$READER (from environment)"
    else
        local pico_readers
        pico_readers=$(echo "$readers" | grep -c "Pico Key" || true)
        [ "$pico_readers" -ge 1 ] || die "no Pico Key reader found"
        [ "$pico_readers" -le 1 ] || die "found $pico_readers Pico Key readers; set READER_INDEX= or isolate one via uhubctl"
        READER=$(echo "$readers" | awk '/Pico Key/{print $1; exit}')
    fi
    echo "$readers" | sed 's/^/  /'

    log "card answers (reader $READER)"
    opensc-tool --reader "$READER" -an | sed 's/^/  /'
}

# --- ramdisk ------------------------------------------------------------
make_ramdisk() {
    # 64MB. Key material lives here and nowhere else; SSD secure-erase is
    # unreliable, so never writing to disk beats trying to scrub it after.
    local dev
    dev=$(hdiutil attach -nomount ram://131072)
    dev=$(echo "$dev" | tr -d '[:space:]')
    newfs_hfs -v ceremony "$dev" >/dev/null
    WORKDIR=$(mktemp -d /tmp/ceremony.XXXXXX)
    mount -t hfs "$dev" "$WORKDIR"
    RAMDISK="$dev"
    chmod 700 "$WORKDIR"
    log "ramdisk at $WORKDIR ($dev)"
}

# --- key material -------------------------------------------------------
obtain_key() {
    log "reading seal key from stdin"
    local pem
    pem=$(cat)
    [[ "$pem" == -----BEGIN* ]] || die "no PEM on stdin — pipe the escrowed seal key into provision"
    printf '%s\n' "$pem" > "$WORKDIR/seal.pem"
    chmod 600 "$WORKDIR/seal.pem"

    # scsh imports from PKCS#12; the certificate is only a carrier for the
    # public half, which encodeKey() needs alongside the private key.
    openssl req -new -x509 -key "$WORKDIR/seal.pem" -out "$WORKDIR/seal.crt" \
        -days 7300 -subj "/CN=$KEY_LABEL" 2>/dev/null
    P12_PWD=$(openssl rand -hex 16)
    openssl pkcs12 -export -inkey "$WORKDIR/seal.pem" -in "$WORKDIR/seal.crt" \
        -out "$WORKDIR/seal.p12" -name "$KEY_LABEL" -passout "pass:$P12_PWD"
}

# --- device -------------------------------------------------------------
init_device() {
    log "initialising device (ERASES ALL KEYS)"
    sc-hsm-tool --reader "$READER" --initialize \
        --so-pin "$SO_PIN" --pin "$USER_PIN" \
        --dkek-shares 1 --label "$TOKEN_LABEL"

    log "waiting for device to recover after initialize"
    echo "  press RESET on the dongle, then press Enter here"
    read -r < /dev/tty

    log "confirming device responds"
    opensc-tool --reader "$READER" -an | sed 's/^/  /' \
        || die "device did not recover -- press RESET and retry"

    log "DKEK share (transient -- not escrowed, see header)"
    SHARE_PWD=$(openssl rand -hex 24)
    sc-hsm-tool --reader "$READER" --create-dkek-share "$WORKDIR/dkek.pbe" \
        --password "$SHARE_PWD"
    sc-hsm-tool --reader "$READER" --import-dkek-share "$WORKDIR/dkek.pbe" \
        --password "$SHARE_PWD" --so-pin "$SO_PIN"
}

import_key() {
    log "unpacking scsh"
    unzip -q -o "$SCSH_ZIP" -d "$WORKDIR/scsh"
    local SCSH_DIR="$WORKDIR/scsh/scsh-3.18.77"

    # sc-hsm-tool --unwrap-key cannot take a PEM (it wants a DER container
    # of blob + description + certificate). scsh does the DKEK wrap AND the
    # card import itself over PCSC, so sc-hsm-tool is not involved here.
    local reader_name
    reader_name=$(opensc-tool --list-readers 2>&1 \
        | awk -v r="$READER" '/^[0-9]/{if($1==r){s=substr($0,21); sub(/^ +/,"",s); print s; exit}}')
    [ -n "$reader_name" ] || die "cannot resolve reader $READER to a name"

    sed -e "s|<hex of the .pbe DKEK share file>|$(xxd -p "$WORKDIR/dkek.pbe" | tr -d '\n')|" \
        -e "s|<DKEK share password>|$SHARE_PWD|" \
        -e "s|<absolute path to seal.p12>|$WORKDIR/seal.p12|" \
        -e "s|<p12 password>|$P12_PWD|" \
        -e "s|<user PIN>|$USER_PIN|" \
        -e "s|Pol Henarejos Pico Key HID Interface|$reader_name|" \
        "$SCSH_IMPORT_JS" > "$SCSH_DIR/ceremony-import.js"

    log "wrapping under DKEK and importing (takes ~1 min)"
    ( cd "$SCSH_DIR" && java -Xmx1024m \
        -Dsun.security.smartcardio.t1GetResponse=false \
        -Dorg.bouncycastle.asn1.allow_unsafe_integer=true \
        -Djava.library.path=./lib -cp './bin:lib/*' \
        de.cardcontact.scdp.engine.ScriptRunner ceremony-import.js ) \
        | grep -vE "^Derive DKEK" | sed 's/^/  /'
}

verify() {
    log "verifying: encrypt with the ESCROWED key, decrypt on the device"
    local id
    id=$(pkcs11-tool --module "$PKCS11_MODULE" --login --pin "$USER_PIN" -O 2>/dev/null \
         | awk -v l="$KEY_LABEL" '/Private Key Object/{p=1} p&&/label:/{lab=$2} p&&/ID:/{if(lab==l){print $2; exit}}')
    [ -n "$id" ] || die "imported key not found on device"

    echo "seal-key-ceremony-proof" > "$WORKDIR/proof.txt"
    openssl rsa -in "$WORKDIR/seal.pem" -pubout -out "$WORKDIR/seal.pub" 2>/dev/null
    openssl pkeyutl -encrypt -pubin -inkey "$WORKDIR/seal.pub" \
        -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
        -in "$WORKDIR/proof.txt" -out "$WORKDIR/proof.enc"

    # --id, NOT --label: pkcs11-tool does not filter by label for --decrypt
    # and will silently use the wrong key (fails CKR_ENCRYPTED_DATA_INVALID,
    # which looks like corruption and isn't).
    local out
    out=$(pkcs11-tool --module "$PKCS11_MODULE" --login --pin "$USER_PIN" \
            --decrypt -m RSA-PKCS-OAEP --hash-algorithm SHA256 --id "$id" \
            -i "$WORKDIR/proof.enc" 2>/dev/null | tail -1)
    [ "$out" == "seal-key-ceremony-proof" ] \
        || die "OAEP round-trip FAILED (got: '$out') -- device does not hold the escrowed key"
    echo "  PASS -- device holds exactly the escrowed key (key id $id)"
}

# --- main ---------------------------------------------------------------
case "${1:-}" in
    generate) generate ;;
    preflight) preflight ;;
    provision)
        preflight
        make_ramdisk
        obtain_key
        init_device
        import_key
        verify
        log "DONE -- record this unit's USB serial in your inventory"
        ;;
    *) die "usage: $0 {generate|preflight|provision}" ;;
esac
