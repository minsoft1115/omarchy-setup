// Shell-wide service half of minsoft1115.workspaces.
//
// It exists to own the GlobalShortcut. A bar widget is instantiated once per
// monitor (Bar.qml runs Variants over Quickshell.screens), while a
// GlobalShortcut is a compositor registration rather than something drawn, so
// declaring it in the widget would register the same name once per screen —
// which Hyprland rejects (CGlobalShortcutsProtocol::isTaken). A "service"
// plugin is instantiated exactly once by shell.qml, so the registration lives
// here and the popup stays in the widget.
//
// The shell injects `shell` and `manifest` (shell.qml, ensureService).
import QtQuick
import Quickshell.Hyprland

Item {
  id: root

  property var shell: null
  property var manifest: null

  // Super is a modifier, so the shortcut also fires when Super is pressed as
  // the start of SUPER+X. Measured gap from Super down to the next key was
  // 150-230ms, which this delay does not clear on its own — it does not have
  // to. A chord that slips past it moves the compositor, and onCompositorMoved
  // drops the pending open before it can fire. The delay only has to filter
  // the fastest chords; keeping it short is what makes a deliberate hold feel
  // immediate.
  readonly property int openDelayMs: 250

  // Hyprland does not deliver the shortcut's release event if another key was
  // pressed during the hold — verified on 0.56.2, both through exec_cmd binds
  // and through hyprland-global-shortcuts-v1. Relying on `released` alone
  // therefore strands the overlay open. The compositor-moved backstop below
  // catches most of it; this is the hard ceiling for anything it misses, so
  // the overlay can never outlive its welcome by more than a few seconds.
  readonly property int safetyTimeoutMs: 5000

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : ""
  property bool peeking: false

  // Compositor state as it was when Super went down — not when the overlay
  // opened. The window between the two is exactly where a chord lands, and a
  // baseline taken at open time cannot see a switch that already happened.
  //
  // Comparing values rather than reacting to any change signal also keeps
  // refreshToplevels() from closing the overlay by re-emitting
  // activeToplevelChanged with nothing actually moved.
  property int armedWorkspaceId: -1
  property string armedToplevelAddress: ""

  // Live widget instances of this plugin, one per monitor. Keyed by the bar
  // layout entry id, which is the plugin id — not the widget's moduleName,
  // which deliberately stays "omarchy.workspaces" for IPC routing.
  function widgets() {
    if (!shell || !shell.bar || typeof shell.bar.moduleWidgets !== "function" || !pluginId) return []
    return shell.bar.moduleWidgets(pluginId)
  }

  function callAll(method) {
    var items = widgets()
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }

  function currentWorkspaceId() {
    return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  }

  function currentToplevelAddress() {
    return Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address || "") : ""
  }

  function arm() {
    armedWorkspaceId = currentWorkspaceId()
    armedToplevelAddress = currentToplevelAddress()
    openTimer.restart()
  }

  function show() {
    // Hyprland's event socket does not push every title change, so pull a
    // fresh snapshot before the list is read.
    Hyprland.refreshToplevels()
    peeking = true
    safetyTimer.restart()
    callAll("showPeek")
  }

  // Something moved under us. If the overlay is already up, close it; if it is
  // still counting down, drop the pending open — the user is mid-chord, and
  // letting the timer fire would put the overlay up *after* the action it was
  // never meant to interrupt, with no release event coming to take it down.
  function onCompositorMoved(reason) {
    if (openTimer.running) {
      openTimer.stop()
      console.log("peek: pending open cancelled -", reason)
      return
    }
    hide(reason)
  }

  function hide(reason) {
    openTimer.stop()
    safetyTimer.stop()
    if (!peeking) return
    peeking = false
    callAll("hidePeek")
    console.log("peek: hidden -", reason)
  }

  GlobalShortcut {
    appid: "minsoft1115"
    name: "workspace-peek"
    description: "Peek at workspace contents while held"

    onPressed: root.arm()
    onReleased: root.hide("released")
  }

  Timer {
    id: openTimer
    interval: root.openDelayMs
    onTriggered: root.show()
  }

  Timer {
    id: safetyTimer
    interval: root.safetyTimeoutMs
    onTriggered: root.hide("safety-timeout")
  }

  // Backstops for the lost release. Whatever the user did with SUPER+X almost
  // always lands here: switching workspace, focusing or opening a window. It is
  // also the right behaviour on its own — once the compositor state moves, the
  // list on screen is stale.
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      if (root.currentWorkspaceId() !== root.armedWorkspaceId)
        root.onCompositorMoved("workspace-changed")
    }
    function onActiveToplevelChanged() {
      if (root.currentToplevelAddress() !== root.armedToplevelAddress)
        root.onCompositorMoved("toplevel-changed")
    }
  }
}
