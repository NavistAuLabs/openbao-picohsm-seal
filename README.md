# wavehsm

Custom pico-hsm firmware build for the Waveshare ESP32-S3-LCD-1.47 seal
dongles used by the-openbao-kit's pkcs11 seal (homelab estate).

## Customizations over upstream

| Change | Why |
|---|---|
| `-DFORCE_BUTTON_WAIT` | Gate rescue-applet destructive APDUs (eFuse burn `0x1D`, PHY write `0x1C`, BOOTSEL reboot) behind a physical button press. Mitigates the unauthenticated-permanent-destruction risk documented in the-openbao-kit README. Does NOT affect normal PKCS#11 operations — auto-unseal is unaffected. |
| `NEOPIXEL_PIN` → `GPIO_NUM_38` | Waveshare ESP32-S3-LCD-1.47 wires its WS2812B RGB LED to GPIO 38 (schematic: net `RGB_IO`, component LED1). Upstream default `GPIO_NUM_48` is the LCD backlight on this board. |
| Build from master, not v6.6 | v6.6 (2026-04-07) is ~30 security fixes behind master on the pre-authentication USB parsing surface. No release is imminent (114+ days, pattern of major-version gaps). |

## Pins

| Item | Value |
|---|---|
| pico-hsm | `1ad844413636e95297c4f23fea90afaa4db3c581` (master, 2026-07-27) |
| pico-keys-sdk | `843a3dc593b7eec0dd561c5255a14c89374c804c` (pinned by pico-hsm submodule) |
| ESP-IDF | v5.5 (via `espressif/idf:v5.5` Docker image) |
| v6.6 tag (for reference) | `251b35dd9c4fd929923fc3b192f6793826efeaef` |

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

```
esptool --port <port> erase-flash
esptool --port <port> write-flash 0x0 output/pico_hsm_wavehsm_esp32s3.bin
```

Verify: `opensc-tool -an` should report SmartCard-HSM.

## Vendoring back to the-openbao-kit

After a successful build and bench test, copy the binary into
`the-openbao-kit/files/firmware/pico-hsm/` with SHA256SUMS and update
`README-PROVENANCE.md` to reflect the custom build.
