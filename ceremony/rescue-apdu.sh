#!/usr/bin/env bash
# ceremony/rescue-apdu.sh
#
# Guarded sender for pico-hsm RESCUE APPLET APDUs.
#
# WHY THIS EXISTS -- read before bypassing it:
#
#   CLA 80, INS 0x1C = PHY write      (persistent board config)
#   CLA 80, INS 0x1D = SECURE BOOT BURN  <-- IRREVERSIBLE, DESTROYS THE UNIT
#   CLA 80, INS 0x1E = PHY read       (safe)
#
# On pico-hsm v6.6 INS 0x1D is UNAUTHENTICATED and UNGATED. It calls
# otp_enable_secure_boot(), which burns a hardcoded 32-byte digest
# (src/fs/otp.c) into an unused eFuse key block, sets its purpose to
# SECURE_BOOT_DIGEST, write-protects it and sets SECURE_BOOT_EN. With
# P2=01 it additionally revokes the other digest slots, locks the key
# block and disables JTAG. None of this can be undone.
#
# Consequence: the unit will only ever boot firmware signed by upstream's
# key -- or nothing at all, if the flashed image is not signed with it.
# Units flashed from the GitHub release asset have a signing status
# relative to that digest that is UNKNOWN. So a stray 0x1D is plausibly
# a brick, not merely a lock.
#
# The read (0x1E) and the burn (0x1D) differ by one bit. Hence this
# wrapper: it refuses 0x1D outright.
#
#   ./rescue-apdu.sh read           # PHY read  (801E010000)
#   ./rescue-apdu.sh raw <hex>      # anything else, still guarded
#
set -euo pipefail

RESCUE_AID="00A4040008A0583FC19B7E4F21"
READER="${READER:-0}"

die() { printf '\nREFUSED: %s\n' "$*" >&2; exit 1; }

# WHITELIST, not blacklist. 0x1D (fuse burn) is one bit from 0x1C and
# 0x1E, so anything not explicitly permitted is refused -- a typo must
# fail closed, never fall through to the destructive instruction.
ALLOWED_INS="1E"          # 1C (PHY write) added only once a reviewed
                          # TLV blob exists and the v6.6 codec is diffed

guard() {
    local hex="${1//[: ]/}"
    hex=$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')

    [[ "$hex" =~ ^[0-9A-F]+$ ]] || die "not hex: $hex"
    [ $(( ${#hex} % 2 )) -eq 0 ] || die "odd-length hex: $hex"
    [ ${#hex} -ge 8 ] || die "APDU too short: $hex"

    local cla="${hex:0:2}" ins="${hex:2:2}"
    [ "$cla" == "80" ] || die "unexpected CLA $cla (rescue applet uses 80)"

    local ok=0
    for a in $ALLOWED_INS; do [ "$ins" == "$a" ] && ok=1; done
    if [ "$ok" -ne 1 ]; then
        if [ "$ins" == "1D" ]; then
            die "INS 0x1D is the secure-boot eFuse burn. On ESP32-S3 upstream ships UNSIGNED images while otp.c carries a digest of a key nobody has -- this PERMANENTLY BRICKS the unit. Never."
        fi
        die "INS 0x$ins is not on the whitelist ($ALLOWED_INS). Refusing."
    fi
    printf '%s' "$hex"
}

count_units() {
    system_profiler SPUSBDataType 2>/dev/null | grep -c "Pico Key:" || true
}

main() {
    local n
    n=$(count_units)
    [ "$n" -eq 1 ] || die "$n Pico Key devices connected; connect exactly one (they are indistinguishable at the PKCS#11 layer)"

    system_profiler SPUSBDataType 2>/dev/null \
        | awk '/Pico Key:/{f=1} f&&/Serial Number:/{print "unit:", $3; f=0}'

    local apdu
    case "${1:-}" in
        read) apdu="801E010000" ;;
        raw)  apdu=$(guard "${2:?hex required}") ;;
        *)    die "usage: $0 {read|raw <hex>}" ;;
    esac
    apdu=$(guard "$apdu")

    echo "SELECT rescue applet + send $apdu"
    opensc-tool --reader "$READER" \
        -s "$RESCUE_AID" \
        -s "$(printf '%s' "$apdu" | sed 's/../&:/g; s/:$//')"
}

main "$@"
