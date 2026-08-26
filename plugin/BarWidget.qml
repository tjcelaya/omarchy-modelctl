import QtQuick
import Quickshell
import Quickshell.Io

// modelctl — loaded local model + one entry per running herdr agent.
// Deliberately distinct from omarchy.agents, which reports Claude subscription usage.
Item {
  id: root

  // Injected by the bar host.
  property var bar
  property string moduleName: "tj.modelctl"
  property var settings: ({})

  readonly property int refreshSec: (settings && settings.refreshIntervalSec) || 5
  readonly property int port:       (settings && settings.port) || 8090
  readonly property bool showCwd:   settings ? settings.showCwd !== false : true

  property string state: "off"      // off | loading | ready
  property string model: ""
  property string freeMem: ""
  property string unit: ""
  property var agents: []

  readonly property color fg:     bar ? bar.foreground : "white"
  readonly property string fam:   bar ? bar.fontFamily : "monospace"
  readonly property bool vertical: bar ? (bar.position === "left" || bar.position === "right") : false

  implicitWidth: vertical ? 28 : row.implicitWidth + 16
  implicitHeight: bar ? bar.barSize : 26

  function scriptDir() { return Quickshell.env("HOME") + "/.config/omarchy/bar/scripts" }
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
          root.freeMem = d.free  || ""
          root.unit    = d.unit  || ""
          root.agents  = d.agents || []
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
    spacing: 8
    visible: !root.vertical

    // ── model ─────────────────────────────────────────────────────────────
    Text {
      anchors.verticalCenter: parent.verticalCenter
      font.family: root.fam
      font.pixelSize: 12
      color: root.fg
      opacity: root.state === "ready" ? 1.0 : 0.55
      text: "󰚩 " + (root.state === "ready" ? (root.model || "local")
                   : root.state === "loading" ? "···" : "off")
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

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.agents.length > 0
      font.family: root.fam; font.pixelSize: 12
      color: root.fg; opacity: 0.35
      text: "│"
    }

    // ── one entry per agent ───────────────────────────────────────────────
    Repeater {
      model: root.agents
      delegate: Text {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        font.family: root.fam
        font.pixelSize: 12
        color: root.fg
        // Focused agent is full strength; working reads brighter than idle.
        opacity: modelData.focused ? 1.0 : (modelData.status === "working" ? 0.8 : 0.5)
        text: "󱃒 " + modelData.name
              + (root.showCwd && modelData.cwd ? " " + modelData.cwd : "")
              + (modelData.focused ? " ●" : "")
        MouseArea {
          anchors.fill: parent
          onClicked: root.run("herdr agent focus " + modelData.pane)
        }
      }
    }
  }

  // Vertical bars have no room for the list; show the glyph and let the menu do the rest.
  Text {
    anchors.centerIn: parent
    visible: root.vertical
    font.family: root.fam; font.pixelSize: 12
    color: root.fg
    text: "󰚩"
    MouseArea { anchors.fill: parent; onClicked: root.run(root.scriptDir() + "/modelctl-menu") }
  }
}
