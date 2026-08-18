-- Right Alt as the Hangul key, for the fcitx5 hangul input method.
--
-- Installed to ~/.config/minsoft1115/hypr/ by setup-korean.sh, which adds one
-- require line to ~/.config/hypr/hyprland.lua between markers. Omarchy's own
-- input.lua is never edited.
--
-- kb_options is replaced wholesale rather than added to, so whatever is already
-- set has to be carried over. It is read here at load time instead of being
-- baked in when the script runs: an Omarchy update that changes the default
-- options is then picked up on the next reload, with nothing to reinstall and
-- no stale copy of the old defaults left behind in a config file.
--
-- The guard matters because this file is loaded after Omarchy's defaults on
-- every reload, and a value that already carries the option must not grow a
-- second copy of it.
local current = hl.get_config("input.kb_options") or ""

if not current:find("korean:ralt_hangul", 1, true) then
  hl.config({
    input = {
      kb_options = current ~= "" and current .. ",korean:ralt_hangul" or "korean:ralt_hangul",
    },
  })
end
