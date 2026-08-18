# Super 홀드 워크스페이스 미리보기 — 설계와 실측 기록

> **구현 완료.** 처음 세운 설계와, 실측으로 뒤집힌 가정들을 함께 남긴다.
> 배경은 [quickshell-workspaces.md](quickshell-workspaces.md) 참고.
> 설치는 [`install-workspaces-widget.sh`](../install-workspaces-widget.sh) 가 한다.

**목표**: Super 키를 누르고 있는 동안, 창이 있는 워크스페이스들의 클라이언트 목록을
**포커스된 모니터에만** 띄우고, 떼면 사라진다.

---

## 1. 왜 위젯 하나로는 안 되는가

바 위젯은 `Bar.qml` 의 `Variants { model: Quickshell.screens }` 때문에 **모니터마다 인스턴스가 생긴다.**
그런데 `GlobalShortcut` 은 화면에 그리는 물건이 아니라 **컴포지터에 이름을 등록하는 객체**다.
위젯 안에 그냥 선언하면 모니터 수만큼 같은 이름으로 등록을 시도하고,
Hyprland 의 `CGlobalShortcutsProtocol::isTaken(appid, name)` 가 중복을 거부한다.

"포커스된 모니터에서만 생성"으로 묶는 것도 답이 아니다 — 모니터 포커스가 바뀔 때마다
단축키가 해제·재등록되면서 그 틈에 입력을 놓친다.

**등록은 딱 하나, 표시는 포커스된 모니터가.** 이걸 분리하는 게 설계의 핵심이다.

---

## 2. 구조 — service + bar-widget 한 쌍

Omarchy 에 이미 선례가 있다. `omarchy.media` 가 `kinds: ["service", "bar-widget"]` 이다.

| kind | 생성 횟수 | 생성 주체 |
|---|---|---|
| `service` | **셸당 1회** | `shell.qml` 의 `ensureService()` → `_services[id]` |
| `bar-widget` | **모니터당 1회** | `Bar.qml` 의 `Variants { model: Quickshell.screens }` |

그래서 단축키는 service 가, 팝업은 bar-widget 이 맡는다.

```
minsoft1115.workspaces/
├── manifest.json        kinds: ["bar-widget", "service"]
│                        entryPoints: { barWidget: "Workspaces.qml",
│                                       service:   "PeekService.qml" }
├── Workspaces.qml       바 위젯 (모니터당 1) — 숫자 렌더 + PopupCard 소유
├── PeekService.qml      서비스 (셸당 1)     — GlobalShortcut 소유 + 브로드캐스트
├── PeekCard.qml         팝업 내용물 레이아웃
└── PeekModel.js         워크스페이스/클라이언트 모델 빌드 (순수 JS, 테스트 쉬움)
```

### 서비스 → 위젯 경로 (확인됨)

서비스에는 셸이 `shell`, `manifest`, `pluginRegistry` 를 주입한다 (`shell.qml:305-309`).
그리고 `shell.bar` 가 살아 있는 바 인스턴스이고 (`shell.qml:186`),
`Bar.qml:470` 의 `moduleWidgets(pluginId)` 가 **살아 있는 모든 위젯 인스턴스**를 돌려준다.

```qml
// PeekService.qml 안에서
shell.bar.moduleWidgets(manifest.id)   // → [Workspaces 인스턴스, ...] (모니터당 하나)
```

`manifest.id` 를 쓰므로 플러그인 이름을 하드코딩하지 않는다.

> **주의**: `moduleWidgets` 는 **바 레이아웃 항목의 id** 로 매칭한다 (`slot.moduleName !== id`).
> 우리 위젯의 `moduleName` 은 IPC 라우팅 때문에 `"omarchy.workspaces"` 로 남겨 뒀지만,
> 레이아웃 항목 id 는 `minsoft1115.workspaces` 다. 그래서 `manifest.id` 가 맞고,
> `moduleName` 을 넘기면 빈 배열이 온다.

---

## 3. 데이터 흐름

```
Super 누름
 └─ Hyprland  bind → hl.dsp.global("minsoft1115:workspace-peek")
     └─ hyprland-global-shortcuts-v1: pressed
         └─ PeekService: GlobalShortcut.onPressed
             ├─ 디바운스 타이머 시작 (200ms)
             └─ 만료 시
                 ├─ Hyprland.refreshToplevels()      ← 제목 신선도 확보
                 └─ moduleWidgets(manifest.id) 전부에 showPeek()
                     └─ Workspaces.qml: onFocusedMonitor 인 인스턴스만 팝업 open

Super 뗌
 └─ released → 타이머 취소 + 전부에 hidePeek()

Super 홀드 중 다른 키가 내려옴
 └─ Hyprland  hl.on("input.keyboard.key")
     └─ hl.dsp.global("minsoft1115:workspace-peek-cancel")
         └─ PeekService: dismiss() — 대기 중이면 예약 취소, 떠 있으면 닫기
```

디바운스와 취소 경로가 왜 필요한지는 6장 참고.

---

## 4. 컴포넌트 스케치

### PeekService.qml (셸당 1개)

```qml
import QtQuick
import Quickshell.Hyprland

Item {
  id: root
  property var shell: null       // 셸이 주입
  property var manifest: null    // 셸이 주입

  readonly property int openDelayMs: 200

  function widgets() {
    return (shell && shell.bar && typeof shell.bar.moduleWidgets === "function" && manifest)
      ? shell.bar.moduleWidgets(manifest.id) : []
  }

  function callAll(method) {
    var items = widgets()
    for (var i = 0; i < items.length; i++)
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
  }

  GlobalShortcut {
    appid: "minsoft1115"
    name: "workspace-peek"
    description: "Peek at workspace contents while held"

    onPressed: openTimer.restart()
    onReleased: { openTimer.stop(); root.callAll("hidePeek") }
  }

  Timer {
    id: openTimer
    interval: root.openDelayMs
    onTriggered: { Hyprland.refreshToplevels(); root.callAll("showPeek") }
  }
}
```

### Workspaces.qml 에 추가되는 부분 (모니터당 1개)

```qml
  property bool peekOpen: false

  // 자기 바가 어느 화면에 떠 있는지는 QsWindow 첨부 프로퍼티로 안다
  // (PopupCard.qml:25, Bar.qml:155 에서 쓰는 관용구)
  readonly property bool onFocusedMonitor: {
    var w = root.QsWindow ? root.QsWindow.window : null
    var m = Hyprland.focusedMonitor
    return !!(w && w.screen && m && w.screen.name === m.name)
  }

  function showPeek() { peekOpen = onFocusedMonitor }
  function hidePeek() { peekOpen = false }

  PopupCard {
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.peekOpen
    triggerMode: "hover"        // 수동 오버레이 — focus grab 안 씀
    contentWidth: fittedContentWidth(Style.space(420))
    contentHeight: fittedContentHeight(peekCard.implicitHeight)

    PeekCard { id: peekCard; anchors.fill: parent }
  }
```

`PopupCard` 는 그 자체가 `PopupWindow` 이고 바 위젯 안에서 쓰는 선례가 있다
(`plugins/bar/widgets/Tray.qml:398`). 위치 계산·화면 밖 클램프·테마 테두리를 다 해준다.
`triggerMode: "hover"` 는 소스 주석 그대로 *"passive overlay; the owning widget controls open"* 이라
홀드 오버레이에 정확히 맞는다.

### PeekModel.js — 표시할 데이터

`HyprlandWorkspace.toplevels` → `HyprlandToplevel` 에서 뽑는다 (전부 메모리, 프로세스 안 띄움):

| 필드 | 출처 |
|---|---|
| 제목 | `toplevel.title` |
| 앱 id | `toplevel.wayland.appId` |
| class, pid, floating, xwayland, at, size, `focusHistoryID` | `toplevel.lastIpcObject` (= `hyprctl clients` 원본 JSON) |
| 활성/긴급 | `toplevel.activated` / `.urgent` |

클릭 동작이 필요하면 `toplevel.wayland.activate()` / `.close()` 를 그대로 쓴다
(`ActiveWindow.qml` 이 이미 하는 방식).

`focusHistoryID` 로 MRU 정렬하면 창 전환기처럼 쓸 수 있다.

> `hyprctl -j clients` 를 따로 부를 필요는 없다 — `lastIpcObject` 가 바로 그 JSON 이다.
> 다만 한 번에 일관된 스냅샷이 필요하면 `hyprctl --batch "j/workspaces ; j/clients"` 로
> 한 번에 받을 수 있다 (`-j` 와 같이 쓰면 `unknown request`). 비용은 3ms 수준.

---

## 5. Hyprland 바인딩 — 설계가 틀렸던 곳

`GlobalShortcut` 은 **이름만 등록**한다. 실제 키 연결은 Hyprland 설정이 해야 하므로
플러그인만으로는 완결되지 않는다. 저장소의 [`hypr/workspace-peek.lua`](../hypr/workspace-peek.lua)
가 그 역할이고, 스크립트가 `~/.config/hypr/` 로 복사한 뒤 `hyprland.lua` 에 require 한 줄을
마커로 감싸 넣는다.

```lua
local peek = hl.dsp.global("minsoft1115:workspace-peek")

hl.bind("Super_L",         peek, { non_consuming = true, description = "Peek at workspace contents" })
hl.bind("SUPER + Super_L", peek, { non_consuming = true, release = true })
```

실제 파일에는 이 두 바인딩 외에 **키 조합 감지 훅**이 더 있다 (6장).

**처음 설계는 두 군데가 틀렸고, 실측으로 잡았다.**

### ① 키 문자열은 `"MOD + KEY"` 다

전통적인 `hyprland.conf` 표기인 `"SUPER, Super_L"` 은 Lua API 가 거부한다.

```
hl.bind: failed to parse key string: Unknown keysym: "SUPER, Super_L", did you forget a +?
```

### ② press 와 release 의 표기가 서로 다르다

같은 키 문자열에 `release` 만 다르게 두 번 걸면 **한쪽만 발사된다.**

| 바인딩 | 언제 발사되나 |
|---|---|
| `"Super_L"` (modmask 0) | **누를 때만** |
| `"SUPER + Super_L"` (modmask 64) | **뗄 때만** |

Super 를 **누르는 순간엔 아직 SUPER 모디파이어가 안 붙어** modmask 0 으로 매칭되고,
**떼는 순간엔 아직 붙어 있어** modmask 64 로 매칭되기 때문이다.

### ③ `non_consuming` 은 선택이 아니라 필수

없으면 이 바인딩이 Super 를 삼켜 다른 `SUPER+X` 가 전부 죽는다. 붙인 상태에서
`SUPER + F12` 가 정상 발사되는 것을 확인했다.

---

## 6. 가장 큰 함정 — release 이벤트가 유실된다

**Super 를 누른 채 다른 키를 한 번이라도 누르면, 그 뒤 Super 를 떼도 release 가 오지 않는다.**
Hyprland 0.56.2 에서 `exec_cmd` 바인딩과 `hyprland-global-shortcuts-v1` **양쪽 모두** 재현됐다.

```
PRESSED  → show
(Super+F12)
         → RELEASED 없음        팝업이 열린 채 고착
```

`released` 하나에만 의존하면 안 된다는 뜻이다. 닫기를 네 겹으로 만들었고,
그중 하나가 **조건을 직접 관측**한다.

| 방어선 | 역할 |
|---|---|
| 250ms 지연 | 가장 빠른 코드 차단 (실측 간격 150~230ms 라 이것만으로는 부족하다) |
| **키 조합 감지** | Super 를 쥔 채 다른 키가 내려오면 즉시 취소 — **주 방어선** |
| 컴포지터 이동 감지 | 워크스페이스·활성 창이 바뀌면 닫기 (키와 무관한 이동도 받는다) |
| 5초 안전 타이머 | 위 셋이 놓친 것의 상한 |

### 키 조합 감지 — 원인을 그대로 본다

처음에는 컴포지터 이동 감지가 주 방어선이었다. 하지만 그건 **결과를 보는 간접 추론**이다.
release 유실의 진짜 조건은 "홀드 중 다른 키가 눌렸나" 인데, 결과를 안 남기는 조합
(메뉴·패널 토글·전체화면·리사이즈·유니버설 복사·알림·잠금) 이 Omarchy 기본 바인딩의
절반 가까이라 그만큼이 5초 타이머까지 떠 있었다. 특히 `SUPER+CTRL` 계열 41개는
거의 전부 메뉴·패널이라 **한 개도 안 잡혔다.**

Hyprland 0.56 Lua API 의 `hl.on("input.keyboard.key")` 가 조건을 그대로 준다
([`hypr/workspace-peek.lua`](../hypr/workspace-peek.lua)).

```lua
hl.on("input.keyboard.key", function(keycode, _, state)
  if state ~= 1 then return end
  if SUPER_KEYCODES[keycode] then return end
  if not hl.is_key_down("Super_L") then return end

  hl.dispatch(cancel)
end)
```

셸 쪽은 `workspace-peek-cancel` 글로벌 단축키를 하나 더 등록해 이걸 받는다.

**실측으로 확인한 것** (0.56.2, 물리 키 입력):

| | 결과 |
|---|---|
| 콜백 인자 | `(xkb 키코드, ms 타임스탬프, 1=down / 0=up)` — 스텁에는 `fun(...)` 로만 되어 있다 |
| 레이어셸 포커스 중 | **온다.** `SUPER+SPACE` 로 메뉴를 연 뒤 친 글자가 그대로 잡혔다 |
| 중복 발행 | 같은 이벤트가 두 번 오는 경우가 있다 (같은 타임스탬프). fcitx5 가 키를 되돌려 보내는 경로로 보이며, 취소는 멱등이라 무해하다 |
| `hl.is_key_down` | Super 홀드 상태를 정확히 따라온다 |

Super 자신의 press 는 걸러야 한다 — 안 그러면 팝업이 뜨자마자 스스로를 취소한다.
press 바인딩이 `Super_L` **키심**이므로 표준 배열에서 그 키심을 나르는 키코드
(`133`, evdev 125+8) 를 제외한다. Super 를 다른 물리 키로 재매핑하면 이 목록도 같이 고쳐야 한다.

비용은 상태 검사 한 번이다. 릴리스 이벤트에서 바로 빠져나가고, 실제 키 누름에 대해서만
컴포지터에 Super 상태를 묻는다.

### 컴포지터 이동 감지는 남긴다

주 방어선 자리는 내줬지만 **그 자체로 옳은 동작**이라 유지한다 — 컴포지터가 움직였으면
화면의 목록은 이미 낡았고, 키를 거치지 않은 이동(다른 창 클릭, 창 규칙, 포커스를 뺏는 알림)
도 있다. `Hyprland.focusedWorkspace` 와 `activeToplevel` 을 **Super 를 누른 시점의 값과
비교**해서 판정한다.

- **비교 방식**이라 타이밍에 의존하지 않는다. 시간 기반 유예(grace)를 먼저 시도했는데,
  유예 구간이 하필 잡아야 할 케이스(팝업 직후 `SUPER+2`)를 그대로 삼켰다.
- **기준값을 `press` 시점에 잡는 것**이 중요하다. `show` 시점 기준으로는 0.5초가 지나기
  전에 일어난 전환을 볼 수 없어서, 전환이 끝난 뒤에 팝업이 뜨는 증상이 남았다.
- `refreshToplevels()` 가 `activeToplevelChanged` 를 헛되이 재발행해도 주소가 같으면
  무시된다.

남는 빈틈은 **키도 안 누르고 컴포지터도 안 움직이는 경우**뿐이다 (`SUPER+드래그` 로 같은 창을
옮기는 정도). 5초 타이머가 받는다.

### 그 외 함정

| 함정 | 대응 |
|---|---|
| 서비스가 모니터마다 생기면 단축키 이름 충돌 | `service` kind 는 셸당 1회 — 구조로 해결 |
| 제목이 낡을 수 있음 | 팝업 열 때 `Hyprland.refreshToplevels()` |
| 팝업이 엉뚱한 모니터에 뜸 | `PopupCard` 는 `anchorItem` 의 바 윈도우에 앵커됨 → 포커스된 모니터 인스턴스가 연다 |
| `QsWindow` 가 null | `Workspaces.qml` 에 **`import Quickshell`** 이 있어야 첨부 프로퍼티가 해석된다 |
| `kinds` 에 `service` 추가 시 `shell.json` 에 `disabled` 배열이 생길 수 있음 | 실측 결과 왕복 후 잔여 키 없음 (`disabled`, `cloneSourceRestores` 모두 null) |

---

## 6-1. 팝업 폭 — 세 번 틀렸다

내용에 따라 가로로 늘어나게 만드는 데 세 번 실패했다. 전부 다른 원인이었다.

**`contentWidth` 는 내용 폭이 아니라 팝업 전체 폭이다.** `PopupCard` 가
`implicitWidth: contentWidth` 로 묶어 두므로 패딩·테두리를 포함한다. 그런데 높이 헬퍼와 달리
폭 헬퍼는 인셋을 더해 주지 않는다.

```qml
fittedContentHeight(h) → h + verticalContentInset   // 더해 줌
fittedContentWidth(w)  → w                          // 안 더해 줌
```

그래서 직접 더해야 한다.

```qml
readonly property real horizontalInset:
  padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)
contentWidth: fittedContentWidth(peekCard.implicitWidth + horizontalInset)
```

**폭 측정도 두 번 틀렸다.**

1. `width: Math.min(implicitWidth, cap)` — 자기참조 바인딩 루프.
   journal 에 `Binding loop detected for property "appColWidth"` 가 찍힌다
2. `TextMetrics` 로 측정 — **폰트 폴백을 반영하지 않아** 한글 제목을 과소 측정

최종적으로 같은 문자열을 **숨긴 `Column` 에 실제로 배치하고 그 `implicitWidth` 를 읽는다.**
실제 셰이핑 경로를 타므로 폴백까지 정확하고, 측정용 `Text` 는 내용으로만 크기가 정해지니
루프도 없다.

> **Column 에 자식 폭을 부모에 묶지 말 것.** `Column` 은 자식 폭에서 `implicitWidth` 를
> 계산하므로, 자식이 부모 폭을 따라가면 순환이 되어 카드가 최소 크기로 주저앉는다.

---

## 7. 아이콘

`DesktopEntries` + Omarchy 의 `AppLibrary` 로 해결된다.

1. `DesktopEntries.heuristicLookup(appId)` → `DesktopEntry.icon`
   (창 class 와 아이콘 이름이 다른 경우까지 처리)
2. 실패 시 `shell.appLibrary.iconSource(name)` → 앱/디바이스 컨텍스트로 제한된 인덱스,
   그 다음 테마 조회, 마지막으로 `application-x-executable`

`shell.appLibrary` (`shell.qml:20`) 는 `bar.shell` 로 닿는다. 렌더링은 트레이 위젯과 같은
패턴으로, `IconImage` 대신 `Image` 에 `sourceSize` 를 물리 픽셀로 준다 — `IconImage` 는
논리 크기를 써서 HiDPI 에서 PNG 아이콘이 뭉갠다.

---

## 8. 설치 스크립트가 하는 일

`install-workspaces-widget.sh` 가 Quickshell 플러그인과 Hyprland 바인딩을 함께 다룬다.

| 동작 | 하는 일 |
|---|---|
| `install` | 플러그인 복사 + 바에 적용 + 셸 재시작, 그리고 `workspace-peek.lua` 설치 + `hyprland.lua` 에 require 한 줄 + `hyprctl reload` |
| `revert` | require 줄 제거 + reload, 위젯은 Omarchy 기본으로 원복 (플러그인·바인딩 파일은 남김) |
| `remove` | 위 + 설치본과 바인딩 파일 삭제 |
| `status` | 위젯 상태 + 바인딩 3단계(파일 설치 / require 여부 / `Super_L` 실제 바인딩 여부) |

require 줄은 `-- workspaces-widget:begin/end` 마커로 감싸 멱등하게 넣고 뺀다.
`hyprland.lua` 와 `shell.json` 은 손대기 전에 `*.bak.<타임스탬프>` 로 백업한다.

**왕복 검증 결과** — `install` → `revert` 후:

- `Super_L` 바인딩 0개, `hyprland.lua` 마커 0개
- 바 레이아웃은 `omarchy.workspaces` 로 **제자리 복원** (위치 유지)
- `shell.json` 잔여 키 없음 (`disabled`, `cloneSourceRestores` 모두 null)

---

## 9. 최종 구성

```
minsoft1115.workspaces/
├── manifest.json      kinds: ["bar-widget", "service"]
├── Workspaces.qml     바 위젯 (모니터당 1) — 숫자 + PopupCard, 포커스 모니터 게이팅
├── PeekService.qml    서비스 (셸당 1)     — GlobalShortcut 2개 + 브로드캐스트 + 닫기 4중 방어
├── PeekCard.qml       팝업 레이아웃       — 배지 + 아이콘/앱이름/제목, 폭 실측
└── PeekModel.js       모델 빌드           — lastIpcObject 에서, 프로세스 안 띄움
hypr/workspace-peek.lua   Hyprland 바인딩 + 키 조합 감지 훅
```

튜닝 지점:

| 값 | 위치 | 현재 |
|---|---|---|
| 팝업 지연 | `PeekService.openDelayMs` | 250ms |
| 안전 타이머 | `PeekService.safetyTimeoutMs` | 5000ms |
| 제목 최대 폭 | `PeekCard.titleMaxWidth` | `Style.space(460)` |
| 아이콘 크기 | `PeekCard.iconSize` | `Style.space(14)` |
