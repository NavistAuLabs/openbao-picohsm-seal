# wavehsm

Custom pico-hsm firmware build for the Waveshare ESP32-S3-LCD-1.47 seal
dongles used by the-openbao-kit's pkcs11 seal (homelab estate).

## Customizations over upstream v6.6

| Change | Why |
|---|---|
| `-DFORCE_BUTTON_WAIT` | Gate rescue-applet destructive APDUs (eFuse burn `0x1D`, PHY write `0x1C`, BOOTSEL reboot) behind a physical button press. Mitigates the unauthenticated-permanent-destruction risk documented in the-openbao-kit README. Does NOT affect normal PKCS#11 operations — auto-unseal is unaffected. |
| `NEOPIXEL_PIN` -> `GPIO_NUM_38` | Waveshare ESP32-S3-LCD-1.47 wires its WS2812B RGB LED to GPIO 38 (schematic: net `RGB_IO`, component LED1). Upstream default `GPIO_NUM_48` is the LCD backlight on this board. |
| `usbd_edpt_xfer` 5th parameter | `esp_tinyusb` 1.7.6 (managed component in ESP-IDF v5.5 Docker image) added a `bool is_isr` parameter; v6.6 pico-keys-sdk CCID code calls with 4 args. |

## Why v6.6, not master

Master has ~30 security fixes but its ESP32 build is broken upstream
(nightly CI silently fails it — `autobuild.sh` has no `set -e`). A
master-based build was completed and flashed but the resulting USB
descriptors were not recognised by macOS's built-in CCID class driver
(`usbsmartcardreaderd`), whereas v6.6 is the known-working baseline.
The security fixes remain a future goal — either when upstream ships a
new release or when the descriptor regression is resolved.

## Pins

| Item | Value |
|---|---|
| pico-hsm | `v6.6` / `251b35dd9c4fd929923fc3b192f6793826efeaef` |
| pico-keys-sdk | `44ee0254165d6338e27e6739c19c648f83b5c6c9` (pinned by v6.6 submodule) |
| ESP-IDF | v5.5 (via `espressif/idf:v5.5` Docker image) |

## Board: Waveshare ESP32-S3-LCD-1.47

Product page: https://www.waveshare.com/esp32-s3-lcd-1.47.htm

| Function | GPIO |
|---|---|
| RGB LED (WS2812B) | 38 |
| Boot button | 0 |
| LCD backlight | 48 |
| LCD RST | 39 |
| LCD CLK | 40 |
| LCD DC | 41 |
| LCD CS | 42 |
| LCD DIN/MOSI | 45 |

Schematic: `datasheets/ESP32-S3-LCD-1.47_schematic_diagram.pdf`

## Build

Requires Docker. Produces a merged flash image at offset 0.

```
./build.sh              # output in ./output/
./build.sh /tmp/out     # output in /tmp/out/
```

## Flash

Hold BOOT button, tap RESET, release BOOT to enter download mode.

```
esptool --port <port> erase-flash
esptool --port <port> write-flash 0x0 output/pico_hsm_wavehsm_esp32s3.bin
```

Unplug and replug normally to boot the new firmware.

## Flash record

| Date | Unit | Firmware | Result |
|---|---|---|---|
| 2026-07-31 | bench (`unit-2`) | v6.6 + patches | LED green (GPIO 38 confirmed). Smartcard verification pending (macOS CCID driver config to sort out separately). |

## macOS workstation CCID note

The system-bundled `ifd-ccid` (v1.5.1) does not include VID `0x2E8A`
PID `0x10FD`. Upstream libccid does. The smoke test on 2026-07-29
worked — the workstation config that enabled it needs to be
reconstructed. This is a workstation setup issue, not a firmware issue.
Apple's built-in class driver (`usbsmartcardreaderd`) does not recognise
this device regardless of firmware version; `useIFDCCID=yes` plus a
VID/PID-aware `ifd-ccid` is required.

## Vendoring back to the-openbao-kit

After bench verification, copy the binary into
`the-openbao-kit/files/firmware/pico-hsm/` with SHA256SUMS and update
`README-PROVENANCE.md` to reflect the custom build.
