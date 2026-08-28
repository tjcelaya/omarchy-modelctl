import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// modelctl — three bar segments (loaded LLM · image model · running agents) and one
// dropdown panel: switch the llama.cpp model, pick the image model, keep the image
// server resident, generate, jump to an agent. Same panel kit as the first-party
// Bluetooth / Wi-Fi dropdowns, so it looks and behaves like them.
Panel {
  id: root
  moduleName: "tjcelaya.modelctl"
  ipcTarget: "tjcelaya.modelctl"   // omarchy shell tjcelaya.modelctl toggle|open|close

  readonly property int refreshSec: (settings && settings.refreshIntervalSec) || 5
  readonly property string modelIcon:  (settings && settings.modelIcon) || "󰚩"
  readonly property string agentsIcon: (settings && settings.agentsIcon) || "󱃒"
  readonly property string imageIcon: "󰋩"

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
  readonly property bool anyWorking: {
    for (var i = 0; i < agents.length; i++) if (agents[i].status === "working") return true
    return false
  }

  // Bar stays glanceable: icon + short tag. models.conf `tag=` wins; otherwise
  // initials of the words before the size marker + the size digits
  // (gpt-oss-20b -> go20, qwen3-coder-30b-a3b -> qc30, llama3.2:3b -> l3).
  function abbrev(id) {
    if (root.modelTag) return root.modelTag
    if (!id) return ""
    var words = String(id).toLowerCase().split(/[-_:\/\s]+/).filter(function(w) { return w })
    var size = -1
    for (var i = 0; i < words.length; i++) if (/^\d+(\.\d+)?b$/.test(words[i])) { size = i; break }
    if (size < 0) return words.join("").replace(/[^a-z0-9]/g, "").slice(0, 5)
    var init = words.slice(0, size).map(function(w) { return w[0] }).join("").slice(0, 3)
    return init + words[size].replace(/\.\d+b$|b$/, "")
  }
  function sdAbbrev(id) { return root.sdTag || String(id).slice(0, 5) }
  // While generating: "<tag> 37%" once sd-cli reports a phase fraction, else "<tag> 1:05".
  function busyText() {
    if (!root.busy) return ""
    var b = root.busy, tag = b.model === root.sdModel ? root.sdAbbrev(b.model) : String(b.model).slice(0, 5)
    var m = /^(\d+)\/(\d+)$/.exec(b.progress || "")
    if (m && Number(m[2]) > 0) return tag + " " + Math.floor(100 * Number(m[1]) / Number(m[2])) + "%"
    var s = Number(b.elapsed || 0)
    return tag + " " + Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
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

  // ── bar segments ───────────────────────────────────────────────────────────
  // WidgetButton, not BarIconButton: these carry a glyph *and* a short tag, and the
  // icon button is a fixed single-glyph slot that squashes anything longer.
  Row {
    id: segments
    spacing: 0

    WidgetButton {
      id: modelButton
      bar: root.bar
      fontSize: Style.font.body
      horizontalMargin: 6
      text: root.modelIcon + (root.state === "ready" ? " " + root.abbrev(root.model) : root.state === "loading" ? " ···" : "")
      dimmed: root.state !== "ready"
      tooltipText: root.heroStatus() + "\nLeft: dropdown · Middle: stop · Right: logs"
      onPressed: function(b) {
        if (b === Qt.MiddleButton) root.stopLlm()
        else if (b === Qt.RightButton) root.run(["omarchy-launch-or-focus-tui", "journalctl --user -u modelctl.service -u 'modelctl@*.service' -f"])
        else root.toggle()
      }
    }
    WidgetButton {
      id: imageButton
      bar: root.bar
      fontSize: Style.font.body
      horizontalMargin: 6
      text: root.imageIcon + " " + (root.busy ? root.busyText() : root.sdAbbrev(root.sdModel))
      dimmed: !root.busy && !root.imageOn
      tooltipText: (root.busy ? "Generating with " + root.busy.model + " · " + root.busy.prompt
                              : "Image model: " + (root.sdModel || "none")) + "\nLeft: dropdown · Right: generate"
      SequentialAnimation on opacity {
        running: root.busy !== null; loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 700 } NumberAnimation { to: 1.0; duration: 700 }
      }
      onPressed: function(b) {
        if (b === Qt.RightButton) root.generate()
        else root.toggle()
      }
    }
    WidgetButton {
      id: agentsButton
      bar: root.bar
      fontSize: Style.font.body
      horizontalMargin: 6
      text: root.agentsIcon + (root.agents.length > 0 ? " " + root.agents.length : "")
      dimmed: root.agents.length === 0
      tooltipText: root.agents.length === 0 ? "No coding agents running" : root.agents.length + " agent(s) running · click for the list"
      onPressed: function(b) { root.toggle() }
    }
  }

  // ── dropdown ───────────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: segments
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)   // clamps to the screen; lists cap themselves

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "g" || t === "G") root.generate()
        if (t === "s" || t === "S") root.toggleServer()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ---------- Hero: icon · title · status · server switch ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, serverSwitch.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.modelIcon
            color: root.fg
            font.family: root.fam
            font.pixelSize: Style.font.display
            opacity: root.state === "ready" ? 1.0 : 0.5
          }
          ToggleSwitch {
            id: serverSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
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
          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: serverSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "Local models"
              color: root.fg; font.family: root.fam; font.pixelSize: Style.font.title; font.bold: true
              elide: Text.ElideRight; width: parent.width
            }
            Text {
              text: root.heroStatus().toUpperCase()
              color: root.dim; font.family: root.fam; font.pixelSize: Style.font.caption
              font.bold: true; font.letterSpacing: 1.2
              elide: Text.ElideRight; width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- llama.cpp ----------
        SectionTitle { text: "LLAMA.CPP"; trailing: root.llms.length + " model" + (root.llms.length === 1 ? "" : "s") }
        Text {
          visible: root.llms.length === 0
          width: parent.width; wrapMode: Text.WordWrap
          text: "No GGUF models found. Put some under MODELCTL_MODEL_DIRS, or pull one with LM Studio or Ollama."
          color: root.dim; font.family: root.fam; font.pixelSize: Style.font.bodySmall
        }
        ListView {
          id: llmList
          width: parent.width
          height: Math.min(contentHeight, Style.space(240))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
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

        PanelSeparator { foreground: root.fg }

        // ---------- stable-diffusion ----------
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
          id: sdList
          width: parent.width
          height: Math.min(contentHeight, Style.space(200))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
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
        Toggle {
          width: parent.width
          label: "Keep image server loaded"
          description: "Resident sd-server on :8091 · off = each image loads its model fresh"
          checked: root.imageOn
          foreground: root.fg; fontFamily: root.fam
          onClicked: root.toggleImageServer()
        }
        Button {
          width: parent.width
          text: root.busy ? "Generate another image…  (queues)" : "Generate image…"
          iconText: root.imageIcon
          tooltipText: "Prompt via the Omarchy input popup · uses " + (root.sdModel || "the selected model")
          foreground: root.fg; fontFamily: root.fam
          onClicked: root.generate()
        }

        PanelSeparator { foreground: root.fg }

        // ---------- agents ----------
        SectionTitle { text: "AGENTS"; trailing: root.agents.length === 0 ? "none running" : root.agents.length + " running" }
        ListView {
          id: agentList
          visible: root.agents.length > 0
          width: parent.width
          height: Math.min(contentHeight, Style.space(160))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
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
