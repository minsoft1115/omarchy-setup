-- Hold Super to peek at what is on every workspace.
--
-- Installed into ~/.config/hypr/ by install-workspaces-widget.sh. The shortcut
-- names registered here are claimed by the minsoft1115.workspaces shell plugin
-- (PeekService.qml) over hyprland-global-shortcuts-v1; this file only wires
-- keys to them.
--
-- The two binds use deliberately different key strings, which is not a typo.
-- Hyprland evaluates the press before the SUPER modifier has been applied and
-- the release while it is still held, so a bare "Super_L" is what catches the
-- press and "SUPER + Super_L" is what catches the release. Binding both to the
-- same string gets you only one of the two events. (Measured on 0.56.2.)
--
-- non_consuming is required. Without it this bind swallows Super and every
-- other SUPER+X binding stops working.
local peek = hl.dsp.global("minsoft1115:workspace-peek")
local cancel = hl.dsp.global("minsoft1115:workspace-peek-cancel")

hl.bind("Super_L", peek, {
  non_consuming = true,
  description = "Peek at workspace contents",
})

hl.bind("SUPER + Super_L", peek, {
  non_consuming = true,
  release = true,
})

-- Hyprland drops the release event entirely if another key was pressed during
-- the hold, which used to strand the overlay until the plugin's own backstops
-- noticed. Those backstops watch for the compositor *moving* (workspace or
-- active window), so every SUPER chord that changes neither -- menus, panel
-- toggles, fullscreen, resize, universal copy/paste, notifications, lock --
-- left the overlay up until a safety timeout.
--
-- This watches the actual condition instead: a key going down while Super is
-- held is exactly when the release is lost, and it is also exactly when the
-- user has stopped peeking and started a chord.
--
-- Payload measured on 0.56.2: (xkb keycode, timestamp ms, 1 = down / 0 = up).
-- The same event can arrive more than once -- an input method forwarding keys
-- back produces a second copy -- but cancelling twice is a no-op.
--
-- Super's own press has to be skipped or the peek would cancel itself. The
-- press bind above is on the Super_L *keysym*, so this is the keycode that
-- carries it on a stock layout (evdev 125/126 + 8); Super_R is here only
-- because it costs nothing. Remapping Super onto another physical key would
-- need this list updated to match.
local SUPER_KEYCODES = { [133] = true, [134] = true }

-- Cheap by design: this runs on every key press in the session, so it bails on
-- the state check first and only asks the compositor about Super for real key
-- presses. Dispatching to a shortcut nobody has open is harmless -- the plugin
-- ignores a cancel it has nothing to cancel.
hl.on("input.keyboard.key", function(keycode, _, state)
  if state ~= 1 then return end
  if SUPER_KEYCODES[keycode] then return end
  if not hl.is_key_down("Super_L") then return end

  hl.dispatch(cancel)
end)
