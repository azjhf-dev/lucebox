#!/usr/bin/env bash
# Launch Inkling 2 Mini (Fast or base GGUF) monolithic on one RX 7900 XTX
# (gfx1100, 24 GB). Added in the azjhf-dev fork, branch rdna3-7900xtx.
# Untested on hardware as of 2026-11-26; see docs/rdna3-7900xtx.md.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 TARGET_GGUF [luce_server arguments...]" >&2
    echo "example: $0 models/inkling2/Inkling-2-Mini-Fast-IQ4_NL.gguf" >&2
    exit 2
fi

target=$1
shift 1

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
server_dir=$(cd "$script_dir/.." && pwd)
build_dir=${LUCE_BUILD_DIR:-$server_dir/build-hip}
binary=$build_dir/luce_server

if [[ ! -f $target ]]; then
    echo "missing required file: $target" >&2
    echo "download with: hf download Lucebox/Inkling-2-Mini-Fast-GGUF Inkling-2-Mini-Fast-IQ4_NL.gguf mtp.safetensors --local-dir models/inkling2" >&2
    exit 1
fi
if [[ ! -f $binary || ! -x $binary ]]; then
    echo "missing executable: $binary" >&2
    echo "build with: cmake -S server -B server/build-hip -DCMAKE_BUILD_TYPE=Release -DLUCE_GPU_BACKEND=hip -DLUCE_HIP_ARCHITECTURES=gfx1100 && cmake --build server/build-hip --target luce_server -j\"\$(nproc)\"" >&2
    exit 1
fi

# 64K context keeps the 16.4 GiB IQ4_NL build + DSpark drafter + Q8_0 KV
# inside 24 GB. Raise only with the 14.0 GiB IQ4_NL-16GB build; see the doc.
context=${INKLING2_CONTEXT:-65536}
port=${INKLING2_PORT:-8080}

exec "$binary" "$target" \
    --profile inkling2-7900xtx \
    --max-ctx "$context" \
    --port "$port" \
    "$@"
