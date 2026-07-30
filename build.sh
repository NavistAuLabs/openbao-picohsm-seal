#!/usr/bin/env bash
# wavehsm/build.sh — reproducible build of pico-hsm firmware
# for Waveshare ESP32-S3-LCD-1.47 seal dongles.
#
# Based on v6.6 (the last release that builds cleanly and works with
# macOS's built-in CCID driver). Customizations:
#   1. -DFORCE_BUTTON_WAIT — presence gate on rescue-applet destructive APDUs
#   2. NEOPIXEL_PIN GPIO_NUM_38 — correct LED pin for this board
#
# Usage: ./build.sh [output-dir]   (default: ./output/)

set -euo pipefail

PICO_HSM_TAG="v6.6"
PICO_HSM_COMMIT="251b35dd9c4fd929923fc3b192f6793826efeaef"
IDF_TAG="v5.5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-${SCRIPT_DIR}/output}"
mkdir -p "${OUT_DIR}"

echo "=== wavehsm build ==="
echo "pico-hsm: ${PICO_HSM_TAG} (${PICO_HSM_COMMIT})"
echo "esp-idf:  ${IDF_TAG}"
echo "output:   ${OUT_DIR}"
echo

docker run --rm \
  -v "${OUT_DIR}:/out" \
  -e PICO_HSM_TAG="${PICO_HSM_TAG}" \
  -e PICO_HSM_COMMIT="${PICO_HSM_COMMIT}" \
  espressif/idf:${IDF_TAG} \
  bash -c '
set -euo pipefail

echo "--- clone pico-hsm ${PICO_HSM_TAG} ---"
git clone --recursive --branch "${PICO_HSM_TAG}" \
  https://github.com/polhenarejos/pico-hsm.git /build/pico-hsm
cd /build/pico-hsm

actual=$(git rev-parse HEAD)
if [ "${actual}" != "${PICO_HSM_COMMIT}" ]; then
  echo "FATAL: tag ${PICO_HSM_TAG} resolved to ${actual}, expected ${PICO_HSM_COMMIT}" >&2
  exit 1
fi

echo "--- patch: NEOPIXEL_PIN GPIO_NUM_48 -> GPIO_NUM_38 ---"
sed -i "s/#define NEOPIXEL_PIN GPIO_NUM_48/#define NEOPIXEL_PIN GPIO_NUM_38/g" \
  pico-keys-sdk/src/led/led.c \
  pico-keys-sdk/src/led/led_neopixel.c
grep -q GPIO_NUM_38 pico-keys-sdk/src/led/led.c || { echo "FATAL: led.c patch failed" >&2; exit 1; }
grep -q GPIO_NUM_38 pico-keys-sdk/src/led/led_neopixel.c || { echo "FATAL: led_neopixel.c patch failed" >&2; exit 1; }
echo "  OK"

echo "--- pin esp_tinyusb to pre-1.7.6 (avoid API change that breaks CCID descriptor handling) ---"
sed -i "s/\"^1.7.6\"/\">=1.4.0,<1.7.6\"/" \
  pico-keys-sdk/config/esp32/components/pico-keys-sdk/idf_component.yml
sed -i "/espressif\/esp_tinyusb/a\\  espressif/tinyusb: \">=0.15.0,<0.21.0\"" \
  pico-keys-sdk/config/esp32/components/pico-keys-sdk/idf_component.yml
echo "  OK"

echo "--- patch: FORCE_BUTTON_WAIT ---"
sed -i "/^if(ESP_PLATFORM)/,/^endif()/{
  s/project(pico_hsm)/project(pico_hsm)\n    add_compile_definitions(FORCE_BUTTON_WAIT)/
}" CMakeLists.txt
grep -q FORCE_BUTTON_WAIT CMakeLists.txt || { echo "FATAL: CMakeLists.txt patch failed" >&2; exit 1; }
echo "  OK"

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
