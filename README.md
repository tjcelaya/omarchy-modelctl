# modelctl

An Omarchy bar plugin for running local LLMs with llama.cpp, and for seeing every
running [herdr](https://github.com/tjcelaya/herdr) coding agent at a glance.

![modelctl in the Omarchy bar and its menu](preview.png)

    󰚩oss20  󰋩  󱃒2

- **Model** (`󰚩` + abbreviation) — left-click opens the dropdown, middle-click stops
  the server, right-click tails its journal.
- **Images** (`󰋩` + tag of the selected model, or `chrm 37%` while one is generating) —
  left-click opens the dropdown, right-click generates an image with the selected model.
  Dim = one-shot, bright = resident `sd-server`.
- **Agents** (`󱃒` + count; glyph via the `agentsIcon` setting) — dim with no
  number when nothing is running, lit with a count otherwise. Click opens the agents
  submenu: every running coding agent with its directory and status; selecting one
  focuses it. Detected: herdr panes (status + pane focus) and any `claude`,
  `opencode`, `codex`, … process with a TTY inside a Hyprland window — a plain
  terminal, `omarchy agent`, etc. (window focus). Search matches agent name and
  every path segment. tmux panes: planned.

Names, paths and status live in the menu; the bar stays to icons and short tags.

### Image generation

Prompts via Omarchy's native input popup, saves to `~/Pictures/generated` as
`<timestamp>-<prompt-slug>.png`, then opens it. Override the folder with
`MODELCTL_IMAGE_DIR` or the `imageDir` setting; `SD_STEPS`, `SD_W`, `SD_H` tune the rest.

Image models are discovered like the LLMs: every checkpoint under `sd_dir`
(`~/.config/modelctl/models.conf`; `MODELCTL_SD_DIR` overrides) is classified by
family from its filename — SD 1.x, SD-Turbo, SDXL, SDXL-Lightning, Flux schnell/dev,
Chroma, Z-Image, SD3 — and paired with the VAE / text encoders that family needs from
the same folder (`flux_ae`, `t5-xxl`, `clip_l`, `clip_g`, a Qwen3-4B encoder for
Z-Image). One that lacks a companion shows `(✗)` with what is missing and will not run.
`[sd:<glob>]` sections overlay label, tag, steps/cfg/res, appended or replacement
flags — e.g. drop `--diffusion-fa` for one model that hangs your GPU. `modelctl-image
--list` shows them; pick in the menu or `modelctl-image --<id> "prompt"` (any unique
substring of the id works: `--chroma`). Nothing is measured for you: run `--check`
(below) and the menu shows the wall time and peak GPU use from *your* hardware.

Before generating, the script reads the amdgpu memory counters; if the model's peak
would not fit next to what is loaded, it stops the running `modelctl@*` LLM unit and
starts it again afterwards. The peak used for that decision is estimated from the
files' sizes until a native-res `--check --full` replaces it. Generations are serialized
(one `sd-cli` at a time — two on one iGPU can hang it); a second click waits and says so.
Checkpoints live in `sd_dir` from `models.conf` (`MODELCTL_SD_DIR` overrides).

Every run logs to `~/.local/state/modelctl/logs/<stamp>-<model>.log`. A failure is
classified before it is shown — *GPU hung and was reset by amdgpu* (with the kernel's
ring-timeout line), *out of GPU memory* (with the counters), *checkpoint unreadable*,
*sd-cli crashed with signal N* — instead of the last three lines of a progress bar.

Two opt-in keys under `[defaults]` in `~/.config/modelctl/models.conf`:

- `sd_check = true` enables `modelctl-image --check <id> [--no-fa] [--res N] [--steps N] [--full]`:
  a fixed-prompt smoke test (1 step at 512² by default; `--full` = the model's native
  res and steps). Each run appends wall time, peak GPU use and the failure class to
  `~/.local/state/modelctl/sd-checks.tsv` (`--checks` prints it). `--no-fa` / `--res`
  are for bisecting a hang: is it flash attention, or the resolution?
- `sd_retry_no_fa = true`: when a generation dies with a Vulkan device-lost, retry it
  once without `--diffusion-fa` and say so in the notification.

Deliberately separate from Omarchy's built-in `omarchy.agents`, which reports Claude
subscription usage rather than running sessions.

## Install

    omarchy plugin add https://github.com/tjcelaya/omarchy-modelctl.git --enable
    ~/.config/omarchy/plugins/tjcelaya.modelctl/install.sh

`omarchy plugin add` clones this repo into `~/.config/omarchy/plugins/tjcelaya.modelctl`
and loads the bar widget from there. `install.sh` wires the two things that have to
live outside the plugin folder — a `modelctl` launcher on `PATH` and the on-demand
systemd user units — as symlinks back into it, so `omarchy plugin update` updates
everything. Nothing is enabled at boot: a server starts only when you pick a model.

If the widget is not on the bar: `omarchy plugin enable tjcelaya.modelctl`, then
`omarchy bar move tjcelaya.modelctl --section center`.

### Uninstall

    ~/.config/omarchy/plugins/tjcelaya.modelctl/uninstall.sh
    omarchy plugin remove tjcelaya.modelctl

`uninstall.sh` stops any running server, removes the units, the `PATH` symlink,
modelctl's state and **only its own** `modelctl.*` entries in
`~/.config/omarchy/extensions/omarchy-menu.jsonc` (other entries in that file are
kept, both on install and on removal).

### Developing

Work in a clone (e.g. `~/src/omarchy-modelctl`), push, then pull it into the
installed copy the same way any user would:

    omarchy plugin update tjcelaya.modelctl    # git pull in ~/.config/omarchy/plugins/tjcelaya.modelctl
    omarchy restart shell                      # QML changes need a reload; scripts take effect at once

Everything the widget runs lives in the installed folder, so the machine never runs
unpushed code. `omarchy plugin validate .` checks the manifest before pushing;
`bin/modelctl-check` checks the bar and menu agree with herdr; `modelctl-image --check`
(opt-in) smoke-tests an image model.

## Requirements

- `llama-cpp` + `ggml-vulkan` (or another ggml backend) — `llama-server` on `PATH`
- GGUF models anywhere in `MODELCTL_MODEL_DIRS` (default: the LM Studio, llama.cpp,
  `~/models` and Ollama locations — all of them are scanned)
- `stable-diffusion.cpp` (`sd-cli`, `sd-server`) and checkpoints under
  `MODELCTL_SD_DIR` — optional; only for the image button
- `herdr` for the agent list — optional; without it the widget shows only the model
- systemd user session; `python3`, `jq`, `curl`

## Usage

    modelctl list                 # every GGUF found, with the context each will get
    modelctl                      # start the default model in the foreground
    modelctl <id>                 # start a specific one (id = filename minus .gguf, or ollama name:tag)
    modelctl show <id>            # print the llama-server command line, don't run it
    systemctl --user start modelctl@<id>

### Where models come from

Nothing is hardcoded. `modelctl` scans `MODELCTL_MODEL_DIRS` (default
`~/.lmstudio/models`, `~/.cache/llama.cpp`, `~/models`, `~/.ollama/models`) for
`*.gguf`, following symlinks, and merges everything it finds. Plain folders (LM Studio,
llama.cpp's cache, your own) are picked up as-is; an **Ollama** store is read through
its manifests and each pulled `name:tag` is served straight from its GGUF blob
(Ollama does not need to be running). No model manager is required or preferred. `mmproj-*.gguf`
projectors are attached automatically, sharded models start from shard 1, and the
menu regenerates from the scan every time it opens.

### The dropdown

Clicking any of the three bar segments opens one panel, built from the same kit as
Omarchy's Bluetooth and Wi-Fi dropdowns: a hero with the loaded model and an on/off
switch for the LLM server, the `llama.cpp` list (click to load, check on the loaded
one), the `stable-diffusion` list (click to select for the 󰋩 button; `parks the LLM`
where the peak would not fit; greyed out with the missing companion file), a
*Keep image server loaded* toggle, *Generate image…*, and the running agents (click to
focus). `Esc` closes, `g` generates, `s` toggles the server. `omarchy shell
tjcelaya.modelctl toggle` opens it from anywhere. The Omarchy quick menu keeps only a
launcher entry and the searchable **Agents** submenu.

### Tuning: `~/.config/modelctl/models.conf`

Machine- and model-specific settings live here, not in code (created from
`models.conf.example` by `install.sh`). Sections are globs over model ids:

    [defaults]
    default = gpt-oss-20b*
    args = -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -np 1 --cache-reuse 256 --jinja

    [gpt-oss-20b*]
    ctx = 131072
    label = gpt-oss-20b        # the alias llama-server reports; match it in opencode
    tag = oss20                # what the bar shows
    note = fastest here

Without a section a model gets 16k context and the stock flags. The values in the
example file were measured on one machine (Radeon 760M, 23.5 GiB Vulkan pool) —
`TUNING.md` explains how they were derived so you can redo it for yours.

## Settings

Exposed through the plugin manifest, editable in Omarchy's settings UI:

| key | default | meaning |
|---|---|---|
| `refreshIntervalSec` | 5 | how often to re-read state |
| `port` | 8090 | llama-server port |
| `showCwd` | true | show each agent's working directory |
| `imageDir` | `~/Pictures/generated` | where generated images are saved |
| `modelIcon` | `󰚩` | glyph for the model tag (see `BarWidget.qml` for tested alternatives) |
| `agentsIcon` | `󱃒` | glyph for the agents badge |

## Status

**v0.1.0, works on one machine.** The QML widget is new and less battle-tested than
the shell scripts behind it. Known gaps:

- Context sizes come from `models.conf` (16k default), not computed from free VRAM.
- Only herdr-managed agents are listed; plain tmux panes are a planned addition.
- The dropdown still uses Omarchy's menu via a generated JSONC file, because the
  menu's `provider` mechanism is a closed set hardcoded in `Menu.qml`. A native
  popup panel would remove that.
