# TODO

## Repo does not exist on GitHub yet

This lives only at `~/src/omarchy-modelctl` with local commits. Before anything
below can be filed as an issue, create the remote:

    gh repo create omarchy-modelctl --public --source=. --remote=origin --push

Then submit to the marketplace (see PUBLISHING.md) and mirror the issue below as a
**Linear ticket and/or GitHub issue** on Omarchy.

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
that are usually invisible. Being probed: whether `\n` inside a label renders as
two lines (labelText has `elide: ElideRight` and no `wrapMode`, so it may clip).

**Real fix for this plugin:** stop using the shared menu. Render our own popup
panel — own width, two columns (running agents | loadable models), management
actions on their own row. Blocked on whether a third-party plugin can import
`Panel` from `qs.Ui`; untested.
