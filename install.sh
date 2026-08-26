#!/usr/bin/env bash
# Install modelctl: plugin -> ~/.config/omarchy/plugins/tj.modelctl
#                   scripts -> ~/.config/omarchy/bar/scripts
#                   units   -> ~/.config/systemd/user
# Symlinks, so `git pull` here updates everything in place.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.config/omarchy/plugins ~/.config/omarchy/bar/scripts ~/.config/systemd/user ~/.local/bin
# A symlinked plugin DIRECTORY is registered but never hot-reloaded — the shell's
# file watcher does not follow it. Real dir, symlinked files.
mkdir -p ~/.config/omarchy/plugins/tj.modelctl
for f in "$SRC"/plugin/*; do ln -sf "$f" ~/.config/omarchy/plugins/tj.modelctl/"$(basename "$f")"; done
for f in "$SRC"/bin/modelctl-*; do ln -sf "$f" ~/.config/omarchy/bar/scripts/"$(basename "$f")"; done
ln -sf "$SRC/bin/modelctl" ~/.local/bin/modelctl
for u in "$SRC"/systemd/*.service; do [ -e "$u" ] && ln -sf "$u" ~/.config/systemd/user/"$(basename "$u")"; done
systemctl --user daemon-reload
echo "installed. enable the widget with:  omarchy plugin enable tj.modelctl"
echo "then place it:                      omarchy bar move tj.modelctl --section center"
