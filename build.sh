#!/usr/bin/env bash
# wavehsm/build.sh — reproducible containerized build of pico-hsm firmware
# for Waveshare ESP32-S3-LCD-1.47 seal dongles.
#
# Customizations over upstream:
#   1. -DFORCE_BUTTON_WAIT — gate rescue-applet destructive APDUs behind
#      a physical button press (eFuse burn, PHY write, BOOTSEL reboot)
#   2. NEOPIXEL_PIN GPIO_NUM_38 — Waveshare wires the WS2812B to GPIO38,
#      not the DevKitC-1's GPIO48 (which is LCD backlight on this board)
#
# Output: a merged flash image at offset 0, same layout as the upstream
# release asset. Flash with:
#   esptool --port <port> erase-flash
#   esptool --port <port> write-flash 0x0 <output>.bin
#
# Usage: ./build.sh [output-dir]   (default: ./output/)

set -euo pipefail

# --- pins ---
PICO_HSM_REPO="https://github.com/polhenarejos/pico-hsm.git"
PICO_HSM_COMMIT="1ad844413636e95297c4f23fea90afaa4db3c581"  # master 2026-07-27
PICO_HSM_DATE="2026-07-27"

IDF_VERSION="v5.5"

OUT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/output}"
mkdir -p "${OUT_DIR}"

echo "=== wavehsm build ==="
echo "pico-hsm: ${PICO_HSM_COMMIT} (${PICO_HSM_DATE})"
echo "esp-idf:  ${IDF_VERSION}"
echo "output:   ${OUT_DIR}"
echo

docker run --rm \
  -v "${OUT_DIR}:/out" \
  -e PICO_HSM_COMMIT="${PICO_HSM_COMMIT}" \
  espressif/idf:${IDF_VERSION} \
  bash -c '
set -euo pipefail

echo "--- clone pico-hsm ---"
git clone --recursive https://github.com/polhenarejos/pico-hsm.git /build/pico-hsm
cd /build/pico-hsm
git checkout "${PICO_HSM_COMMIT}"
git submodule update --init --recursive

actual=$(git rev-parse HEAD)
if [ "${actual}" != "${PICO_HSM_COMMIT}" ]; then
  echo "FATAL: checkout resolved to ${actual}, expected ${PICO_HSM_COMMIT}" >&2
  exit 1
fi

echo "--- patch: NEOPIXEL_PIN GPIO_NUM_48 -> GPIO_NUM_38 ---"
# Two sites in pico-keys-sdk where ESP32-S3 default is hardcoded
sed -i "s/#define NEOPIXEL_PIN GPIO_NUM_48/#define NEOPIXEL_PIN GPIO_NUM_38/g" \
  pico-keys-sdk/src/led/led.c \
  pico-keys-sdk/src/led/led_neopixel.c

# Verify patches applied
for f in pico-keys-sdk/src/led/led.c pico-keys-sdk/src/led/led_neopixel.c; do
  if ! grep -q "GPIO_NUM_38" "$f"; then
    echo "FATAL: NEOPIXEL_PIN patch failed in $f" >&2
    exit 1
  fi
  if grep -q "GPIO_NUM_48" "$f"; then
    echo "FATAL: GPIO_NUM_48 still present in $f after patch" >&2
    exit 1
  fi
done
echo "  led.c: OK"
echo "  led_neopixel.c: OK"

echo "--- patch: FORCE_BUTTON_WAIT ---"
# Add the define to the ESP_PLATFORM branch of CMakeLists.txt, right after
# project(pico_hsm). This is the cleanest injection point — it applies to
# all source files in the ESP32 build.
sed -i "/^if(ESP_PLATFORM)/,/^endif()/{
  s/project(pico_hsm)/project(pico_hsm)\n    add_compile_definitions(FORCE_BUTTON_WAIT)/
}" CMakeLists.txt

if ! grep -q "FORCE_BUTTON_WAIT" CMakeLists.txt; then
  echo "FATAL: FORCE_BUTTON_WAIT injection failed" >&2
  exit 1
fi
echo "  CMakeLists.txt: OK"

echo "--- build esp32s3 ---"
idf.py set-target esp32s3
idf.py all

echo "--- merge flash image ---"
cd build
esptool.py --chip ESP32-S3 merge_bin -o /out/pico_hsm_wavehsm_esp32s3.bin @flash_args
cd ..

echo "--- checksums ---"
sha256sum /out/pico_hsm_wavehsm_esp32s3.bin | tee /out/SHA256SUMS

echo
echo "=== build complete ==="
'

echo
echo "Output:"
ls -la "${OUT_DIR}/"
shasum -a 256 "${OUT_DIR}/pico_hsm_wavehsm_esp32s3.bin"
