# firmware

Custom pico-hsm firmware build for the Waveshare ESP32-S3-LCD-1.47, reproducible via Docker.

## Customisations over upstream v6.6

| Change | Why |
|---|---|
| `-DFORCE_BUTTON_WAIT` | Gate rescue-applet destructive APDUs (eFuse burn `0x1D`, PHY write `0x1C`, BOOTSEL reboot) behind a physical button press. Mitigates the unauthenticated-permanent-destruction risk (see ../ceremony/rescue-apdu.sh). Does NOT affect normal PKCS#11 operations — auto-unseal is unaffected. |
| `NEOPIXEL_PIN` -> `GPIO_NUM_38` | Waveshare ESP32-S3-LCD-1.47 wires its WS2812B RGB LED to GPIO 38 (schematic: net `RGB_IO`, component LED1). Upstream default `GPIO_NUM_48` is the LCD backlight on this board. |
| tinyusb pinned `<0.21.0` | `esp_tinyusb`'s managed-component resolver pulls `tinyusb` 0.21.0, which changed CCID descriptor handling so macOS's `usbsmartcardreaderd` rejects the device, and added a 5th `bool is_isr` parameter to `usbd_edpt_xfer()` that breaks the v6.6 build. Pinning to `<0.21.0` (resolves to 0.19.x) fixes both; no source patch is needed. |

## Why v6.6, not master

Master has ~30 security fixes (counted against commit `1ad8444`) but its ESP32 build is broken upstream
(nightly CI silently fails it — `autobuild.sh` has no `set -e`); the
descriptor regression was traced to tinyusb 0.21.0, not to master.
Separately, master's reorganised key storage
(`hsm_key_container_update()` / `mkek_store_file()`) fails key import
with `SW 6400` on a freshly initialised device, so the ceremony cannot
complete. The security fixes remain a future goal — either when
upstream ships a new release or when the import path is fixed.

## Pins

| Item | Value |
|---|---|
| pico-hsm | `v6.6` / `251b35dd9c4fd929923fc3b192f6793826efeaef` |
| pico-keys-sdk | `44ee0254165d6338e27e6739c19c648f83b5c6c9` (pinned by v6.6 submodule) |
| ESP-IDF | v5.5 (via `espressif/idf:v5.5` Docker image) |
| master (abandoned build) | `1ad844413636e95297c4f23fea90afaa4db3c581` |

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

Requires Docker.

```
./build.sh v6.6 custom     # v6.6 + patches — the production firmware
./build.sh v6.6 stock      # unmodified reference build
./build.sh master custom   # master + patches + component stubs; builds but fails key import, see above
```

Output lands in `artifacts/<ref>-<variant>/` as `pico_hsm_esp32s3.bin`,
`SHA256SUMS`, and `build-info.txt`. An existing artifact directory is
not rebuilt — delete it to rebuild.

## Flash

Hold BOOT button, tap RESET, release BOOT to enter download mode.

Take an eFuse baseline before flashing —
`espefuse --port <port> summary > efuse-<serial>.txt` — those bits are
irreversible and the baseline is what later shows whether a unit was
ever hardened.

```
esptool --port <port> erase-flash
esptool --port <port> write-flash 0x0 artifacts/v6.6-custom/pico_hsm_esp32s3.bin
```

Unplug and replug normally to boot the new firmware. Confirm with
`opensc-tool -an`, which reports `SmartCard-HSM version 6.6`.
