-- Hold Super to peek at what is on every workspace.
--
-- Installed into ~/.config/hypr/ by install-workspaces-widget.sh. The shortcut
-- name registered here is claimed by the minsoft1115.workspaces shell plugin
-- (PeekService.qml) over hyprland-global-shortcuts-v1; this file only wires
-- keys to it.
--
-- The two binds use deliberately different key strings, which is not a typo.
-- Hyprland evaluates the press before the SUPER modifier has been applied and
-- the release while it is still held, so a bare "Super_L" is what catches the
-- press and "SUPER + Super_L" is what catches the release. Binding both to the
-- same string gets you only one of the two events. (Measured on 0.56.2.)
--
-- non_consuming is required. Without it this bind swallows Super and every
-- other SUPER+X binding stops working.
--
-- Note that Hyprland drops the release event entirely if another key was
-- pressed during the hold; the plugin has its own backstops for that.
local peek = hl.dsp.global("minsoft1115:workspace-peek")

hl.bind("Super_L", peek, {
  non_consuming = true,
  description = "Peek at workspace contents",
})

hl.bind("SUPER + Super_L", peek, {
  non_consuming = true,
  release = true,
})
