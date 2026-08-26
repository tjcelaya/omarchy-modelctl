# modelctl

An Omarchy bar plugin for running local LLMs with llama.cpp, and for seeing every
running [herdr](https://github.com/) coding agent at a glance.

    󰚩 gpt-oss-20b  │  󱃒 claude ~/src ●  󱃒 opencode ~/src/snake

- **Model segment** — left-click opens a menu of local models, middle-click stops the
  server, right-click tails its journal.
- **Agent segments** — one per running herdr agent, live. Click to focus that pane.
  `●` marks the focused agent; idle agents are dimmed.

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
