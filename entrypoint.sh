#!/bin/bash
set -euo pipefail

# ── 内存检查 ───────────────────────────────────────────────
MEM_MB=$(awk '/MemAvailable/{printf "%.0f",$2/1024}' /proc/meminfo)
echo "[INFO] 可用内存: ${MEM_MB}MB | ctx: $LLAMA_CTX_SIZE | threads: $LLAMA_THREADS"
[ "$MEM_MB" -lt 1500 ] && echo "[WARN] 可用内存低于 1500MB，可能 OOM"

# ── 启动 llama-server ──────────────────────────────────────
exec llama-server \
    -m          "$LLAMA_MODEL"   \
    --mmproj    "$LLAMA_MMPROJ"  \
    --host      "$LLAMA_HOST"    \
    --port      "$LLAMA_PORT"    \
    --ctx-size  "$LLAMA_CTX_SIZE"  \
    --threads   "$LLAMA_THREADS"   \
    --threads-batch "$LLAMA_THREADS" \
    --batch-size    "$LLAMA_BATCH_SIZE"  \
    --ubatch-size   "$LLAMA_UBATCH_SIZE" \
    --n-gpu-layers  0  \
    --temp          0  \
    --log-disable
