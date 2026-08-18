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

-- fcitx5 가 사라질 때 눌린 키를 컴포지터가 놓아주게 한다.
--
-- 입력기는 처리한 키를 가상 키보드로 앱에 되전달한다. 그 가상 키보드가
-- 없어지는 순간(fcitx5 종료·재시작·크래시) 눌린 상태로 남은 키가 있으면,
-- Hyprland 는 기본값(release_pressed_on_close = false)에서 그것을 풀지 않는다.
-- 컴포지터가 계속 눌렸다고 믿으니 자동 반복이 멈추지 않는다 — Enter 였다면
-- 빈 명령이 끝없이 실행되고, 다른 키를 한 번 눌러야(또는 Ctrl-C) 멎는다.
--
-- 재현으로 확인한 값 (가상 키보드가 Return 을 쥔 채 사라지게 만들고, 포커스된
-- 창이 받은 줄 수를 셌다):
--
--   false → 2.5초에 92줄, 4.5초에 172줄, 그대로 두면 646줄까지 (초당 40줄)
--   true  → 1줄에서 멈춤
--
-- 릴리스를 한 번 넣어 주면 멎는다. 사람이 Ctrl-C 나 아무 키로 푸는 것과 같다.
hl.config({
  input = {
    virtualkeyboard = {
      release_pressed_on_close = true,
    },
  },
})
