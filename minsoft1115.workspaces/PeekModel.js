.pragma library

// Build the peek model straight from Quickshell's Hyprland objects. No process
// spawn: HyprlandToplevel.lastIpcObject is already the `hyprctl clients` JSON
// entry for that window, kept up to date off the Hyprland event socket.

function clientOf(toplevel) {
  var raw = toplevel.lastIpcObject || {}
  var wl = toplevel.wayland || null
  return {
    address: String(raw.address || ""),
    title: String(toplevel.title || (wl ? wl.title : "") || ""),
    appId: String((wl ? wl.appId : "") || raw.class || ""),
    cls: String(raw.class || ""),
    floating: raw.floating === true,
    xwayland: raw.xwayland === true,
    // Lower means more recently focused; 0 is the active window.
    mru: typeof raw.focusHistoryID === "number" ? raw.focusHistoryID : 9999,
    activated: toplevel.activated === true,
    urgent: toplevel.urgent === true
  }
}

// Only workspaces that actually hold windows are worth showing; an empty one
// says nothing the bar itself does not already say.
function build(workspaces, focusedId) {
  var out = []
  for (var i = 0; i < workspaces.length; i++) {
    var ws = workspaces[i]
    if (!ws || ws.id <= 0) continue

    var tops = ws.toplevels ? ws.toplevels.values : []
    if (!tops || tops.length === 0) continue

    var clients = []
    for (var j = 0; j < tops.length; j++) {
      if (tops[j]) clients.push(clientOf(tops[j]))
    }
    clients.sort(function(a, b) { return a.mru - b.mru })

    out.push({
      id: ws.id,
      name: String(ws.name || ws.id),
      focused: ws.id === focusedId,
      clients: clients
    })
  }
  out.sort(function(a, b) { return a.id - b.id })
  return out
}
