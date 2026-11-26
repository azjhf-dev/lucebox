#!/usr/bin/env bash
# Environment check for running Lucebox on one RX 7900 XTX (gfx1100).
# Prints findings and writes results-7900xtx.json next to this script.
# Read-only: builds nothing, loads no model, needs no root.
# Added in the azjhf-dev fork, branch rdna3-7900xtx.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${CHECK_OUT:-$script_dir/results-7900xtx.json}

gfx_seen=""
rocm_version=""
vram_total_mb=""
notes=()

if command -v amd-smi >/dev/null 2>&1; then
    gfx_seen=$(amd-smi list 2>/dev/null | grep -oi 'gfx[0-9a-z]*' | sort -u | tr '\n' ' ' | sed 's/ $//')
elif command -v rocminfo >/dev/null 2>&1; then
    gfx_seen=$(rocminfo 2>/dev/null | grep -oi 'gfx[0-9a-z]*' | sort -u | tr '\n' ' ' | sed 's/ $//')
else
    notes+=("neither amd-smi nor rocminfo found; is ROCm installed and on PATH?")
fi

if command -v amd-smi >/dev/null 2>&1; then
    rocm_version=$(amd-smi version 2>/dev/null | grep -i 'rocm' | head -1 | awk '{print $NF}')
fi
if [[ -z $rocm_version && -f /opt/rocm/.info/version ]]; then
    rocm_version=$(cat /opt/rocm/.info/version)
fi

if command -v amd-smi >/dev/null 2>&1; then
    vram_total_mb=$(amd-smi metric -m 2>/dev/null | grep -i 'total' | head -1 | grep -o '[0-9]*' | head -1)
fi

case " $gfx_seen " in
    *" gfx1100 "*) notes+=("gfx1100 found: this branch's inkling2-7900xtx profile applies") ;;
    *) notes+=("gfx1100 NOT found; this check is for the RX 7900 XTX") ;;
esac

if [[ -n $rocm_version ]]; then
    major=$(echo "$rocm_version" | cut -d. -f1)
    minor=$(echo "$rocm_version" | cut -d. -f2)
    if [[ $major -lt 7 || ( $major -eq 7 && $minor -lt 2 ) ]]; then
        notes+=("ROCm $rocm_version is older than the required 7.2")
    fi
else
    notes+=("ROCm version unknown")
fi

python3 - "$out" "$gfx_seen" "$rocm_version" "$vram_total_mb" "${notes[@]}" <<'PY'
import json, sys
out, gfx, rocm, vram = sys.argv[1:5]
notes = sys.argv[5:]
data = {
    "check": "lucebox rdna3-7900xtx environment",
    "gfx_targets_seen": gfx.split() if gfx else [],
    "rocm_version": rocm or None,
    "vram_total_mb": int(vram) if vram.isdigit() else None,
    "notes": notes,
}
with open(out, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(json.dumps(data, indent=2))
PY
