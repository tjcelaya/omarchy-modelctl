import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// modelctl — three bar segments (loaded LLM · image model · running agents), each
// with its own dropdown. Left click opens that group's panel, middle click opens
// every shown group side by side, right click opens the group's action menu. The
// `order` setting lists the groups shown, left to right; a group left out has no
// segment at all. Agents is always shown: its menu re-enables the others and opens
// the plugin's config. Same panel kit as the first-party Bluetooth / Wi-Fi
// dropdowns, so it looks and behaves like them.
Panel {
  id: root
  moduleName: "tjcelaya.modelctl"
  ipcTarget: "tjcelaya.modelctl"   // omarchy shell tjcelaya.modelctl toggle|open|close

  readonly property int refreshSec: (settings && settings.refreshIntervalSec) || 5
  readonly property string modelIcon:  (settings && settings.modelIcon) || "󰧑"
  readonly property string agentsIcon: (settings && settings.agentsIcon) || "󰙴"
  readonly property string imageIcon: "󰋩"
  // The groups shown, left to right. A group missing from `order` has no segment;
  // agents is the anchor and is always present.
  readonly property var defaultOrder: ["agents", "model", "image"]
  readonly property var order: root.parseOrder(root.setting("order", "agents,model,image"))
  readonly property bool imageEnabled:  root.order.indexOf("image") >= 0
  readonly property bool modelEnabled:  root.order.indexOf("model") >= 0
  function parseOrder(raw) {
    var names = String(raw).toLowerCase().split(/[,\s]+/)
    var alias = { images: "image", sd: "image", models: "model", llm: "model", local: "model", agent: "agents" }
    var out = []
    for (var i = 0; i < names.length; i++) {
      var n = alias[names[i]] || names[i]
      if (root.defaultOrder.indexOf(n) >= 0 && out.indexOf(n) < 0) out.push(n)
    }
    if (out.indexOf("agents") < 0) out.unshift("agents")
    return out
  }

  // What the dropdown shows: one group (model | image | agents), every enabled group
  // side by side (all), or the right-click action menu for menuGroup (menu).
  property string which: "all"
  property string menuGroup: "model"
  property int menuIndex: 0
  property bool confirmOpen: false

  // ── state, refreshed from modelctl-barjson ───────────────────────────────
  property string state: "off"        // off | loading | ready
  property string model: ""           // served alias while ready
  property string modelId: ""         // unit instance (model id) while any unit runs
  property string modelTag: ""
  property string freeMem: ""
  property int port: 8090
  property bool imageOn: false        // resident sd-server
  property string sdModel: ""
  property string sdTag: ""
  property var busy: null             // {model, elapsed, progress, prompt} while sd-cli runs
  property var llms: []
  property var sds: []
  property var agents: []
  // Optimistic mark so a click shows before the next poll lands.
  property string pendingLlm: ""

  readonly property color fg:   bar ? bar.foreground : Color.foreground
  readonly property string fam: bar ? bar.fontFamily : Style.font.family
  readonly property color dim:  Qt.darker(fg, 1.5)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.15)
  readonly property int colW: Style.space(380)
  readonly property int menuW: Style.space(320)

  // The bar shows the full model id next to the glyph, never an abbreviation, so
  // what is loaded is never in doubt. The unit instance is the id; the served alias
  // stands in until the unit reports one.
  function loadedName() { return root.modelId || root.model }
  // While generating: "<id> 37%" once sd-cli reports a phase fraction, else "<id> 1:05".
  function busyText() {
    if (!root.busy) return ""
    var b = root.busy, name = String(b.model)
    var m = /^(\d+)\/(\d+)$/.exec(b.progress || "")
    if (m && Number(m[2]) > 0) return name + " " + Math.floor(100 * Number(m[1]) / Number(m[2])) + "%"
    var s = Number(b.elapsed || 0)
    return name + " " + Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
  }
  function ctxText(m) {
    var parts = []
    if (m.ctx) parts.push(Math.round(m.ctx / 1024) + "k ctx")
    if (m.vision) parts.push("vision")
    if (m.note) parts.push(m.note)
    return parts.join(" · ")
  }
  function heroStatus() {
    if (root.state === "ready") return (root.model || "local") + " on :" + root.port
    if (root.state === "loading") return "Loading " + (root.modelId || "model") + "…"
    return "Nothing loaded" + (root.freeMem ? " · " + root.freeMem + " free" : "")
  }
  function imageStatus() {
    if (root.busy) return "Generating · " + root.busyText()
    if (!root.sdModel) return root.sds.length ? "No model selected" : "No checkpoints found"
    return root.sdModel + (root.imageOn ? " · server on :8091" : " · loads per image")
  }
  function agentsStatus() {
    var n = root.agents.length
    if (n === 0) return "None running"
    var working = 0
    for (var i = 0; i < n; i++) if (root.agents[i].status === "working") working++
    return n + " running" + (working ? " · " + working + " working" : "")
  }
  function groupTitle(g) { return g === "image" ? "Image models" : g === "agents" ? "Agents" : "Local models" }
  function groupIcon(g) { return g === "image" ? root.imageIcon : g === "agents" ? root.agentsIcon : root.modelIcon }
  function groupEnabled(g) { return root.order.indexOf(g) >= 0 }
  function showing(g) { return root.which === g || (root.which === "all" && root.groupEnabled(g)) }

  // Scripts ship in bin/ next to this file, wherever the plugin folder lives.
  function scriptDir() { return Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "") }
  // Every action is an argv: bash only ever sees the constant `exec "$@"`, so ids,
  // paths and anything read from herdr / Hyprland land in positional parameters and
  // are never re-tokenized. Same shape as the shell's own Util.execArgv.
  function run(argv) { Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv)) }
  function refreshSoon() { refreshTimer.restart() }

  function switchLlm(id) {
    if (root.pendingLlm === id) return
    root.pendingLlm = id
    root.run([root.scriptDir() + "/modelctl-switch", id])
    refreshSoon()
  }
  function stopLlm() {
    root.pendingLlm = ""
    root.run([root.scriptDir() + "/modelctl-stop"])
    refreshSoon()
  }
  function toggleServer() {
    if (root.state !== "off") stopLlm()
    else if (root.llms.length > 0) switchLlm(root.llms[0].id)
  }
  function selectSd(id) {
    root.sdModel = id
    root.run([root.scriptDir() + "/modelctl-sd", "select", id])
    refreshSoon()
  }
  function toggleImageServer() {
    root.imageOn = !root.imageOn
    root.run(["systemctl", "--user", root.imageOn ? "start" : "stop", "modelctl@image.service"])
    refreshSoon()
  }
  function generate() {
    root.close()
    root.run([root.scriptDir() + "/modelctl-image"])
  }
  function focusAgent(a) {
    root.close()
    if (a && Array.isArray(a.focus) && a.focus.length) root.run(a.focus)
  }
  function showLogs() {
    root.close()
    root.run(["omarchy-launch-or-focus-tui", "journalctl --user -u modelctl.service -u 'modelctl@*.service' -f"])
  }
  // Showing or hiding a group rewrites the `order` setting, so it survives restarts
  // and shows in the settings UI; `omarchy bar set` writes shell.json and the bar
  // patches us live. A re-enabled group returns to its default slot.
  function setGroupEnabled(g, on) {
    if (g === "agents") return
    var next = root.order.filter(function(x) { return x !== g })
    if (on) {
      var at = next.length
      for (var i = 0; i < next.length; i++)
        if (root.defaultOrder.indexOf(next[i]) > root.defaultOrder.indexOf(g)) { at = i; break }
      next.splice(at, 0, g)
    }
    root.run(["omarchy", "bar", "set", root.moduleName, "order", next.join(",")])
    if (!on && (root.which === g || root.menuGroup === g)) root.close()
  }
  function editConfig() {
    root.close()
    root.run(["omarchy-launch-editor", Quickshell.env("HOME") + "/.config/modelctl/models.conf"])
  }
  function shutdown(g) {
    root.confirmOpen = false
    root.close()
    root.run([root.scriptDir() + "/modelctl-shutdown", g === "model" ? "all" : g === "image" ? "image" : "agents"])
    refreshSoon()
  }

  // ── opening ────────────────────────────────────────────────────────────────
  // A single group or a menu shows only when a click (or the groups IPC) asked
  // for it; opening any other way — `omarchy shell tjcelaya.modelctl toggle`, the
  // bar's Tab switching — lands on the full side-by-side view.
  property bool viewRequested: false
  function showPanel(name) {
    if (root.opened && root.which === name) { root.close(); return }
    root.which = name
    root.confirmOpen = false
    if (root.opened) return
    root.viewRequested = true
    root.controller.show()
  }
  function showMenu(g) {
    if (root.opened && root.which === "menu" && root.menuGroup === g) { root.close(); return }
    root.menuGroup = g
    root.menuIndex = 0
    root.which = "menu"
    root.confirmOpen = false
    if (root.opened) return
    root.viewRequested = true
    root.controller.show()
  }
  function clickGroup(g, button) {
    if (button === Qt.MiddleButton) root.showPanel("all")
    else if (button === Qt.RightButton) root.showMenu(g)
    else root.showPanel(g)
  }
  function cycleGroup(step) {
    var order = root.order.concat(["all"]).filter(function(g) { return g === "all" || root.groupEnabled(g) })
    var i = order.indexOf(root.which)
    root.which = order[((i < 0 ? 0 : i) + step + order.length) % order.length]
  }
  onOpenedChanged: {
    root.confirmOpen = false
    if (!opened) { root.viewRequested = false; return }
    if (!root.viewRequested) root.which = "all"
    root.viewRequested = false
    modelFlick.contentY = 0; imageFlick.contentY = 0; agentsFlick.contentY = 0
  }
  onOrderChanged: {
    var g = root.which === "menu" ? root.menuGroup : root.which
    if (g !== "all" && !root.groupEnabled(g)) root.close()
  }

  // The panel is one scrolling surface per column: wheel, drag, j/k or the arrows.
  function scrollFlick(f, steps) { f.contentY = Math.max(0, Math.min(f.contentY + steps * Style.space(56), f.contentHeight - f.height)) }
  function scrollBy(steps) {
    if (root.showing("model")) root.scrollFlick(modelFlick, steps)
    if (root.showing("image")) root.scrollFlick(imageFlick, steps)
    if (root.showing("agents")) root.scrollFlick(agentsFlick, steps)
  }

  // ── right-click menu ──────────────────────────────────────────────────────
  function menuRows() {
    var g = root.menuGroup, rows = []
    rows.push({ act: "open", icon: root.groupIcon(g), label: "Open " + root.groupTitle(g) + " panel", sub: "" })
    if (g === "agents") {
      // The anchor group's menu is the main menu: it brings back hidden groups and
      // opens the plugin's own config file.
      if (!root.modelEnabled) rows.push({ act: "enable-model", icon: root.modelIcon, label: "Enable Local models group", sub: "Adds the segment back" })
      if (!root.imageEnabled) rows.push({ act: "enable-image", icon: root.imageIcon, label: "Enable Image models group", sub: "Adds the segment back" })
      rows.push({ act: "edit", icon: "󰷈", label: "Edit models.conf", sub: "~/.config/modelctl/models.conf · model dirs, per-model tuning" })
      rows.push({ act: "shutdown", icon: "󰗼", label: "Shut down all agents…", sub: root.agentsStatus() + " · asks first" })
    } else if (g === "model") {
      rows.push(root.state !== "off"
        ? { act: "server", icon: "󰐥", label: "Stop LLM server", sub: root.heroStatus() }
        : { act: "server", icon: "󰐥", label: "Start default model", sub: root.llms.length ? root.llms[0].label : "no models found" })
      rows.push({ act: "logs", icon: "󰌱", label: "View server logs", sub: "journalctl for the modelctl units" })
      rows.push({ act: "disable", icon: "󰛑", label: "Disable Local models group", sub: "Removes the segment · the Agents menu brings it back" })
      rows.push({ act: "shutdown", icon: "󰗼", label: "Shut down all model servers…", sub: "llama-server and sd-server · asks first" })
    } else {
      rows.push({ act: "disable", icon: "󰛑", label: "Disable Image models group", sub: "Removes the segment · the Agents menu brings it back" })
      rows.push({ act: "shutdown", icon: "󰗼", label: "Shut down image server…", sub: "Stops sd-server, cancels a running generation · asks first" })
    }
    return rows
  }
  function confirmMessage() {
    if (root.menuGroup === "image") return "Stop the image server and cancel a running generation?"
    if (root.menuGroup === "agents") return "Close all " + root.agents.length + " running agent session" + (root.agents.length === 1 ? "" : "s") + "? Their terminals end."
    return "Stop llama-server and sd-server, and cancel any running generation?"
  }
  function menuActivate(i) {
    var rows = root.menuRows()
    if (i < 0 || i >= rows.length) return
    switch (rows[i].act) {
      case "open": root.showPanel(root.menuGroup); break
      case "server": root.toggleServer(); root.close(); break
      case "logs": root.showLogs(); break
      case "enable-model": root.setGroupEnabled("model", true); root.close(); break
      case "enable-image": root.setGroupEnabled("image", true); root.close(); break
      case "edit": root.editConfig(); break
      case "disable": root.setGroupEnabled(root.menuGroup, false); break
      case "shutdown": confirm.selectedIndex = 1; root.confirmOpen = true; break
    }
  }

  IpcHandler {
    target: "tjcelaya.modelctl.groups"
    function show(name: string): void { if (name === "all" || root.groupEnabled(name)) root.showPanel(name) }
    function menu(name: string): void { if (root.groupEnabled(name)) root.showMenu(name) }
  }

  Process {
    id: poll
    // Login shell for the session PATH (sd-cli, herdr live in ~/.local/bin); the
    // script path is the only argument and it is ours.
    command: ["bash", "-lc", 'exec "$@"', "bash", root.scriptDir() + "/modelctl-barjson"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(this.text)
          root.state    = d.state || "off"
          root.model    = d.model || ""
          root.modelId  = d.modelId || ""
          root.modelTag = d.tag || ""
          root.freeMem  = d.free || ""
          root.port     = d.port || 8090
          root.imageOn  = d.image === true
          root.sdModel  = d.sd || ""
          root.sdTag    = d.sdtag || ""
          root.busy     = d.busy || null
          root.llms     = d.llms || []
          root.sds      = d.sds || []
          root.agents   = d.agents || []
          if (root.pendingLlm && (root.modelId === root.pendingLlm || root.state === "ready")) root.pendingLlm = ""
        } catch (e) {
          // Leave the last good reading in place rather than blanking the bar.
        }
      }
    }
  }
  Timer {
    interval: root.opened ? 2000 : root.refreshSec * 1000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true
  }
  Timer { id: refreshTimer; interval: 700; onTriggered: if (!poll.running) poll.running = true }

  implicitWidth: segments.implicitWidth
  implicitHeight: segments.implicitHeight
  // The bar's open-panel underline is centred on the slot and sized by this hint;
  // every panel belongs to the whole widget, so it spans all shown segments.
  readonly property real openPanelIndicatorWidth: Math.max(0, segments.width - Style.space(12))

  // ── bar segments ───────────────────────────────────────────────────────────
  // WidgetButton, not BarIconButton: these carry a glyph *and* a short tag, and the
  // icon button is a fixed single-glyph slot that squashes anything longer.
  readonly property string clickHelp: "\nLeft: this group · Middle: all groups · Right: actions"
  function segmentText(g) {
    if (g === "model") return root.modelIcon + (root.state === "ready" ? " " + root.loadedName() : root.state === "loading" ? " " + root.loadedName() + " ···" : "")
    // Like the other segments, a tag means something is loaded: the resident
    // sd-server's model, or the generation in flight. The selection lives in the panel.
    if (g === "image") return root.imageIcon + (root.busy ? " " + root.busyText() : root.imageOn ? " " + root.sdModel : "")
    return root.agentsIcon + (root.agents.length > 0 ? " " + root.agents.length : "")
  }
  function segmentDim(g) {
    if (g === "model") return root.state !== "ready"
    if (g === "image") return !root.busy && !root.imageOn
    return root.agents.length === 0
  }
  function segmentTip(g) {
    if (g === "model") return root.heroStatus()
    if (g === "image") return root.busy ? "Generating with " + root.busy.model + " · " + root.busy.prompt : "Image model: " + (root.sdModel || "none")
    return root.agents.length === 0 ? "No coding agents running" : root.agents.length + " agent(s) running"
  }
  Row {
    id: segments
    spacing: 0
    Repeater {
      id: segRepeater
      model: root.order
      delegate: WidgetButton {
        id: seg
        required property string modelData
        readonly property string group: modelData
        bar: root.bar
        visible: root.groupEnabled(group)
        fontSize: Style.font.body
        horizontalMargin: 6
        text: root.segmentText(group)
        dimmed: root.segmentDim(group)
        tooltipText: root.segmentTip(group) + root.clickHelp
        SequentialAnimation on opacity {
          running: seg.group === "image" && root.busy !== null; loops: Animation.Infinite
          NumberAnimation { to: 0.45; duration: 700 } NumberAnimation { to: 1.0; duration: 700 }
          onStopped: seg.opacity = 1.0
        }
        onPressed: function(b) { root.clickGroup(group, b) }
      }
    }
  }
  function buttonFor(g) {
    for (var i = 0; i < segRepeater.count; i++) {
      var item = segRepeater.itemAt(i)
      if (item && item.group === g) return item
    }
    return segments
  }

  // ── dropdown ───────────────────────────────────────────────────────────────
  readonly property Item anchorButton: {
    var g = root.which === "menu" ? root.menuGroup : root.which
    segRepeater.count   // re-evaluate once the segments exist
    return g === "all" ? segments : root.buttonFor(g)
  }
  readonly property int shownCount: (root.showing("model") ? 1 : 0) + (root.showing("image") ? 1 : 0) + (root.showing("agents") ? 1 : 0)
  // contentWidth is the card's outer width; the content sits inside its padding and
  // border, so ask for the columns plus those insets and let the columns share
  // whatever the screen leaves.
  readonly property real horizontalInset: panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec)
  function panelWidth() {
    var n = root.shownCount
    var inner = root.which === "menu" ? root.menuW : n * root.colW + Math.max(0, n - 1) * columns.gap
    return inner + root.horizontalInset
  }
  readonly property real columnWidth: root.which === "all"
    ? (columns.width - Math.max(0, root.shownCount - 1) * columns.gap) / Math.max(1, root.shownCount)
    : columns.width
  // Columns follow the bar's segment order; x counts the shown groups before this one.
  function columnX(g) {
    var k = 0
    for (var i = 0; i < root.order.length; i++) {
      if (root.order[i] === g) break
      if (root.showing(root.order[i])) k++
    }
    return k * (root.columnWidth + columns.gap)
  }
  function panelHeight() {
    if (root.which === "menu") return menuCol.implicitHeight
    var h = 0
    if (root.showing("model")) h = Math.max(h, modelCol.implicitHeight)
    if (root.showing("image")) h = Math.max(h, imageCol.implicitHeight)
    if (root.showing("agents")) h = Math.max(h, agentsCol.implicitHeight)
    return h
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth())
    contentHeight: panel.fittedContentHeight(root.panelHeight())   // clamps to the screen; the columns scroll

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: { if (root.confirmOpen) root.confirmOpen = false; else root.close() }
      onTabRequested: function(direction) { if (!root.confirmOpen) root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.confirmOpen) { if (dx !== 0 || dy !== 0) confirm.selectedIndex = confirm.selectedIndex === 0 ? 1 : 0; return }
        if (root.which === "menu") {
          if (dy !== 0) root.menuIndex = Math.max(0, Math.min(root.menuRows().length - 1, root.menuIndex + dy))
          return
        }
        if (dy !== 0) root.scrollBy(dy)
        if (dx !== 0) root.cycleGroup(dx)
      }
      onActivateRequested: {
        if (root.confirmOpen) { if (confirm.selectedIndex === 0) root.confirmOpen = false; else root.shutdown(root.menuGroup); return }
        if (root.which === "menu") root.menuActivate(root.menuIndex)
      }
      onTextKey: function(t) {
        if (root.confirmOpen) return
        if (t === "g" || t === "G") { if (root.imageEnabled) root.generate() }
        if (t === "s" || t === "S") { if (root.modelEnabled) root.toggleServer() }
        if (t === "m" || t === "M") { if (root.modelEnabled) root.showPanel("model") }
        if (t === "i" || t === "I") { if (root.imageEnabled) root.showPanel("image") }
        if (t === "a" || t === "A") root.showPanel("agents")
        if (t === "*") root.showPanel("all")
      }

      Item {
        id: columns
        anchors.fill: parent
        readonly property int gap: Style.space(24) + 1   // rule plus its margins
        Repeater {
          model: root.which === "all" ? Math.max(0, root.shownCount - 1) : 0
          delegate: Rectangle {
            required property int index
            x: (index + 1) * (root.columnWidth + columns.gap) - (columns.gap + 1) / 2
            width: 1; height: columns.height; color: root.hairline
          }
        }

        // ---------- Local models (main group) ----------
        GroupColumn {
          id: modelCol
          visible: root.showing("model")
          x: root.columnX("model")
          flick: modelFlick
          Flickable {
            id: modelFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: modelInner.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
              id: modelInner
              width: modelFlick.width
              spacing: Style.space(12)
              GroupHeader {
                icon: root.modelIcon; title: "Local models"; status: root.heroStatus(); lit: root.state === "ready"
                ToggleSwitch {
                  id: serverSwitch
                  width: implicitWidth; height: implicitHeight
                  checked: root.state !== "off"
                  busy: root.state === "loading" || root.pendingLlm !== ""
                  interactive: root.llms.length > 0
                  foreground: root.fg
                  onToggled: root.toggleServer()
                  PanelToolTip {
                    visible: serverSwitch.containsMouse
                    text: root.state !== "off" ? "Stop the LLM server" : "Start the default model"
                    fontFamily: root.fam
                  }
                }
              }
              PanelSeparator { foreground: root.fg }
              SectionTitle { text: "LLAMA.CPP"; trailing: root.llms.length + " model" + (root.llms.length === 1 ? "" : "s") }
              Text {
                visible: root.llms.length === 0
                width: parent.width; wrapMode: Text.WordWrap
                text: "No GGUF models found. Put some under MODELCTL_MODEL_DIRS, or pull one with LM Studio or Ollama."
                color: root.dim; font.family: root.fam; font.pixelSize: Style.font.bodySmall
              }
              ListView {
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Style.space(2)
                model: root.llms
                delegate: ModelRow {
                  required property var modelData
                  width: ListView.view.width
                  title: modelData.label
                  subtitle: root.ctxText(modelData)
                  icon: modelData.vision ? "󰄀" : "󰘚"
                  current: root.modelId === modelData.id || (root.model !== "" && root.model === modelData.label)
                  pending: root.pendingLlm === modelData.id || (root.state === "loading" && root.modelId === modelData.id)
                  tip: current ? "Loaded · click to stop" : "Load with llama-server"
                  onActivated: current ? root.stopLlm() : root.switchLlm(modelData.id)
                }
              }
            }
          }
        }

        // ---------- Image models ----------
        GroupColumn {
          id: imageCol
          visible: root.showing("image")
          x: root.columnX("image")
          flick: imageFlick
          Flickable {
            id: imageFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: imageInner.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
              id: imageInner
              width: imageFlick.width
              spacing: Style.space(12)
              GroupHeader {
                icon: root.imageIcon; title: "Image models"; status: root.imageStatus(); lit: root.imageOn || root.busy !== null
                ToggleSwitch {
                  id: imageSwitch
                  width: implicitWidth; height: implicitHeight
                  checked: root.imageOn
                  interactive: root.sds.length > 0
                  foreground: root.fg
                  onToggled: root.toggleImageServer()
                  PanelToolTip {
                    visible: imageSwitch.containsMouse
                    text: root.imageOn ? "Stop the resident sd-server (:8091)" : "Keep sd-server loaded on :8091 · off = each image loads its model fresh"
                    fontFamily: root.fam
                  }
                }
              }
              PanelSeparator { foreground: root.fg }
              SectionTitle {
                text: "STABLE-DIFFUSION"
                trailing: root.busy ? "generating · " + root.busyText() : root.sds.length + " model" + (root.sds.length === 1 ? "" : "s")
              }
              Text {
                visible: root.sds.length === 0
                width: parent.width; wrapMode: Text.WordWrap
                text: "No checkpoints found. Put .safetensors / .gguf checkpoints (and their VAE / text encoders) under sd_dir in ~/.config/modelctl/models.conf."
                color: root.dim; font.family: root.fam; font.pixelSize: Style.font.bodySmall
              }
              ListView {
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Style.space(2)
                model: root.sds
                delegate: ModelRow {
                  required property var modelData
                  width: ListView.view.width
                  readonly property bool runnable: modelData.status === "ok"
                  title: modelData.label
                  subtitle: modelData.note + (modelData.peak > 9000 ? " · parks the LLM" : "")
                  icon: root.busy && root.busy.model === modelData.id ? "󰔟" : "󰋩"
                  current: root.sdModel === modelData.id
                  enabled: runnable
                  tip: runnable ? "Select for the bar's " + root.imageIcon + " button" : "Cannot run: " + modelData.status
                  onActivated: if (runnable) root.selectSd(modelData.id)
                }
              }
              Button {
                width: parent.width
                text: root.busy ? "Generate another image…  (queues)" : "Generate image…"
                iconText: root.imageIcon
                tooltipText: "Prompt via the Omarchy input popup · uses " + (root.sdModel || "the selected model")
                foreground: root.fg; fontFamily: root.fam
                onClicked: root.generate()
              }
            }
          }
        }

        // ---------- Agents ----------
        GroupColumn {
          id: agentsCol
          visible: root.showing("agents")
          x: root.columnX("agents")
          flick: agentsFlick
          Flickable {
            id: agentsFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: agentsInner.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
              id: agentsInner
              width: agentsFlick.width
              spacing: Style.space(12)
              GroupHeader { icon: root.agentsIcon; title: "Agents"; status: root.agentsStatus(); lit: root.agents.length > 0 }
              PanelSeparator { foreground: root.fg }
              SectionTitle { text: "RUNNING"; trailing: "click to focus" }
              Text {
                visible: root.agents.length === 0
                width: parent.width; wrapMode: Text.WordWrap
                text: "No coding agents detected. herdr panes and terminal windows running claude, opencode, codex… show up here."
                color: root.dim; font.family: root.fam; font.pixelSize: Style.font.bodySmall
              }
              ListView {
                visible: root.agents.length > 0
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Style.space(2)
                model: root.agents
                delegate: ModelRow {
                  required property var modelData
                  width: ListView.view.width
                  title: modelData.name + " · " + (String(modelData.cwd).replace(/\/$/, "").split("/").pop() || modelData.cwd)
                  subtitle: [modelData.cwd, modelData.status, modelData.pane].filter(function(x) { return x }).join(" · ")
                  icon: modelData.status === "working" ? "󰑮" : "󰆍"
                  current: modelData.focused === true
                  tip: "Focus this agent"
                  onActivated: root.focusAgent(modelData)
                }
              }
            }
          }
        }

        // ---------- Right-click actions ----------
        Item {
          id: menuCol
          visible: root.which === "menu"
          width: columns.width
          height: parent.height
          implicitHeight: menuInner.implicitHeight
          Column {
            id: menuInner
            width: parent.width
            spacing: Style.space(12)
            GroupHeader {
              icon: root.groupIcon(root.menuGroup); title: root.groupTitle(root.menuGroup)
              status: root.menuGroup === "image" ? root.imageStatus() : root.menuGroup === "agents" ? root.agentsStatus() : root.heroStatus()
              lit: true
            }
            PanelSeparator { foreground: root.fg }
            ListView {
              width: parent.width
              height: contentHeight
              interactive: false
              spacing: Style.space(2)
              model: root.opened || root.which === "menu" ? root.menuRows() : []
              delegate: ModelRow {
                required property var modelData
                required property int index
                width: ListView.view.width
                title: modelData.label
                subtitle: modelData.sub
                icon: modelData.icon
                current: index === root.menuIndex
                onActivated: root.menuActivate(index)
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        message: root.confirmMessage()
        confirmText: "Shut down"
        background: Color.popups.background
        foreground: root.fg
        fontFamily: root.fam
        onCanceled: root.confirmOpen = false
        onConfirmed: root.shutdown(root.menuGroup)
      }
    }
  }

  // One group's column: fills the panel height, scrolls its own content.
  component GroupColumn: Item {
    property Flickable flick: null
    width: root.columnWidth
    height: parent ? parent.height : implicitHeight
    implicitHeight: flick ? flick.contentHeight : 0
  }

  // Group header: icon · title / status · an optional accessory (the switch) on the right.
  component GroupHeader: Item {
    id: gh
    property string icon: ""
    property string title: ""
    property string status: ""
    property bool lit: true
    default property alias accessory: slot.data
    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(ghIcon.implicitHeight, ghLabels.implicitHeight, slot.height)
    Text {
      id: ghIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: gh.icon
      color: root.fg
      font.family: root.fam
      font.pixelSize: Style.font.display
      opacity: gh.lit ? 1.0 : 0.5
    }
    Row {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
    }
    Column {
      id: ghLabels
      anchors.left: ghIcon.right
      anchors.leftMargin: Style.space(14)
      anchors.right: slot.left
      anchors.rightMargin: slot.width > 0 ? Style.space(12) : 0
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        text: gh.title
        color: root.fg; font.family: root.fam; font.pixelSize: Style.font.title; font.bold: true
        elide: Text.ElideRight; width: parent.width
      }
      Text {
        text: gh.status.toUpperCase()
        color: root.dim; font.family: root.fam; font.pixelSize: Style.font.caption
        font.bold: true; font.letterSpacing: 1.2
        elide: Text.ElideRight; width: parent.width
      }
    }
  }

  // Section header with an optional right-aligned detail.
  component SectionTitle: Item {
    property string text: ""
    property string trailing: ""
    width: parent ? parent.width : implicitWidth
    implicitHeight: header.implicitHeight
    PanelSectionHeader { id: header; text: parent.text; foreground: root.fg; fontFamily: root.fam; anchors.left: parent.left }
    Text {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      text: parent.trailing; color: root.dim
      font.family: root.fam; font.pixelSize: Style.font.caption
    }
  }

  // Two-line selectable row: icon · title / subtitle · check when current.
  component ModelRow: CursorSurface {
    id: row
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property bool pending: false
    property string tip: ""
    signal activated()
    hasCursor: rowMouse.containsMouse && row.enabled
    foreground: root.fg
    fill: root.hoverFill
    currentFill: root.selectedFill
    opacity: enabled ? 1.0 : 0.45
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: row.activated()
    }
    PanelToolTip { visible: row.tip !== "" && rowMouse.containsMouse; text: row.tip; fontFamily: root.fam }

    Item {
      id: content
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Math.max(rowIcon.implicitHeight, info.implicitHeight)
      Text {
        id: rowIcon
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        text: row.icon; color: row.current ? root.fg : root.dim
        font.family: root.fam; font.pixelSize: Style.font.heading
      }
      Column {
        id: info
        anchors.left: rowIcon.right; anchors.leftMargin: Style.space(10)
        anchors.right: mark.left; anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        Text { text: row.title; color: root.fg; font.family: root.fam; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width }
        Text { visible: row.subtitle !== ""; text: row.subtitle; color: root.dim; font.family: root.fam; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: parent.width }
      }
      Text {
        id: mark
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        text: row.pending ? "…" : row.current ? "󰄬" : ""
        color: root.fg; font.family: root.fam; font.pixelSize: Style.font.heading
        width: implicitWidth
      }
    }
  }
}
