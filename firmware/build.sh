#!/usr/bin/env bash
# firmware/build.sh — reproducible build of pico-hsm firmware
# for Waveshare ESP32-S3-LCD-1.47 seal dongles.
#
# Outputs to artifacts/<ref>-<variant>/ so each build is preserved.
#
# Usage:
#   ./build.sh v6.6 custom       # v6.6 + our patches (LED, button, tinyusb pin)
#   ./build.sh v6.6 stock        # v6.6 unmodified (reference build)
#   ./build.sh master custom     # master + our patches + component stubs
#
# Artifacts land in artifacts/<ref>-<variant>/:
#   pico_hsm_esp32s3.bin
#   SHA256SUMS
#   build-info.txt

set -euo pipefail

REF="${1:?usage: $0 <ref> <stock|custom>}"
VARIANT="${2:?usage: $0 <ref> <stock|custom>}"

IDF_TAG="v5.5"

# resolve ref to a commit
case "$REF" in
    v6.6)
        PICO_HSM_COMMIT="251b35dd9c4fd929923fc3b192f6793826efeaef"
        CLONE_ARGS="--branch v6.6"
        ;;
    master)
        PICO_HSM_COMMIT="1ad844413636e95297c4f23fea90afaa4db3c581"
        CLONE_ARGS=""
        ;;
    *)
        PICO_HSM_COMMIT="$REF"
        CLONE_ARGS=""
        ;;
esac

SHORT_COMMIT="${PICO_HSM_COMMIT:0:8}"
case "$REF" in
    v*) ARTIFACT_NAME="${REF}-${VARIANT}" ;;
    *)  ARTIFACT_NAME="${SHORT_COMMIT}-${VARIANT}" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/artifacts/${ARTIFACT_NAME}"
mkdir -p "${OUT_DIR}"

if [ -f "${OUT_DIR}/pico_hsm_esp32s3.bin" ]; then
    echo "Artifact already exists: ${OUT_DIR}/"
    shasum -a 256 "${OUT_DIR}/pico_hsm_esp32s3.bin"
    echo "Delete the directory to rebuild."
    exit 0
fi

echo "=== firmware build: ${ARTIFACT_NAME} ==="
echo "pico-hsm: ${REF} (${SHORT_COMMIT})"
echo "variant:  ${VARIANT}"
echo "esp-idf:  ${IDF_TAG}"
echo "output:   ${OUT_DIR}"
echo

docker run --rm \
  -v "${OUT_DIR}:/out" \
  -e PICO_HSM_COMMIT="${PICO_HSM_COMMIT}" \
  -e VARIANT="${VARIANT}" \
  -e CLONE_ARGS="${CLONE_ARGS}" \
  espressif/idf:${IDF_TAG} \
  bash -c '
set -euo pipefail

echo "--- clone pico-hsm ---"
git clone --recursive ${CLONE_ARGS} \
  https://github.com/polhenarejos/pico-hsm.git /build/pico-hsm
cd /build/pico-hsm
git checkout "${PICO_HSM_COMMIT}"
git submodule update --init --recursive

actual=$(git rev-parse HEAD)
if [ "${actual}" != "${PICO_HSM_COMMIT}" ]; then
  echo "FATAL: checkout resolved to ${actual}, expected ${PICO_HSM_COMMIT}" >&2
  exit 1
fi

# --- version-specific build fixes (always applied) ---

# master SDK registers ESP-IDF components whose sources are never fetched
if [ -d pico-keys-sdk/config/esp32/components/cjson ]; then
  has_cjson_src=$(find pico-keys-sdk/third-party/cjson -name "*.c" 2>/dev/null | head -1 || true)
  if [ -z "$has_cjson_src" ]; then
    echo "--- stub unused ESP components (master SDK) ---"
    for comp in cjson tinycbor mldsa44 mldsa65 mldsa87 mlkem512 mlkem768 mlkem1024; do
      if [ -d "pico-keys-sdk/config/esp32/components/${comp}" ]; then
        echo "idf_component_register()" > "pico-keys-sdk/config/esp32/components/${comp}/CMakeLists.txt"
      fi
    done
  fi
fi

# tinyusb 0.21.0 breaks macOS CCID descriptor handling
echo "--- pin tinyusb <0.21.0 ---"
sed -i "/espressif\/esp_tinyusb/a\\  espressif/tinyusb: \">=0.15.0,<0.21.0\"" \
  pico-keys-sdk/config/esp32/components/pico-keys-sdk/idf_component.yml
echo "  OK"

# --- custom patches (only for custom variant) ---

if [ "${VARIANT}" = "custom" ]; then
  echo "--- patch: NEOPIXEL_PIN GPIO_NUM_48 -> GPIO_NUM_38 ---"
  sed -i "s/#define NEOPIXEL_PIN GPIO_NUM_48/#define NEOPIXEL_PIN GPIO_NUM_38/g" \
    pico-keys-sdk/src/led/led.c \
    pico-keys-sdk/src/led/led_neopixel.c
  grep -q GPIO_NUM_38 pico-keys-sdk/src/led/led.c || { echo "FATAL: led.c patch failed" >&2; exit 1; }
  grep -q GPIO_NUM_38 pico-keys-sdk/src/led/led_neopixel.c || { echo "FATAL: led_neopixel.c patch failed" >&2; exit 1; }
  echo "  OK"

  echo "--- patch: FORCE_BUTTON_WAIT ---"
  sed -i "/^if(ESP_PLATFORM)/,/^endif()/{
    s/project(pico_hsm)/project(pico_hsm)\n    add_compile_definitions(FORCE_BUTTON_WAIT)/
  }" CMakeLists.txt
  grep -q FORCE_BUTTON_WAIT CMakeLists.txt || { echo "FATAL: CMakeLists.txt patch failed" >&2; exit 1; }
  echo "  OK"
fi

echo "--- build esp32s3 ---"
idf.py set-target esp32s3
idf.py all

echo "--- merge flash image ---"
cd build
esptool.py --chip ESP32-S3 merge_bin -o /out/pico_hsm_esp32s3.bin @flash_args
cd ..

echo "--- checksums ---"
sha256sum /out/pico_hsm_esp32s3.bin | tee /out/SHA256SUMS

echo
echo "=== build complete ==="
'

# record build info
cat > "${OUT_DIR}/build-info.txt" <<INFO
ref: ${REF}
commit: ${PICO_HSM_COMMIT}
variant: ${VARIANT}
idf: ${IDF_TAG}
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
sha256: $(shasum -a 256 "${OUT_DIR}/pico_hsm_esp32s3.bin" | awk '{print $1}')
INFO

echo
echo "Output: ${OUT_DIR}/"
ls -la "${OUT_DIR}/"
cat "${OUT_DIR}/build-info.txt"
