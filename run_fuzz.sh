#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-ash}" # usage: ./run_fuzz.sh [ash|hush]

if [[ "$TARGET" != "ash" && "$TARGET" != "hush" ]]; then
    echo "Usage: $0 [ash|hush]"
    exit 1
fi

if ! command -v bwrap >/dev/null 2>&1; then
    echo "bubblewrap (bwrap) is required for sandboxing but was not found." >&2
    echo "Install it first: sudo pacman -S bubblewrap" >&2
    exit 1
fi

ROOT_DIR="$(pwd)"
SRC_DIR="${ROOT_DIR}/busybox-${TARGET}"
OUT_DIR="${ROOT_DIR}/out_${TARGET}"
IN_DIR="${ROOT_DIR}/in_${TARGET}"
DICT_FILE="${ROOT_DIR}/dict/${TARGET}.dict"

export CC="afl-clang-fast"
export AFL_USE_ASAN=1
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=1:allocator_may_return_null=1:detect_stack_use_after_return=1"

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

SCRATCH_DIR="/tmp"

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

echo "=== Build succeeded. Launching AFL++ for ${TARGET} (sandboxed) ==="

# Execution harness parameters:
# -m none: Disable memory limit (essential for ASAN address space reservation)
# -t 500+: Generous timeout due to ASAN instrumentation overhead ('+' skips
#          hangs instead of treating them as a hard failure)
# '@@' is passed as the SCRIPT FILE argument, not combined with '-s'.
# '-s' tells ash/hush to read from stdin, which conflicts with AFL feeding
# input via a file path substituted for '@@' -- you can't do both at once.
# Fuzz the *unstripped* binary. Stripping only removes .symtab metadata --
# AFL instrumentation is unaffected either way -- but keeping symbols means
# readable crash/ASan backtraces later instead of bare addresses.
#
# bwrap flags:
#   --ro-bind / /        mount the whole host filesystem read-only
#   --dev /dev, --proc /proc   minimal working /dev and /proc
#   --tmpfs /dev/shm      AFL++ needs working shared memory for the coverage
#                         bitmap; give it a proper tmpfs-backed /dev/shm
#                         rather than whatever --dev provided
#   --tmpfs /tmp          some libc/ASAN paths assume a writable /tmp
#   --tmpfs "$SCRATCH_DIR" the ONLY place the fuzzed shell can actually
#                         write anything -- RAM-backed, gone on exit
#   --chdir "$SCRATCH_DIR" run the target from inside that tmpfs
#   --bind "$OUT_DIR" "$OUT_DIR"   override the read-only root just for
#                         AFL's real output dir, so results are durable
#   --unshare-net         no network namespace at all
#   --die-with-parent     sandbox tears down cleanly if afl-fuzz is killed
exec bwrap \
    --ro-bind / / \
    --dev /dev \
    --proc /proc \
    --tmpfs /dev/shm \
    --tmpfs "$SCRATCH_DIR" \
    --chdir "$SCRATCH_DIR" \
    --bind "$OUT_DIR" "$OUT_DIR" \
    --unshare-net \
    --die-with-parent \
    -- \
    afl-fuzz \
        -i "$IN_DIR" \
        -o "$OUT_DIR" \
        "${DICT_ARGS[@]}" \
        -m none \
        -t 500+ \
        -- "${SRC_DIR}/busybox_unstripped" "$TARGET" "@@"
