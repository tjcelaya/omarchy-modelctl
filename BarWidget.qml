import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// modelctl — loaded local model + one entry per running herdr agent.
// Deliberately distinct from omarchy.agents, which reports Claude subscription usage.
Item {
  id: root

  // Injected by the bar host.
  property var bar
  property string moduleName: "tjcelaya.modelctl"
  property var settings: ({})

  readonly property int refreshSec: (settings && settings.refreshIntervalSec) || 5
  readonly property int port:       (settings && settings.port) || 8090
  readonly property bool showCwd:   settings ? settings.showCwd !== false : true

  property string state: "off"      // off | loading | ready
  property string model: ""
  property string freeMem: ""
  property string unit: ""
  property var agents: []
  property bool imageOn: false
  property string sdModel: "turbo"
  // Glyph settings (JetBrainsMono Nerd Font codepoints, verified to render 2026-08-27).
  // modelIcon — something that isn't Omarchy's own agents robot:
  //   󰧑 F09D1 brain      󰘚 F061A chip      󰻠 F0EE0 cpu-64-bit   󰍛 F035B memory   󰙴 F0674 sparkles
  // agentsIcon — the default 󱃒 F10D2 is a crossed-out screen and reads badly small; try:
  //   󰆍 F018D console    󰞷 F07B7 console-line (>_)    E795 dev-terminal
  //   󱚝 F169D robot-happy   󱚞 F169E robot-happy-outline   󱚥 F16A5 robot-excited   󰭆 F0B46 robot-industrial
  readonly property string modelIcon:  (settings && settings.modelIcon) || "󰚩"
  readonly property string agentsIcon: (settings && settings.agentsIcon) || "󱃒"
  // Glyphs at the shell's icon size, tags at body size — matches first-party widgets.
  readonly property int iconPx: Style.font.icon
  readonly property int textPx: Style.font.body

  readonly property color fg:     bar ? bar.foreground : "white"
  readonly property string fam:   bar ? bar.fontFamily : "monospace"
  readonly property bool anyWorking: {
    for (var i = 0; i < agents.length; i++) if (agents[i].status === "working") return true
    return false
  }
  readonly property bool vertical: bar ? (bar.position === "left" || bar.position === "right") : false

  implicitWidth: vertical ? 28 : row.implicitWidth + 16
  implicitHeight: bar ? bar.barSize : 26

  // Bar stays glanceable: icon + short tag. models.conf `tag=` wins; otherwise
  // derive one: initials of the words before the size marker + the size digits
  // (gpt-oss-20b -> go20, qwen3-coder-30b-a3b -> qc30, llama3.2:3b -> l3).
  property string modelTag: ""
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
  function sdAbbrev(id) {
    return ({turbo: "turbo", sd15: "sd15", sdxl: "sdxl", zimage: "zimg", flux: "flux", chroma: "chrm"})[id] || id
  }
  // Icon and tag as one Text with a smaller-font span, so they sit on one baseline.
  function tagged(icon, tag) {
    return tag ? icon + " <span style=\"font-size:" + root.textPx + "px\">" + tag + "</span>" : icon
  }

  // Scripts ship in bin/ next to this file, wherever the plugin folder lives.
  function scriptDir() { return Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "") }
  function run(cmd) { if (bar && bar.run) bar.run(cmd) }

  Process {
    id: poll
    command: ["bash", "-lc", root.scriptDir() + "/modelctl-barjson"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(this.text)
          root.state   = d.state || "off"
          root.model   = d.model || ""
          root.modelTag = d.tag || ""
          root.freeMem = d.free  || ""
          root.unit    = d.unit  || ""
          root.agents  = d.agents || []
          root.imageOn = d.image === true
          root.sdModel = d.sd || "turbo"
        } catch (e) {
          // Leave the last good reading in place rather than blanking the bar.
        }
      }
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    visible: !root.vertical

    // ── model ─────────────────────────────────────────────────────────────
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font.family: root.fam
      font.pixelSize: root.iconPx
      textFormat: Text.RichText
      color: root.fg
      opacity: root.state === "ready" ? 1.0 : 0.55
      text: root.tagged(root.modelIcon, root.state === "ready" ? root.abbrev(root.model)
                              : root.state === "loading" ? "···" : "")
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (m) => {
          if (m.button === Qt.LeftButton)        root.run(root.scriptDir() + "/modelctl-menu")
          else if (m.button === Qt.MiddleButton) root.run(root.scriptDir() + "/modelctl-stop")
          else root.run("omarchy-launch-or-focus-tui 'journalctl --user -u modelctl.service -u modelctl@*.service -f'")
        }
      }
    }

    // ── image generation ──────────────────────────────────────────────────
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font.family: root.fam
      font.pixelSize: root.iconPx
      textFormat: Text.RichText
      color: root.fg
      // Bright when the SD server is resident, dim when it is a one-shot launcher.
      opacity: root.imageOn ? 1.0 : 0.6
      text: root.tagged("󰋩", root.sdAbbrev(root.sdModel))
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          if (m.button === Qt.LeftButton)
            root.run(root.scriptDir() + "/modelctl-image")
          else
            root.run(root.imageOn ? "systemctl --user stop modelctl@image.service"
                                  : "systemctl --user start modelctl@image.service")
        }
      }
    }

    // ── agents: glyph always; count only when >0, lit only when >0 ─────────
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font.family: root.fam
      font.pixelSize: root.iconPx
      textFormat: Text.RichText
      color: root.fg
      opacity: root.agents.length === 0 ? 0.35 : root.anyWorking ? 1.0 : 0.8
      text: root.tagged(root.agentsIcon, root.agents.length > 0 ? String(root.agents.length) : "")
      MouseArea {
        anchors.fill: parent
        onClicked: root.run(root.scriptDir() + "/modelctl-menu agents")
      }
    }
  }

  // Vertical bars have no room for the list; show the glyph and let the menu do the rest.
  Text {
    anchors.centerIn: parent
    visible: root.vertical
    font.family: root.fam; font.pixelSize: root.iconPx
    color: root.fg
    text: root.modelIcon
    MouseArea { anchors.fill: parent; onClicked: root.run(root.scriptDir() + "/modelctl-menu") }
  }
}
