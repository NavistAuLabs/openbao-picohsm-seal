# Changelog

All notable changes to this project are documented here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Any change to a firmware patch or to the boot-guard sequence is called out
here regardless of size.

## [Unreleased]

### Added

- `firmware/`: reproducible Docker build of pico-hsm v6.6 for the Waveshare
  ESP32-S3-LCD-1.47 with three patches (`FORCE_BUTTON_WAIT`, LED on GPIO 38,
  tinyusb pinned below 0.21.0).
- `failover/`: uhubctl boot guard with ATR liveness probe, swap script, and
  Proxmox USB hardware-mapping snippet.
- `unseal-host/`: standard-kernel and pcscd/libccid role fragment, libccid
  VID/PID patch, and the OpenBao `seal "pkcs11"` stanza.
- `ceremony/`: key ceremony script (PINs from env, PEM on stdin), scsh import
  script, guarded rescue-APDU sender, scsh 3.18.77 provenance pin.
