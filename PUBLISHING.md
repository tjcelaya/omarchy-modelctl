# Publishing to omarchyplugins.com

Per https://omarchyplugins.com/publish.html the marketplace wants a public GitHub
repo whose **root** is the plugin folder: `manifest.json`, the QML entry point,
README, LICENSE, safe install/removal, optional preview image. This repo is laid
out that way (v0.1.0+). Local checks that must pass before submitting:

    omarchy plugin validate ~/src/omarchy-modelctl          # working tree
    T=$(mktemp -d) && git clone -q . $T && omarchy plugin validate $T && rm -rf $T   # what `plugin add` sees
    jq . manifest.json >/dev/null

Manual steps (nothing here is automated on purpose):

1. `gh repo create omarchy-modelctl --public --source=. --remote=origin --push`
2. Add repo topics on GitHub: `omarchy`, `omarchy-plugin`, `llama-cpp`, `stable-diffusion`.
3. Tag the release: `git tag v0.1.0 && git push --tags` (bump `version` in
   `manifest.json` for every later release; `omarchy plugin update` pulls HEAD).
4. Smoke-test the real install path on this machine:
       uninstall.sh; omarchy plugin remove tjcelaya.modelctl
       omarchy plugin add https://github.com/tjcelaya/omarchy-modelctl.git --enable
       ~/.config/omarchy/plugins/tjcelaya.modelctl/install.sh
5. Submit: https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
   — repo URL, category "AI", tags as above. Their CI validates the commit that is
   current at submission time; a maintainer approves after.

Repo-URL references that assume `github.com/tjcelaya/omarchy-modelctl`: README
install line, `systemd/*.service` `Documentation=`, this file.
