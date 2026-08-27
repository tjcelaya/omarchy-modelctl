# modelctl

An Omarchy bar plugin for running local LLMs with llama.cpp, and for seeing every
running [herdr](https://github.com/) coding agent at a glance.

    󰚩oss20  󰋩  󱃒2

- **Model** (`󰚩` + abbreviation) — left-click for the model menu, middle-click stops
  the server, right-click tails its journal.
- **Images** (`󰋩`) — left-click generates one image with the model selected in the
  menu's `stable-diffusion` section; right-click toggles a resident SD-Turbo
  `sd-server` on :8091. Dim = one-shot, bright = resident.
- **Agents** (`󱃒` + count) — click for the menu, which lists every running herdr
  agent with its cwd and status. Selecting one focuses its pane.

Names, paths and status live in the menu; the bar stays to icons and short tags.

### Image generation

Prompts via Omarchy's native input popup, saves to `~/Pictures/generated` as
`<timestamp>-<prompt-slug>.png`, then opens it. Override the folder with
`MODELCTL_IMAGE_DIR` or the `imageDir` setting; `SD_STEPS`, `SD_W`, `SD_H` tune the rest.

Models (`modelctl-image --list`; pick in the menu or `modelctl-image --<id> "prompt"`).
Measured 2026-08-26 at native res on the 23,552 MiB pool, `--vae-tiling` on:

| id | model | res | steps | wall | peak GPU | beside gpt-oss-20b (~14.4 GiB)? |
|---|---|---|---|---|---|---|
| `turbo` | SD-Turbo | 512² | 4 | ~9 s | ~4.5 GiB | yes |
| `sd15` | SD 1.5 | 512² | 20 | ~32 s | ~4 GiB | yes |
| `sdxl` | SDXL-Lightning 4-step | 1024² | 4 | ~36 s | 7.6 GiB | yes |
| `zimage` | Z-Image-Turbo Q8 + Qwen3-4B TE | 1024² | 8 | ~3m20 | 11.6 GiB | no — fits beside `fast` |
| `flux` | Flux.1-schnell Q8 | 1024² | 4 | ~2m30 | 18.6 GiB | no |
| `chroma` | Chroma1-HD Q8 | 1024² | 20 | ~22 min | 15.6 GiB | no |

Before generating, the script reads the amdgpu memory counters; if the model's measured
peak would not fit next to what is loaded, it stops the running `modelctl@*` LLM unit
and starts it again afterwards (verified: gpt-oss-20b active again after a Flux run,
2m35 total). So `zimage` runs beside `fast` untouched but parks `default`; `flux` and
`chroma` (`⏏` in the menu) park anything.
Checkpoints live in `$MODELCTL_SD_DIR` (default `/mnt/data/stable-diffusion-models`).

Deliberately separate from Omarchy's built-in `omarchy.agents`, which reports Claude
subscription usage rather than running sessions.

## Install

    git clone <this repo> ~/src/omarchy-modelctl
    ~/src/omarchy-modelctl/install.sh
    omarchy plugin enable tj.modelctl
    omarchy bar move tj.modelctl --section center

Everything is symlinked, so `git pull` updates in place.

## Requirements

- `llama-cpp` + `ggml-vulkan` (or another ggml backend)
- GGUF models under `~/.lmstudio/models/` (or set `MODELCTL_MODEL_DIR`)
- `herdr` for the agent list — optional; without it the widget shows only the model
- systemd user session

## Usage

    modelctl              # default model, foreground
    modelctl vision       # a different mode
    modelctl list         # modes with measured context + free memory
    systemctl --user start modelctl@vision

`bin/modelctl` is where model paths and context sizes live. **They are tuned for one
machine** (Radeon 760M, 23.5 GiB Vulkan pool) — re-derive them for yours; see
`TUNING.md`.

## Settings

Exposed through the plugin manifest, editable in Omarchy's settings UI:

| key | default | meaning |
|---|---|---|
| `refreshIntervalSec` | 5 | how often to re-read state |
| `port` | 8090 | llama-server port |
| `showCwd` | true | show each agent's working directory |

## Status

**v0.1.0, works on one machine.** The QML widget is new and less battle-tested than
the shell scripts behind it. Known gaps:

- Model list in `bin/modelctl` is hardcoded, not discovered from disk.
- Context sizes are measured values for a specific GPU, not computed from free VRAM.
- Only herdr-managed agents are listed; anything started outside herdr is invisible.
- The dropdown still uses Omarchy's menu via a generated JSONC file, because the
  menu's `provider` mechanism is a closed set hardcoded in `Menu.qml`. A native
  popup panel would remove that.
