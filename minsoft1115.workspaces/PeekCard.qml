// Contents of the Super-hold peek popup: every workspace that holds windows,
// with its clients listed most-recently-focused first.
//
// Sizing: nothing binds a width to its parent, because a Column takes its
// implicitWidth from its children and a child sized from the Column would make
// that circular, collapsing the card. Column widths are measured imperatively
// on model change rather than through a binding — measuring mutates the shared
// TextMetrics, so doing it inside a binding is itself a loop and the width
// silently freezes at a stale value (which clipped titles until it was fixed).
import Quickshell
import QtQuick
import qs.Commons

Item {
  id: root

  // Array produced by PeekModel.build().
  property var model: []
  // Omarchy's AppLibrary (shell.appLibrary), for icon resolution.
  property var appLibrary: null

  property color textColor: Color.popups.text
  property color accentColor: Color.bar.active

  // A single pathological window title should not stretch the card across the
  // screen; past this the title elides.
  readonly property int titleMaxWidth: Style.space(460)
  readonly property int badgeWidth: Style.space(18)
  readonly property int iconSize: Style.space(14)

  // Column widths come from measuring the real text. TextMetrics was tried
  // first and under-measured: it does not account for the font fallback that
  // actual rendering uses, so CJK titles came out narrower than they draw and
  // silently clipped. Laying the same strings out in a hidden Column and
  // reading its implicitWidth goes through the real shaping path instead.
  //
  // No binding loop here: these Texts size themselves from their content only,
  // never from the widths derived from them.
  readonly property var flatClients: {
    var out = []
    for (var i = 0; i < (model ? model.length : 0); i++) {
      var clients = model[i].clients
      for (var j = 0; j < clients.length; j++) out.push(clients[j])
    }
    return out
  }

  // One drawn row's width, added up from the measured columns. It cannot be
  // taken from the parent: PopupCard sizes itself from this card's
  // implicitWidth, which comes from the Column, so a child sized by the Column
  // would close the loop the header warns about. The separator is the only
  // thing here that needs a width of its own, and this is where it gets it.
  readonly property real contentWidth: badgeWidth + Style.space(10) + iconSize
    + Style.space(8) + appColWidth + Style.space(8) + titleColWidth

  readonly property real appColWidth: appMeasure.implicitWidth
  readonly property real titleColWidth: Math.min(titleMeasure.implicitWidth, titleMaxWidth)

  Column {
    id: appMeasure
    visible: false
    Repeater {
      model: root.flatClients
      Text {
        required property var modelData
        text: modelData.appId
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Column {
    id: titleMeasure
    visible: false
    Repeater {
      model: root.flatClients
      Text {
        required property var modelData
        text: modelData.title
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // Window class is not always the icon name, so ask the desktop entry index
  // first and only fall back to treating the class as a themed icon name.
  // AppLibrary.iconSource() already ends in a generic executable icon.
  function iconFor(client) {
    var entry = null
    try {
      entry = DesktopEntries.heuristicLookup(client.appId)
        || DesktopEntries.heuristicLookup(client.cls)
    } catch (e) { }
    var name = entry && entry.icon ? String(entry.icon) : String(client.appId || client.cls || "")
    return appLibrary ? appLibrary.iconSource(name) : ""
  }

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight

  Column {
    id: column
    // Half of the gap between groups; the other half sits under the separator.
    // Less than it used to be, because the line now does the work the empty
    // space was doing alone.
    spacing: Style.space(8)

    Repeater {
      model: root.model

      Column {
        required property var modelData
        required property int index
        spacing: Style.space(8)

        // Groups run together without this: with three or more windows in one
        // workspace the gap between groups stops reading as larger than the gap
        // between rows, and the badge -- which only sits beside the first row --
        // is too far away to say where the group ended.
        //
        // Faint on purpose. Window titles sit at 0.7-1.0 and an inactive badge
        // at 0.45, so a separator any brighter than this reads as one more line
        // of content rather than as structure. (0.5 was tried and does exactly
        // that.) An invisible item is skipped by the Column, so the first group
        // keeps its spacing.
        Rectangle {
          visible: index > 0
          width: root.contentWidth
          height: 1
          color: root.textColor
          opacity: 0.15
        }

        // Badge on the left, its windows stacked to the right of it. Keeping the
        // list on the badge's row uses the space the window count used to take.
        Row {
          spacing: Style.space(10)

          Rectangle {
            width: root.badgeWidth
            height: Style.space(16)
            radius: Style.space(2)
            color: modelData.focused ? root.textColor : "transparent"
            border.width: modelData.focused ? 0 : 1
            border.color: root.textColor
            opacity: modelData.focused ? 1 : 0.45

            Text {
              anchors.centerIn: parent
              text: modelData.name
              color: modelData.focused ? Color.popups.background : root.textColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: modelData.focused
              renderType: Text.NativeRendering
            }
          }

          Column {
            spacing: Style.space(3)

            Repeater {
              model: modelData.clients

              Row {
                required property var modelData
                spacing: Style.space(8)

                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.iconSize
                  height: root.iconSize
                  fillMode: Image.PreserveAspectFit
                  // Decode at physical pixels, as the tray widget does: sizing a
                  // PNG icon by logical pixels leaves it upscaled on HiDPI.
                  sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
                  sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
                  source: root.iconFor(modelData)
                  opacity: modelData.activated ? 1 : 0.75
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.appColWidth
                  text: modelData.appId
                  color: root.accentColor
                  opacity: modelData.activated ? 1 : 0.75
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.titleColWidth
                  text: modelData.title
                  color: root.textColor
                  opacity: modelData.activated ? 1 : 0.7
                  elide: Text.ElideRight
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }
      }
    }
  }
}
