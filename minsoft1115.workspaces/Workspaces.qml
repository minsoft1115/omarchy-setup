// Clone of omarchy.workspaces. Changes from upstream are marked "CHANGE" below.
//
// Upstream draws the focused workspace as a filled glyph (U+F14FB) instead of
// its number. Here every workspace keeps its number, and focus is shown as a
// filled rounded box behind the number, painted in the bar's normal text color
// with the number itself inverted to the bar background color and set in bold.
//
// moduleName intentionally keeps the upstream id: the shell routes IPC to this
// widget through the manifest's clonedFrom, so renaming it would break that.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "PeekModel.js" as PeekModel

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // ---- focus box tuning ------------------------------------------------
  // Vertical inset keeps the box clear of the bar edges; whatever height is
  // left over is the box height. Horizontal inset keeps neighbouring cells apart.
  readonly property int focusInsetY: Style.space(5)
  readonly property int focusInsetX: Style.space(1)
  // Corner rounding. Small on purpose: a box with softened corners, not a pill.
  // Set to 0 for hard corners, or height / 2 for a full pill.
  readonly property int focusRadius: Style.space(2)
  // Box fill. Deliberately the ordinary bar text color rather than the theme
  // accent, so focus reads as an inversion instead of a second color.
  readonly property color focusFillColor: root.bar ? root.bar.barForeground : Color.bar.text
  // Number color inside the box, and everywhere else.
  readonly property color focusedTextColor: root.bar ? root.bar.background : Color.bar.background
  readonly property color normalTextColor: root.bar ? root.bar.barForeground : Color.bar.text
  // Bold the focused number. WidgetButton's own label has no bold switch, which
  // is why the label is turned off below and the number drawn here instead.
  readonly property bool boldWhenFocused: true
  // Opacity of a workspace with no windows on it. This is not a separate color:
  // the same bar text color is composited over the bar background, so lowering
  // it pushes empty workspaces further toward the background and widens the gap
  // against the ones that do hold windows. 1.0 would make them indistinguishable.
  readonly property real emptyOpacity: 0.32

  // ---- Super-hold peek (driven by PeekService) -------------------------
  // The service owns the GlobalShortcut and calls these on every live widget
  // instance; each instance decides whether the overlay belongs on its screen.
  property bool peekOpen: false
  property var peekModel: []

  // Which screen this bar surface is on. QsWindow is the attached property the
  // rest of the shell uses for the same question (PopupCard.qml, Bar.qml).
  readonly property bool onFocusedMonitor: {
    var win = root.QsWindow ? root.QsWindow.window : null
    var mon = Hyprland.focusedMonitor
    return !!(win && win.screen && mon && win.screen.name === mon.name)
  }

  function showPeek() {
    if (!onFocusedMonitor) return
    peekModel = PeekModel.build(Hyprland.workspaces.values,
                                Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
    peekOpen = peekModel.length > 0
  }

  function hidePeek() {
    peekOpen = false
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // CHANGE 1: a gap in front of the first cell. Upstream sits flush against
  // whatever precedes it in the bar section (the Omarchy menu), which reads as
  // cramped now that the focused cell carries a filled box right up to its
  // edge. Goes through Style.space so it tracks the theme's spacing scale like
  // the trailing gap already does.
  readonly property real leadingGap: root.vertical ? 0 : Style.space(10)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + leadingGap + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.leftMargin: root.leadingGap
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        // CHANGE 2: always draw the number, focused or not. 10 renders as "0"
        // to match the SUPER+0 keybinding.
        text: modelData === 10 ? "0" : String(modelData)
        // CHANGE 3: hide WidgetButton's built-in label and paint the number
        // below instead. The built-in label exposes family and pixel size but
        // no weight, and the focused number needs to be bold. Sizing, hit
        // testing, and tooltips still come from WidgetButton.
        labelVisible: false
        opacity: occupied || focused ? 1 : root.emptyOpacity
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // CHANGE 4: the focus box.
        //   WidgetButton has no background of its own (just a Text and a
        //   MouseArea). Children added at the call site are appended last and
        //   paint on top, so the box needs z: -1 to sit behind the number.
        Rectangle {
          z: -1
          anchors.fill: parent
          anchors.topMargin: root.focusInsetY
          anchors.bottomMargin: root.focusInsetY
          anchors.leftMargin: root.focusInsetX
          anchors.rightMargin: root.focusInsetX
          visible: cell.focused
          color: root.focusFillColor
          radius: root.focusRadius

          Behavior on color {
            enabled: !root.bar || root.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }

        // CHANGE 5: the number itself, drawn above the focus box. Declared
        // after the box so it paints on top; the box sits at z: -1.
        Text {
          anchors.centerIn: parent
          text: cell.text
          color: cell.focused ? root.focusedTextColor : root.normalTextColor
          font.family: cell.fontFamily
          font.pixelSize: cell.fontSize
          font.bold: root.boldWhenFocused && cell.focused
          renderType: Text.NativeRendering
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter

          Behavior on color {
            enabled: !root.bar || root.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }
      }
    }
  }

  // The peek overlay. PopupCard is itself a PopupWindow and is used the same
  // way from Tray.qml; triggerMode "hover" is its passive mode, where the
  // owning widget drives `open` and no focus grab is taken.
  PopupCard {
    id: peekPopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.peekOpen
    triggerMode: "hover"
    // contentWidth is the whole popup width (PopupCard binds implicitWidth to
    // it), while the content sits inside padding and border on both sides.
    // fittedContentHeight adds that inset for you; the width helper does not,
    // so the horizontal inset has to be added here or long lines get clipped.
    readonly property real horizontalInset:
      padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)
    contentWidth: fittedContentWidth(
      Math.max(Style.space(320), peekCard.implicitWidth + horizontalInset))
    contentHeight: fittedContentHeight(peekCard.implicitHeight)

    PeekCard {
      id: peekCard
      anchors.fill: parent
      model: root.peekModel
      appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    }
  }

}
