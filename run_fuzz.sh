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
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' .config

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

make CC="$CC" -j"$(nproc)"

cd "$ROOT_DIR"
mkdir -p "$OUT_DIR"

SCRATCH_DIR="${ROOT_DIR}/sandbox_${TARGET}"
rm -rf "$SCRATCH_DIR"
mkdir -p "$SCRATCH_DIR"
cd "$SCRATCH_DIR"

mkdir -p "$IN_DIR"
if [[ -z "$(ls -A "$IN_DIR" 2>/dev/null)" ]]; then
    echo "echo hello" > "$IN_DIR/seed1"
fi

DICT_ARGS=()
if [[ -f "$DICT_FILE" ]]; then
    DICT_ARGS=(-x "$DICT_FILE")
else
    echo "Warning: dictionary file not found at $DICT_FILE, continuing without -x" >&2
fi

echo "=== Build succeeded. Launching AFL++ for ${TARGET} ==="

# Execution harness parameters:
# -m none: Disable memory limit (essential for ASAN address space reservation)
# -t 500+: Generous timeout due to ASAN instrumentation overhead ('+' skips
#          hangs instead of treating them as a hard failure)
# '@@' is passed as the SCRIPT FILE argument, not combined with '-s'.
# '-s' tells ash/hush to read from stdin, which conflicts with AFL feeding
# input via a file path substituted for '@@' — you can't do both at once.
# Fuzz the *unstripped* binary. busybox's build produces busybox_unstripped
# first, then strips it into ./busybox as the "for distribution" artifact.
# Stripping only removes the .symtab metadata (nm won't see __afl_* there
# anymore) -- the actual AFL instrumentation is untouched either way -- but
# for fuzzing you want symbols kept around so crashes/ASan reports are
# readable later instead of just bare addresses.
exec afl-fuzz \
    -i "$IN_DIR" \
    -o "$OUT_DIR" \
    "${DICT_ARGS[@]}" \
    -m none \
    -t 500+ \
    -- "${SRC_DIR}/busybox_unstripped" "$TARGET" "@@"
