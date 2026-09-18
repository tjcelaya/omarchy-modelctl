# modelctl(1)

## NAME

modelctl - Omarchy bar plugin for local llama.cpp models, stable-diffusion.cpp image models and running coding agents

## SYNOPSIS

```
modelctl [<id>]
modelctl list | show <id> | conf <key> [default] | sd-list | image
modelctl-image [--<id>] ["prompt"] | --list | --check <id> [--no-fa] [--res N] [--steps N] [--full] | --checks
modelctl-shutdown llm | image | agents | all
omarchy shell tjcelaya.modelctl toggle | open | close
omarchy shell tjcelaya.modelctl.groups show <agents|model|image|all> | menu <agents|model|image>
```

## DESCRIPTION

modelctl puts three segments in the Omarchy bar, one per group, each with its own dropdown and action menu:

- **Agents** - every running coding agent (herdr panes and agent processes inside Hyprland windows); one click focuses it.
- **Local models** - starts and stops `llama-server` on any discovered GGUF model.
- **Image models** - picks a stable-diffusion.cpp checkpoint, keeps `sd-server` resident, generates from a prompt.

The bar shows a group's glyph and the full id of whatever is loaded, never an abbreviation; the bar is for glancing, the dropdowns carry context, notes and paths. Nothing runs at boot: a server starts only when you pick a model. Nothing leaves the machine.

## THE BAR

- **Left click** a segment opens that group's dropdown.
- **Middle click** opens every shown group side by side in one card. So does `omarchy shell tjcelaya.modelctl toggle`.
- **Right click** opens the group's action menu. Shut-down actions ask first.
- The `order` setting lists the groups shown, left to right (default `agents,model,image`). A group left out has no segment at all. Agents is the anchor and always stays; its menu brings the others back.
- A segment is dim when its group has nothing loaded or running. The Agents badge shows a count only while something runs; Local models shows the loaded model's id; Image models shows the resident server's model id, or `<id> 37%` while a generation runs.
- The open-panel underline spans every shown segment while any dropdown or menu is open.

## DROPDOWNS

Each dropdown is a panel built from the same kit as Omarchy's Bluetooth and Wi-Fi dropdowns, anchored under its segment. Every list is shown in full; a column taller than the screen scrolls on its own (wheel, drag, `j`/`k` or the arrow keys).

### Everything at once

Middle click, or the IPC `toggle`, shows every shown group in one card with a column per group, each scrolling independently.

### Agents

The running coding agents with their working directory and status. Click one to focus it: a herdr pane is focused through herdr, and any `claude`, `opencode`, `codex`, `gemini`, `aider`, ... process with a TTY inside a Hyprland window (a plain terminal, `omarchy agent`) is focused by window. Processes under herdr are listed once, by herdr. tmux panes are not walked yet.

The Agents menu is the main menu:

- **Open Agents panel**
- **Enable Local models group** / **Enable Image models group** - shown only while that group is hidden; adds its segment back at its default position.
- **Edit models.conf** - opens `~/.config/modelctl/models.conf` in the Omarchy default editor.
- **Shut down all agents...** - after a confirmation, closes every herdr agent pane and sends SIGTERM to every windowed agent process.

This group is deliberately separate from Omarchy's built-in `omarchy.agents`, which reports subscription usage rather than running sessions.

### Local models

The header shows what is loaded and carries the `llama-server` switch (on = start the default model, off = stop). The list is every GGUF found under `model_dirs`; click one to load it, click the loaded one to stop. Context size, alias, notes and flags per model come from `models.conf`. Menu:

- **Open Local models panel**
- **Stop LLM server** / **Start default model**
- **View server logs** - `journalctl --user` on the modelctl units, in a terminal.
- **Disable Local models group** - removes the segment (the Agents menu brings it back).
- **Shut down all model servers...** - after a confirmation, stops `llama-server` and `sd-server` and cancels a running generation.

### Image models

The header shows the selected model and carries the keep-loaded switch: on keeps `sd-server` resident on `sd_port`; off loads the model fresh for each image. The list is every checkpoint under `sd_dir`; click one to select it for the segment's Generate action. A row is greyed out when a VAE or text encoder it needs is missing; `parks the LLM` marks a model whose measured or estimated peak would not fit beside the loaded LLM. **Generate image...** asks for a prompt through Omarchy's input popup. Menu:

- **Open Image models panel**
- **Disable Image models group**
- **Shut down image server...** - after a confirmation, stops `sd-server` and cancels a running generation.

## KEYS

While a dropdown is open:

- `Esc` - close; with a confirmation open, dismiss it instead.
- `h` / `l` (or Left / Right) - cycle the views in segment order, then all.
- `m` `i` `a` `*` - jump to Local models, Image models, Agents, or all.
- `j` / `k` (or Down / Up) - scroll; in a menu, move the cursor.
- `Enter` / `Space` - in a menu, run the row under the cursor.
- `g` - generate an image. `s` - toggle the LLM server.
- `Tab` / `Shift+Tab` - switch to the neighbouring bar widget's panel.

## COMMANDS

### modelctl

- `modelctl` - start the default model (`default` under `[defaults]`, else the first found) in the foreground.
- `modelctl <id>` - start that model. The id is the GGUF filename without `.gguf`, or an Ollama `name:tag`.
- `modelctl list` - every GGUF found, with the context each will get. `--tsv` for machine output.
- `modelctl show <id>` - print the `llama-server` command line without running it.
- `modelctl conf <key> [default]` - print a `[defaults]` value (used by the shell scripts).
- `modelctl sd-list` - image models as `id|label|note|peak|steps|cfg|res|args|tag|status|family`.
- `modelctl image` - run the resident `sd-server` (what the `modelctl@image` unit does).

### modelctl-image

- `modelctl-image ["prompt"]` - generate with the selected model; without a prompt, ask through the input popup.
- `modelctl-image --<id> "prompt"` - generate with a specific model; any unique substring of the id works (`--chroma`).
- `modelctl-image --list` - the image models with their status.
- `modelctl-image --check <id> [--no-fa] [--res N] [--steps N] [--full]` - a fixed-prompt smoke test (1 step at 512 square by default; `--full` uses the model's native size and steps). Needs `sd_check = true`. Each run appends wall time, peak GPU use and the failure class to `~/.local/state/modelctl/sd-checks.tsv`; `--checks` prints it. `--no-fa` and `--res` bisect a hang: flash attention, or the resolution?

### modelctl-shutdown

- `modelctl-shutdown llm` - stop every `llama-server` unit.
- `modelctl-shutdown image` - stop `sd-server` and cancel a running generation.
- `modelctl-shutdown agents` - end every running agent (herdr panes closed, windowed processes get SIGTERM).
- `modelctl-shutdown all` - `llm` and `image`.

### Shell IPC

- `omarchy shell tjcelaya.modelctl toggle|open|close` - the side-by-side view.
- `omarchy shell tjcelaya.modelctl.groups show <agents|model|image|all>` - one dropdown.
- `omarchy shell tjcelaya.modelctl.groups menu <agents|model|image>` - one action menu.
- `systemctl --user start modelctl@<id>` / `modelctl@image` - the units behind the switches.

## IMAGE GENERATION

Prompts go through Omarchy's input popup. Images are saved to `image_dir` (default `~/Pictures/generated`) as `<timestamp>-<model>-<prompt-slug>.png`, then opened.

Image models are discovered like the LLMs: every `.safetensors` or `.gguf` checkpoint under `sd_dir` is classified by family from its filename (SD 1.x, SD-Turbo, SDXL, SDXL-Lightning, Flux schnell/dev, Chroma, Z-Image, SD3) and paired with the VAE and text encoders that family needs from the same folder (`flux_ae`, `t5-xxl`, `clip_l`, `clip_g`, a Qwen3-4B encoder for Z-Image). One that lacks a companion is listed with what is missing and will not run. `.ckpt` (pickle) files are deliberately not discovered.

Before generating, the script reads the amdgpu memory counters; if the model's peak would not fit next to what is loaded, it stops the running LLM unit and starts it again afterwards. The peak is estimated from file sizes until a native-size `--check --full` replaces it with a measurement. Generations are serialized (one `sd-cli` at a time; two on one iGPU can hang it); a second request waits and says so.

Every run logs to `~/.local/state/modelctl/logs/<stamp>-<model>.log`. A failure is classified before it is shown: GPU hung and was reset by amdgpu (with the kernel's ring-timeout line), out of GPU memory (with the counters), checkpoint unreadable, or `sd-cli` crashed with signal N. With `sd_retry_no_fa` on (the default), a generation that dies with a Vulkan device-lost is retried once without `--diffusion-fa`, and the notification says so.

Planned: the Generate dialog will offer steps, size and the output folder as inputs, opening with the values from `models.conf`.

## CONFIGURATION

`~/.config/modelctl/models.conf` holds everything machine- or model-specific. `install.sh` creates it from `models.conf.example` if absent; the Agents menu opens it in your editor. It is an INI file. Section names other than `[defaults]` are globs matched against a model id; later matching sections override earlier ones.

### [defaults]

- `default` - glob of the model the switch and `modelctl` start (default: the first found).
- `hide` - globs of GGUF ids to leave out of the list.
- `model_dirs` - colon-separated folders scanned for GGUF models. Default: the LM Studio, llama.cpp cache, `~/models` and Ollama locations. An Ollama store is read through its manifests; each pulled `name:tag` is served straight from its blob, and Ollama need not be running.
- `port` - `llama-server` port (default `8090`).
- `args` - the full `llama-server` flag set (default `-ngl 99 -fa on -np 1 --cache-reuse 256 --jinja`).
- `image_dir` - where generated images are saved (default `~/Pictures/generated`).
- `sd_dir` - checkpoint folder for image models (default `~/.local/share/stable-diffusion/models`).
- `sd_port` - port of the resident `sd-server` (default `8091`).
- `sd_server_model` - checkpoint the resident `sd-server` loads.
- `sd_hide` - globs of image model ids to leave out.
- `sd_check` - `true` enables `modelctl-image --check` (default `false`).
- `sd_retry_no_fa` - `false` disables the retry without flash attention after a device-lost (default `true`).

### [<glob>] - one GGUF model or a family of them

- `ctx` - context size passed as `-c` (default `16384`).
- `args` - replaces the default flag set; `extra` - flags appended to it.
- `label` - the alias `llama-server` reports (`-a`); default: the id minus its quant suffix. A client's model list must match this.
- `tag` - optional short tag (the bar shows the full id).
- `note` - one line shown under the model in the dropdown.
- `mmproj` - vision projector path (default: an `mmproj-*.gguf` in the same folder).

### [sd:<glob>] - one image model or all of them

- `label`, `tag`, `note` - as above.
- `steps`, `cfg`, `res` - sampler defaults for the model. `[sd:*]` sets them for every model.
- `peak` - peak GPU use in MiB, until a `--check --full` measures it.
- `extra` - flags appended to the family's `sd-cli` arguments; `args` - full replacement (`$SD` expands to `sd_dir`).
- `hide = true` - drop it from the list.

`TUNING.md` in the repository explains how the example values were measured on one machine (Radeon 760M, 23.5 GiB Vulkan pool) so you can redo it for yours.

## SETTINGS

Exposed through the plugin manifest and editable in Omarchy's settings UI or with `omarchy bar set tjcelaya.modelctl <key> <value>`:

- `order` - groups shown, left to right (default `agents,model,image`). Leave one out to drop its segment; `agents` is always kept.
- `refreshIntervalSec` - how often the bar re-reads state (default `5`; `2` while a dropdown is open).
- `showCwd` - show each agent's working directory (default `true`).
- `agentsIcon` - glyph for the Agents segment (default `󰙴`; `󰆍` console, `󱚣` robot also fit).
- `modelIcon` - glyph for the Local models segment (default `󰧑`; `󰚩` robot, `󰘚` chip also fit).

## FILES

- `~/.config/modelctl/models.conf` - configuration (see CONFIGURATION).
- `~/.local/state/modelctl/` - the selected image model, run logs, `sd-checks.tsv`, check images, the generation lock and busy marker.
- `~/Pictures/generated/` - generated images (`image_dir`).
- `~/.config/omarchy/plugins/tjcelaya.modelctl/` - the plugin (a git checkout).
- `~/.local/bin/modelctl` - launcher on PATH, a symlink into the plugin.
- `~/.config/systemd/user/modelctl.service`, `modelctl@.service` - the on-demand units, symlinks into the plugin.
- `~/.local/share/man/man1/modelctl.1` - this manual.
- `~/.config/omarchy/extensions/omarchy-menu.jsonc` - the agent rows for Omarchy's quick menu; only the `modelctl.*` keys are written, every other key is preserved.

## ENVIRONMENT

Each overrides the matching `models.conf` key for one invocation: `MODELCTL_CONF` (the config file itself), `MODELCTL_MODEL_DIRS`, `MODELCTL_PORT`, `MODELCTL_IMAGE_DIR`, `MODELCTL_SD_DIR`, `MODELCTL_SD_PORT`, `MODELCTL_SD_MODEL` (the image model for one `modelctl-image` run). `SD_STEPS`, `SD_CFG`, `SD_W`, `SD_H` override the sampler for one run.

## INSTALLATION

```
omarchy plugin add https://github.com/tjcelaya/omarchy-modelctl.git --enable
~/.config/omarchy/plugins/tjcelaya.modelctl/install.sh
```

`omarchy plugin add` clones the repository into the plugin folder and loads the bar widget from there; a new center widget lands after `omarchy.weather`. `install.sh` wires what has to live outside the folder (the `modelctl` launcher, the systemd user units, this manual) as symlinks back into it, so `omarchy plugin update` updates everything, and creates `models.conf` from the example if absent. Nothing is enabled at boot.

If the widget is not on the bar: `omarchy plugin enable tjcelaya.modelctl`, then `omarchy bar move tjcelaya.modelctl --after omarchy.weather`.

To remove:

```
~/.config/omarchy/plugins/tjcelaya.modelctl/uninstall.sh
omarchy plugin remove tjcelaya.modelctl
```

`uninstall.sh` stops any running server and removes the units, the launcher, the manual, modelctl's transient state and only its own entries in the menu extension. Generated images, run logs, check results and `models.conf` are yours and stay.

## REQUIREMENTS

- `llama-cpp` with a ggml backend (`llama-server` on PATH) and GGUF models under `model_dirs`.
- `stable-diffusion.cpp` (`sd-cli`, `sd-server`) and checkpoints under `sd_dir` - optional, for the Image models group.
- `herdr` - optional, for herdr-managed agents; without it, only windowed agent processes are listed.
- A systemd user session; `python3`, `jq`, `curl`.

## SECURITY

The plugin runs unsandboxed inside `omarchy-shell`, like every Omarchy plugin, so here is exactly what it does.

- **Executes** `llama-server`, `sd-cli` / `sd-server`, `systemctl --user`, `notify-send`, `imv` / `xdg-open` on its own output, `herdr` and `hyprctl` for the agent list, `omarchy bar set` on its own `order` setting, `omarchy-launch-editor` on `models.conf`, and, only after the confirmation dialog, `herdr pane close` / `kill -TERM` on the listed agent processes and `systemctl --user stop` on its units. Every action from the widget is an argv passed through the constant `bash -lc 'exec "$@"'`; nothing read from a filename, herdr or Hyprland is ever re-parsed by a shell. No `eval`, no privilege escalation, no `sudo` or `pkexec`.
- **Network**: `llama-server` and `sd-server` bind `127.0.0.1` only; the widget's only client traffic is `curl` to `127.0.0.1:<port>/health` and `/v1/models`. Nothing leaves the machine; no telemetry.
- **Writes** `~/.local/state/modelctl/`, `image_dir`, `models.conf` (created only if absent), its own settings in `shell.json` through `omarchy bar set`, and the `modelctl.*` keys in the menu extension, rewritten with every other key preserved and the JSON validated before it replaces the file. `install.sh` adds symlinks in `~/.local/bin`, `~/.config/systemd/user` and `~/.local/share/man/man1`; `uninstall.sh` removes only those and its own menu keys.
- **Reads** the model folders, `journalctl -k` and amdgpu sysfs (to explain a GPU hang), `ps`, `/proc/<pid>/cwd` and `hyprctl clients` (to list agents). All local, all already visible to your user.
- **Model files** are parsed by llama.cpp and stable-diffusion.cpp's own loaders. Only `.gguf` and `.safetensors` are discovered.
- **Config** is trusted: `args` and `extra` in `models.conf` go to the servers as written. It is your file.

## DEVELOPING

Work in a clone, push, then pull it into the installed copy the same way any user would: `omarchy plugin update tjcelaya.modelctl`, then `omarchy restart shell` (QML changes need a reload; scripts take effect at once). `omarchy plugin validate .` checks the manifest before pushing. `bin/modelctl-check` checks that the bar and menu agree with herdr. The manual is generated from `docs/MANUAL.md` with `docs/mkman.py` (needs `scdoc`).

## BUGS

- Context sizes come from `models.conf` (16k default), not computed from free VRAM.
- Only one `llama-server` runs at a time; every LLM unit binds `port`.
- tmux panes are not walked for agents.
- The searchable Agents submenu in Omarchy's quick menu is a generated JSONC file, because the menu's provider mechanism is a closed set; its 300px card truncates long working directories (the full path is in the row's description, visible while searching).

## SEE ALSO

llama-server(1), systemctl(1), the repository at https://github.com/tjcelaya/omarchy-modelctl, herdr at https://github.com/tjcelaya/herdr
