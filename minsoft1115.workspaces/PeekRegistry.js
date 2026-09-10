.pragma library

// Live Workspaces.qml instances, one per monitor.
//
// PeekService used to ask the host bar for these via shell.bar.moduleWidgets.
// From Omarchy 4.0.3 a third-party plugin's shell.bar is a sandbox facade
// without that function, so the overlay armed but never appeared. The widgets
// register themselves here instead; the host is not involved.

var items = []

function register(widget) {
  if (!widget) return
  for (var i = 0; i < items.length; i++) {
    if (items[i] === widget) return
  }
  items.push(widget)
}

function unregister(widget) {
  var next = []
  for (var i = 0; i < items.length; i++) {
    if (items[i] !== widget) next.push(items[i])
  }
  items = next
}

function all() {
  return items.slice()
}
