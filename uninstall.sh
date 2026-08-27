#!/usr/bin/env bash
# Undo install.sh: stop any running model server, drop the units, PATH symlink,
# our menu entries and state. Then remove the plugin folder itself with
#   omarchy plugin remove tjcelaya.modelctl
set -uo pipefail
systemctl --user stop 'modelctl@*.service' modelctl.service 2>/dev/null
rm -f ~/.config/systemd/user/modelctl.service ~/.config/systemd/user/modelctl@.service
systemctl --user daemon-reload
rm -f ~/.local/bin/modelctl
rm -f ~/.config/omarchy/bar/scripts/modelctl-*   # pre-1.0 layout
EXT=~/.config/omarchy/extensions/omarchy-menu.jsonc
if [ -f "$EXT" ]; then   # drop only our modelctl.* keys; leave other extensions alone
  python3 - "$EXT" <<'PY'
import sys,json,re
p=sys.argv[1]; d=json.loads(re.sub(r'^\s*//.*$','',open(p).read(),flags=re.M))
d={k:v for k,v in d.items() if not k.startswith("modelctl")}
open(p,"w").write(json.dumps(d,indent=2,ensure_ascii=False)+"\n")
PY
fi
rm -rf ~/.local/state/modelctl "${XDG_RUNTIME_DIR:-/tmp}/modelctl-agents.stamp"
omarchy menu refresh >/dev/null 2>&1 || true
echo "kept: ~/.config/modelctl/models.conf (your tuning)"
echo "modelctl unwired. Now: omarchy plugin remove tjcelaya.modelctl"
