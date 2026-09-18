# TODO

Repo: https://github.com/tjcelaya/omarchy-modelctl. Marketplace submission steps are
in PUBLISHING.md; known gaps are the manual's Bugs section (`man modelctl`).

## Planned

- Count on the Local models segment when more than one model fits in VRAM; needs a
  port per running model (each `modelctl@<id>` unit binds `port` today).
- Generate dialog inputs for steps, size and output folder, opening with the
  `models.conf` values.
- tmux pane detection for agents.

## Upstream: mirror as a GitHub issue on Omarchy

---

## Issue: Omarchy menu card width is hardcoded, truncating plugin labels

**Where:** `/usr/share/omarchy/shell/plugins/menu/Menu.qml:111`

```qml
property int cardWidth: Math.min(
  root.dmenuActive ? Style.space(root.dmenuWidth)
  : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font")
     ? Style.space(520) : Style.space(300)),
  panel.width - Style.gapsOut * 2)
```

300px for every menu, with a 520px exception hardcoded to two first-party routes.
There is no JSONC key and no shell.json setting to widen a custom submenu, so
third-party menu entries must fit ~20 characters or elide. Observed on
`modelctl`: "Generate image (Turbo)…" rendered as "Generate image (T…".

**Asks (either would do):**
1. A `width` key on a submenu definition in `omarchy-menu.jsonc`, mirroring the
   `--width` that `omarchy-menu-input` already accepts, or
2. Size `cardWidth` to content up to a sane maximum, instead of a per-route allowlist.

**Related, same file (`:1287`):** `row.detail` is
`visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0`,
so descriptions render **only while searching**. A plugin cannot show a subtitle in
the normal browsing view. Worth raising together — both push authors to cram
context into a 20-char label.

**Workaround in place:** labels shortened to fit; detail moved into descriptions
that are usually invisible.

**Scope today:** only the searchable `modelctl.agents` submenu still lives in the
shared menu, so the truncation affects agent working directories there. Models,
image models and the agent list are rendered by the plugin's own `KeyboardPanel`
dropdown (a third-party plugin can import `Panel` / `KeyboardPanel` from `qs.Ui`),
which sizes itself and scrolls.
