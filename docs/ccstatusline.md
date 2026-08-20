# Claude status line (install-ccstatusline.sh)

Claude Code 입력창 아래 status line 을
[ccstatusline](https://github.com/sirmalloc/ccstatusline) 으로 채운다.
사용량을 보려고 바의 아이콘을 클릭할 필요 없이, 세션을 쓰는 내내 눈앞에 있다.

```
Model: Fable 5 | ⎇ main | Context: ▓▓░░░░░░░░ 41k/200k (20%)
Session: ▓▓▓▓░░░░░░ 39.0% | Reset: 4hr 27m | Weekly: ▓▓▓▓▓▓▓░░░ 72.0% | Weekly Reset: 2d 11hr
```

## 무엇을 하나

`install` 은 세 가지를 순서대로 한다. 각 단계는 idempotent 라 이미 된 것은
`skipped` 로 넘어간다.

1. **npm 패키지** — `npm install -g ccstatusline`. Omarchy 는 node 를 mise 로
   관리하므로 설치 후 `mise reshim` 까지 해서
   `~/.local/share/mise/shims/ccstatusline` 이 생기게 한다. 등록에는 이 shim
   경로를 쓴다 — node 버전을 갈아타도 경로가 살아남는 쪽이라서.
2. **위젯 설정** — 저장소의 `ccstatusline/settings.json` 을
   `~/.config/ccstatusline/settings.json` 으로 복사.
3. **등록** — `~/.claude/settings.json` 의 `statusLine` 키에 바이너리를 등록.
   jq 로 그 키만 병합하므로 파일의 나머지는 건드리지 않는다.

## 위젯 구성

두 줄이다. 창이 좁아 한 줄이 잘리던 것을 줄을 나눠 해결했다.

| 줄 | 위젯 | 표시 |
|---|---|---|
| 1 | `model` · `git-branch` · `context-bar` (slider) | 모델, 브랜치, context 게이지 + `사용/전체 (%)` |
| 2 | `session-usage` (slider) · `reset-timer` · `weekly-usage` (slider) · `weekly-reset-timer` | 5시간 한도 게이지, 블록 리셋까지 남은 시간, 주간 한도 게이지, 주간 리셋까지 남은 시간 |

그 외 결정들:

- `defaultSeparator: " | "` — 위젯 사이 구분선.
- `flexMode: "full"` — 기본값 `full-minus-40` 은 터미널 오른쪽 40칸을 비워 두는
  모드라(Claude Code 자체 안내문 자리), 창의 2/3 만 쓰는 것처럼 보인다.
  `full` 은 6칸만 남긴다. 아주 좁은 창에서는 그 안내문과 겹칠 수 있다.
- 게이지는 `metadata.display` 값이다: `slider`(게이지+%) 외에
  `progress`(32칸 바), `progress-short`(16칸), `slider-only`(숫자 없이)가 있다.
- 리셋 타이머들은 기본값(`time`, 남은 시간)이고, date 모드로 바꾸면 리셋
  시각으로 표시된다.

바꾸려면 저장소의 `ccstatusline/settings.json` 을 고치고 `install` 을 다시
돌린다. ccstatusline 은 갱신 때마다 설정을 다시 읽으므로 재시작 없이 반영된다.
터미널에서 `ccstatusline` 을 그냥 실행하면 대화형 설정 TUI 가 뜨는데, 거기서
저장하면 설치본이 소스와 달라진다 — 아래 참고.

## 설치본이 outdated 로 뜰 때

ccstatusline 은 설치된 설정 파일을 스스로 다시 쓴다: TUI 를 열면 파일을
정규화하고, 업데이트 공지가 임시 키를 얹는다. 아무도 고치지 않았는데 소스와
달라져 상태가 `installed / outdated` 로 읽힌다. `diff` 로 무엇이 달라졌는지
보고, 원하는 변경이면 **저장소 쪽으로** 받아들인다 — 옛 파일을 덮어써서
핑퐁하지 않는다.

## 되돌리기 (remove)

- `~/.claude/settings.json` 의 `statusLine` — ccstatusline 을 가리킬 때만
  지운다. 다른 명령이 등록돼 있으면 남의 것이므로 두고 경고만 한다.
- 설정 파일 — 소스와 같으면 백업 후 삭제(설치 전 상태는 "파일 없음").
  다르면 손대지 않는다.
- npm 패키지 — 이 status line 말고는 쓸 데가 없으므로 함께 지운다.
  `--keep-package` 를 주면 남긴다.

이미 떠 있는 Claude Code 세션은 재시작할 때까지 이전 status line 을 유지한다.

## 의존성

node/npm 과 jq. 둘 다 있어야 하고, 스크립트가 대신 설치하지는 않는다 —
Omarchy 기본 구성이면 둘 다 있다 (node 는 `mise use -g node@lts`).
