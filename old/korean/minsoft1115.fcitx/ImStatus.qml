import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "minsoft1115.fcitx"

  // fcitx5-remote: 0 closed, 1 inactive, 2 active.
  property int imState: 0
  property string imName: ""
  readonly property bool hangul: imState === 2 && imName === "hangul"

  function refresh() {
    if (!queryProc.running)
      queryProc.running = true
  }

  function toggle() {
    if (root.bar)
      root.bar.run("fcitx5-remote -t")
    followupTimer.restart()
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: followupTimer
    interval: 120
    onTriggered: root.refresh()
  }

  Process {
    id: queryProc
    command: ["sh", "-c",
      'fcitx5-remote --check >/dev/null 2>&1 || { echo "0"; exit 0; }; printf "%s %s\\n" "$(fcitx5-remote)" "$(fcitx5-remote -n)"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        var n = parseInt(parts[0] || "0", 10)
        root.imState = isNaN(n) ? 0 : n
        root.imName = parts[1] || ""
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: iconComp
    tooltipText: root.hangul ? "한글" : "영문"
    onPressed: function() { root.toggle() }
  }

  Component {
    id: iconComp
    Item {
      readonly property int px: Math.round(Math.min(width, height) * Screen.devicePixelRatio)

      Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("hangul.svg")
        sourceSize.width: parent.px
        sourceSize.height: parent.px
        visible: root.hangul
      }

      Image {
        id: latinGlyph
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("latin.svg")
        sourceSize.width: parent.px
        sourceSize.height: parent.px
        visible: !root.hangul
        layer.enabled: true
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: root.bar ? root.bar.barForeground : Color.foreground
        }
      }
    }
  }
}
