#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-ash}" # usage: ./run_fuzz.sh [ash|hush]

if [[ "$TARGET" != "ash" && "$TARGET" != "hush" ]]; then
    echo "Usage: $0 [ash|hush]"
    exit 1
fi

ROOT_DIR="$(pwd)"
SRC_DIR="${ROOT_DIR}/busybox-${TARGET}"
OUT_DIR="${ROOT_DIR}/out_${TARGET}"
IN_DIR="${ROOT_DIR}/in_${TARGET}"
DICT_FILE="${ROOT_DIR}/dict/${TARGET}.dict"

export CC="afl-clang-fast"
export AFL_USE_ASAN=1
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0"

if [[ ! -d "$SRC_DIR" ]]; then
    git clone --depth 1 git://busybox.net/busybox.git "$SRC_DIR"
fi

cd "$SRC_DIR"
make distclean || true

make defconfig

sed -i 's/CONFIG_FEATURE_EDITING=y/# CONFIG_FEATURE_EDITING is not set/' .config
sed -i 's/CONFIG_FEATURE_TAB_COMPLETION=y/# CONFIG_FEATURE_TAB_COMPLETION is not set/' .config
sed -i 's/CONFIG_FEATURE_EDITING_FANCY_PROMPT=y/# CONFIG_FEATURE_EDITING_FANCY_PROMPT is not set/' .config

if [[ "$TARGET" == "ash" ]]; then
    sed -i 's/# CONFIG_ASH is not set/CONFIG_ASH=y/' .config
    sed -i 's/CONFIG_HUSH=y/# CONFIG_HUSH is not set/' .config
    sed -i 's/CONFIG_SH_IS_HUSH=y/# CONFIG_SH_IS_HUSH is not set/' .config
    sed -i 's/# CONFIG_SH_IS_ASH is not set/CONFIG_SH_IS_ASH=y/' .config
else
    sed -i 's/# CONFIG_HUSH is not set/CONFIG_HUSH=y/' .config
    sed -i 's/CONFIG_ASH=y/# CONFIG_ASH is not set/' .config
    sed -i 's/CONFIG_SH_IS_ASH=y/# CONFIG_SH_IS_ASH is not set/' .config
    sed -i 's/# CONFIG_SH_IS_HUSH is not set/CONFIG_SH_IS_HUSH=y/' .config
fi

make oldconfig
make -j"$(nproc)"

cd "$ROOT_DIR"
mkdir -p "$OUT_DIR"

echo "=== Build succeeded. Launching AFL++ for ${TARGET} ==="

# Execution harness parameters:
# -m none: Disable memory limit (essential for ASAN address space reservation)
# -t 200+: Generous timeout due to ASAN instrumentation overhead
# Pass input file directly using '@@' so the shell treats it as a script argument
exec afl-fuzz \
    -i "$IN_DIR" \
    -o "$OUT_DIR" \
    -x "$DICT_FILE" \
    -m none \
    -t 500+ \
    -- "${SRC_DIR}/busybox" "$TARGET" -s "@@"

