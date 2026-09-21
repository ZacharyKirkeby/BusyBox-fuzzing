#!/usr/bin/env bash
set -euo pipefail

# usage: ./monitor_disk.sh [ash|hush] [warn_threshold_gb]
TARGET="${1:-ash}"
WARN_GB="${2:-10}"
OUT_DIR="$(pwd)/out_${TARGET}"

if [[ ! -d "$OUT_DIR" ]]; then
    echo "No such output dir: $OUT_DIR" >&2
    exit 1
fi

echo "Monitoring $OUT_DIR (warning above ${WARN_GB}GB). Ctrl-C to stop."
echo

while true; do
    if [[ -f "$OUT_DIR/default/fuzzer_stats" ]]; then
        execs=$(grep -m1 '^execs_done' "$OUT_DIR/default/fuzzer_stats" | awk '{print $3}')
        crashes=$(find "$OUT_DIR/default/crashes" -type f ! -name 'README*' 2>/dev/null | wc -l)
        hangs=$(find "$OUT_DIR/default/hangs" -type f ! -name 'README*' 2>/dev/null | wc -l)
        queue=$(find "$OUT_DIR/default/queue" -type f 2>/dev/null | wc -l)
    else
        execs="?"; crashes="?"; hangs="?"; queue="?"
    fi

    size_kb=$(du -sk "$OUT_DIR" 2>/dev/null | cut -f1)
    size_gb=$(awk -v kb="$size_kb" 'BEGIN{printf "%.2f", kb/1048576}')

    ts=$(date '+%Y-%m-%d %H:%M:%S')
    line="[$ts] size=${size_gb}GB execs=${execs} queue=${queue} crashes=${crashes} hangs=${hangs}"
    echo "$line"

    if awk -v s="$size_gb" -v w="$WARN_GB" 'BEGIN{exit !(s>w)}'; then
        echo "  !! Output directory has exceeded ${WARN_GB}GB."
        echo "     Safe to prune: hangs/ (least valuable finds)."
        echo "     Do NOT touch queue/ or crashes/ while afl-fuzz is running --"
        echo "     it actively reads/writes there; deleting live files under it"
        echo "     can crash the fuzzer or corrupt its resume state."
    fi

    sleep 300
done
