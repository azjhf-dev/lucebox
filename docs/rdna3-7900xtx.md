# Lucebox on the RX 7900 XTX (RDNA3, gfx1100)

Fork addition, branch `rdna3-7900xtx` on `azjhf-dev/lucebox`.
Upstream pinned at `d0e947392d12efbe7a38a16c59b69e1725050fa8`
(Luce-Org/lucebox main, 2026-11-25, "fix(ci): ignore exited and zombie KFD
PIDs in box_step.sh"). Nothing here is upstreamed.

## Why

Lucebox's Inkling 2 Mini launch profiles cover gfx1201 (R9700) and gfx1151
(Strix Halo) only. The HIP build itself already supports the RX 7900 XT/XTX
(upstream README: "The HIP build also runs on the RX 7900 XT and XTX"), but a
7900 XTX-only host matched no Inkling 2 Mini profile, so the model would not
auto-launch with sane flags. This branch adds that profile plus a launch
script and an environment check.

## What this branch adds

- `share/model_cards/inkling-2-mini.json`: new profile `inkling2-7900xtx`
  (gfx1100, 22 GiB min VRAM, `--target-device hip:0`, `--max-ctx 65536`,
  Q8_0 KV), appended to `default_profile`.
- `server/scripts/serve_inkling2_7900xtx.sh`: house-style launcher, env
  overrides `INKLING2_CONTEXT` / `INKLING2_PORT` / `LUCE_BUILD_DIR`.
- `server/scripts/check_7900xtx.sh`: read-only environment check (GPU arch,
  ROCm >= 7.2, VRAM), writes `results-7900xtx.json`. Run this first and send
  the JSON back.

No kernel changes. Upstream's HIP kernels are tuned for gfx1201 and gfx1151;
gfx1100 runs the generic paths.

## Build (on the 7900 XTX box)

Needs Linux with ROCm 7.2 or newer.

```bash
git clone --recurse-submodules https://github.com/azjhf-dev/lucebox.git
cd lucebox
git checkout rdna3-7900xtx
bash server/scripts/check_7900xtx.sh   # sanity: gfx1100 seen, ROCm >= 7.2
cmake -S server -B server/build-hip -DCMAKE_BUILD_TYPE=Release \
  -DLUCE_GPU_BACKEND=hip -DLUCE_HIP_ARCHITECTURES=gfx1100
cmake --build server/build-hip --target luce_server -j"$(nproc)"
```

## Run

```bash
hf download Lucebox/Inkling-2-Mini-Fast-GGUF \
  Inkling-2-Mini-Fast-IQ4_NL.gguf mtp.safetensors --local-dir models/inkling2
bash server/scripts/serve_inkling2_7900xtx.sh models/inkling2/Inkling-2-Mini-Fast-IQ4_NL.gguf
```

The DSpark speculator (`mtp.safetensors`) is auto-discovered beside the GGUF.

## VRAM budget on 24 GB (from upstream's published figures, estimates)

Q8_0 KV for Inkling 2 Mini measures 4,556 MiB at 262K context
(~17.4 MiB per 1K tokens); the DSpark drafter holds ~3,072 MiB.

| GGUF | Weights | DSpark | KV at 64K | Total (est.) | Fits 24 GB? |
|---|---|---|---|---|---|
| IQ4_NL (benchmark build) | 16.4 GiB | ~3.0 GiB | ~1.1 GiB | ~20.6 GiB | Yes, default |
| IQ4_NL-16GB | 14.0 GiB | ~3.0 GiB | ~1.1 GiB | ~18.2 GiB | Yes; room for 128K-262K |
| UD-Q8_K_XL | 21.3 GiB | ~3.0 GiB | ~1.1 GiB | ~25.5 GiB | No |

With the 16GB build, `INKLING2_CONTEXT=131072` (~+1.1 GiB) or
`INKLING2_CONTEXT=262144` (~+3.4 GiB) should still fit; verify on hardware.

## Performance expectations (not measured)

Measured upstream numbers are all R9700 (gfx1201): 136.5 tok/s HTTP greedy,
155.4 peak dual-GPU, 81.7 strict AR, 3,628 tok/s prefill. The 7900 XTX has
more memory bandwidth (960 GB/s) than the R9700 but the kernels are not
tuned for gfx1100, so treat R9700 numbers as a ceiling, not a promise.
Upstream's own HIP_PERF_PLAN measured Qwen 3.8 27B decode on gfx1100 at
49.81 -> 76.02 tok/s (+53%) with `--ddtree-budget=8`; that flag tunes the
DFlash ddtree drafter, and whether it applies to Inkling's DSpark path is
unknown — test, don't assume.

Baseline to beat on this card (Ash's target): the 3090 reference runs
Inkling 2 Mini around 125 tok/s (LlamAmpere). Published 7900 XTX numbers
above that did not exist as of 2026-11-26; this port is the attempt.

## Fallback

The Fast GGUFs are plain Inkling 2 Mini architecture and load in stock
llama.cpp (HIP or Vulkan) and in the azjhf-dev Avalon fork (branch
inkling2-upstream-sync-1124, HIP RDNA3 flash attention at upstream parity)
today — slower than luce_server but a working baseline on the same card.

## Open items

- Everything above is compile/config-level; nothing has run on a real
  7900 XTX. First run: `check_7900xtx.sh`, then build, then serve and time
  a 256-token decode.
- The graph's Infinity Cache prefetch constant is written for the R9700's
  64 MB cache; the 7900 XTX has 96 MB. `LUCE_INKLING2_PREFETCH=1` is off by
  default either way — leave it off until baseline numbers exist.
- 7900 XT (20 GB) likely needs the IQ4_NL-16GB build and 32K-64K context;
  not covered by this profile.
