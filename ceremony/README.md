# ceremony

The provisioning script, the scsh import script it drives, a guarded APDU
sender, and the pin for the scsh archive the import script needs.

Files: [`seal-key-ceremony.sh`](seal-key-ceremony.sh), [`import-seal-key.js`](import-seal-key.js), [`rescue-apdu.sh`](rescue-apdu.sh), [`SCSH-PROVENANCE.md`](SCSH-PROVENANCE.md).

## Flow

`generate` once, to produce the RSA-4096 seal key. Escrow the PEM in your password manager. Then `provision` once per dongle, with the same PEM on stdin and `SO_PIN`/`USER_PIN` in the environment. The script verifies each dongle by encrypting a known plaintext with the PEM's public half and decrypting it on the device.

```
./seal-key-ceremony.sh generate > seal.pem         # once; escrow this, then shred it
./seal-key-ceremony.sh preflight                   # checks only, touches nothing
SO_PIN=… USER_PIN=… ./seal-key-ceremony.sh provision < seal.pem
```

or, straight from a password manager so the PEM never touches disk:

```
./seal-key-ceremony.sh generate | <your-manager> store …
<your-manager> read … | SO_PIN=… USER_PIN=… ./seal-key-ceremony.sh provision
```

## One dongle at a time

The two units are indistinguishable at the PKCS#11 layer. The script refuses if it sees more than one reader. Isolate the target with `READER_INDEX=`, or power the other hub port off.

## DKEK share is transient

The DKEK share is created fresh per run and never escrowed. Provisioning a replacement dongle later means creating a new share on that device and re-wrapping the same escrowed PEM under it.

## The PEM is the only thing to keep

Escrow it before `provision` runs on the second dongle — both dongles must hold the same key. This repo says nothing about how to escrow it; that is your disaster-recovery plan, not this repo's.

## macOS only

The ramdisk uses `hdiutil`/`newfs_hfs`; on Linux substitute a tmpfs. [`rescue-apdu.sh`](rescue-apdu.sh) uses `system_profiler` to count connected units, which is also macOS-only.

## Post-initialize wedge

The dongle stops answering right after `sc-hsm-tool --initialize`. Press RESET on the dongle, then press Enter to continue.

## scsh

Smart Card Shell is not vendored in this repo — download it and check its hash against the pin in [`SCSH-PROVENANCE.md`](SCSH-PROVENANCE.md). The ceremony script refuses to proceed with a zip whose sha256 doesn't match. It needs a JRE (rehearsed on OpenJDK 22).

## Tools

`openssl sc-hsm-tool pkcs11-tool opensc-tool java unzip shasum`

## `rescue-apdu.sh`

On v6.6, the rescue applet's INS `0x1D` burns secure-boot eFuses with no authentication, and it is one bit away from the safe PHY read `0x1E`. The wrapper whitelists `0x1E` and refuses everything else.

```
./rescue-apdu.sh read
./rescue-apdu.sh raw <hex>
```

## Timings

From the rehearsal recorded in [`SCSH-PROVENANCE.md`](SCSH-PROVENANCE.md): DKEK wrap 8s, import 44s, RSA-4096 OAEP decrypt 16.2s.
