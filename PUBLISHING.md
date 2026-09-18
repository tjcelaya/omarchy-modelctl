# Publishing to the Omarchy plugin marketplace

Per https://plugins.omarchy.org/publish.html (marketplace repo:
https://github.com/omacom/omarchy-plugin-marketplace) the marketplace wants a public
GitHub repo whose **root** is the plugin folder: `manifest.json`, the QML entry point,
README with install *and* removal instructions, LICENSE, documented external
dependencies, optional `preview.png` (optimized automatically, ≤ 50 MB). No symlinks
inside the plugin folder (the README's other images live in `docs/img/`, the manual
in `docs/`; `install.sh` links `docs/modelctl.1` into `~/.local/share/man/man1`). The plugin id must be globally unique across the marketplace
and outside `omarchy.*`; `tjcelaya.modelctl` is unused there as of 2026-09-09.

Local checks that must pass before submitting:

    omarchy plugin validate ~/src/tjcelaya/omarchy-modelctl    # working tree
    T=$(mktemp -d) && git clone -q . $T && omarchy plugin validate $T && rm -rf $T   # what `plugin add` sees
    jq . manifest.json >/dev/null

Manual steps (nothing here is automated on purpose):

1. ~~Create the repo~~ done: https://github.com/tjcelaya/omarchy-modelctl
2. ~~Topics~~ done: `omarchy`, `omarchy-plugin`, `llama-cpp`, `stable-diffusion`.
3. Tag the release: `git tag v0.2.1 && git push --tags` (bump `version` in
   `manifest.json` for every later release; `omarchy plugin update` pulls HEAD).
4. Smoke-test the real install path on this machine:
       uninstall.sh; omarchy plugin remove tjcelaya.modelctl
       omarchy plugin add https://github.com/tjcelaya/omarchy-modelctl.git --enable
       ~/.config/omarchy/plugins/tjcelaya.modelctl/install.sh
5. Submit: https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
   - Repository URL: `https://github.com/tjcelaya/omarchy-modelctl`
   - Category (one, exact spelling): `Developer Tools`
   - Tags (one to three): `AI, Bar`
   - Maintainer notes: ships systemd *user* units and an `install.sh` that only
     symlinks into `~/.local/bin`, `~/.config/systemd/user` and
     `~/.local/share/man/man1`; no sudo/pkexec, no downloads, nothing runs at boot.
     Shut-down actions (`systemctl --user stop` on its own units, `herdr pane close`
     / `kill -TERM` on listed agent processes) run only after an in-panel
     confirmation. Reads `/proc/<pid>/cwd`, `hyprctl clients`, amdgpu sysfs and
     `journalctl -k` locally to list agents and explain GPU hangs; full list in the
     manual's Security section. Expect the automated baseline to report the
     `installer` and `service-management` capabilities (review-required, not a
     finding).
   - All five checklist boxes apply and can be ticked.

   Their CI validates the exact commit that is HEAD at submission time; a maintainer
   approves after. Later releases are promoted through the "Plugin verification"
   form (newer upstream commit + full 40-char SHA), not by resubmitting.

Repo-URL references that assume `github.com/tjcelaya/omarchy-modelctl`: README
install line, `systemd/*.service` `Documentation=`, this file.
