#!/usr/bin/env bash
# Post-install for modelctl. The bar widget itself is loaded by Omarchy straight
# from this folder; this only wires the parts that live outside it:
#   ~/.local/bin/modelctl            launcher on PATH (used by the systemd units)
#   ~/.config/systemd/user/modelctl* on-demand llama-server / sd-server units
# Everything is a symlink into this folder, so `omarchy plugin update` updates it all.
# Nothing is enabled at boot; units start only when you pick a model in the menu.
set -euo pipefail
SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
mkdir -p ~/.config/systemd/user ~/.local/bin
ln -sf "$SRC/bin/modelctl" ~/.local/bin/modelctl
for u in "$SRC"/systemd/*.service; do ln -sf "$u" ~/.config/systemd/user/"$(basename "$u")"; done
systemctl --user daemon-reload
mkdir -p ~/.config/modelctl
[ -e ~/.config/modelctl/models.conf ] || cp "$SRC/models.conf.example" ~/.config/modelctl/models.conf
"$SRC/bin/modelctl-menu-sync" --force || true
echo "modelctl wired. If the widget is not on the bar yet:"
echo "  omarchy plugin enable tjcelaya.modelctl"
echo "  omarchy bar move tjcelaya.modelctl --after omarchy.weather"
echo "Models are discovered from ~/.lmstudio/models, ~/.ollama/models, ~/models, ~/.cache/llama.cpp"
echo "(MODELCTL_MODEL_DIRS). Tune per-model context etc. in ~/.config/modelctl/models.conf."
