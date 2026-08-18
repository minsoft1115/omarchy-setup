# install.sh

> [omarchy-setup](../README.md) 의 진입점. 개별 스크립트는 `scripts/` 에 있다.

clone 부터 선택 설치까지 한 번에 한다. 개별 스크립트를 직접 돌려도 되고, 이건 그것들을
묶어 주는 얇은 층이다.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
```

내용을 먼저 보고 싶으면 두 단계로:

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh -o install.sh
less install.sh
bash install.sh
```

---

## 흐름

```
curl | bash
 └─ clone → ~/.local/share/minsoft1115/omarchy-setup   (있으면 git pull --ff-only)
     └─ 터미널을 다시 붙여 clone 안의 자신을 exec
         └─ gum 체크리스트
             └─ 고른 것들을 고정 순서로 실행 → 요약
```

**터미널을 다시 붙이는 게 핵심이다.** 파이프로 들어온 스크립트는 stdin 이 키보드가 아니라서,
그대로 두면 체크리스트가 EOF 를 읽고 아무것도 선택되지 않는다. 그래서 clone 이 끝나면
`exec bash "$CLONE/install.sh" ... < /dev/tty` 로 넘긴다.

---

## 체크리스트

```
What should be set up? (space toggles, enter confirms)
> ✓ [installed]      Korean input — right Alt switches 한/영, Omarchy menu opens in Latin
  ✓ [not installed]  Bash config — Alt-R history picker, fzf search and kill, delta diffs
  ✓ [installed]      Workspaces bar — hold Super to see which apps are where before switching
```

- **전부 선택된 상태**로 시작한다 (스페이스로 토글)
- 항목마다 **현재 설치 상태**가 붙는다. 각 스크립트의 `status` 출력을 파싱하지 않고
  파일 존재 여부로 판단한다 — 메뉴에 한 단어 띄우자고 남의 문구에 묶일 이유가 없다
- 고른 순서와 무관하게 **실행 순서는 고정**이다: 한글 → bash → 위젯.
  위젯이 `omarchy restart shell` 로 바를 재시작하므로 마지막이다
- `gum` 이 없으면 항목별 `[Y/n]` 로 묻는다

### 미리 답해 두는 질문

`bash` 항목을 고르면 [선택 파일 `pkg-guards.sh`](bash-config.md#선택-파일) 설치 여부를
**여기서 먼저 묻는다.** 그래야 하위 스크립트가 설치 도중에 멈추지 않는다.
`--guards` / `--no-guards` 로 아예 물어보지 않게 할 수도 있다.

---

## 옵션

| 옵션 | 하는 일 |
|---|---|
| `--all` | 묻지 않고 전부 |
| `--only korean,bash` | 이름으로 지정 |
| `--guards` / `--no-guards` | pkg-guards 답을 미리 정함 |
| `--list` | 설치 가능한 것과 현재 상태만 출력 |
| `--dry-run` | 무엇이 돌지만 보여 주고 실행 안 함 |
| `--remove` | 되돌리기 (아래) |
| `--purge` | `--remove` 와 함께 쓰면 마지막에 clone 까지 삭제 |
| `--dir <경로>` | clone 위치 변경 |

```bash
./install.sh --list
./install.sh --only widget
./install.sh --all --no-guards
```

---

## 되돌리기

```bash
./install.sh --remove
```

- 같은 체크리스트가 **전부 해제된 상태**로 뜬다. 설치는 잘못 골라도 다시 돌리면 되지만
  제거는 아니다
- **설치의 역순**으로 진행한다 (위젯 → bash → 한글)
- 끝나면 `~/.config/minsoft1115/` 가 비었을 때 정리한다
- 물어볼 터미널이 없으면 **거부한다.** 설치는 전체 선택으로 진행해도 되지만, 제거를 말없이
  전부 고를 수는 없다

무엇을 지우는지는 각 스크립트가 정한다. 특히 한글 쪽은 **fcitx5 설정을 일부러 남긴다** —
[docs/setup-korean.md](setup-korean.md) 참고.

`--purge` 는 clone 까지 지운다. 실행 중인 스크립트 파일을 지우면 bash 가 나머지를 못 읽으므로,
`exec` 로 프로세스를 갈아탄 뒤 지운다.

---

## clone 을 남기는 이유

세 스크립트 모두 **저장소에서 설치한다** — alias·function 소스, 위젯 QML 소스, Hyprland Lua
조각이 전부 저장소에 있고, 고친 뒤 다시 돌리는 게 반영 방법이다. 첫 실행 후 지우면 갱신
경로가 사라진다. 그래서 임시 폴더가 아니라 고정 위치에 두고 남긴다.

```
~/.local/share/minsoft1115/omarchy-setup
```

다시 실행하면 `git pull --ff-only` 부터 한다. fast-forward 가 안 되면 경고만 하고 있는 그대로
쓴다 — 로컬에서 고쳐 둔 것을 덮지 않기 위해서다.

---

## 실패 처리

한 단계가 실패해도 **나머지는 계속**하고, 끝에 요약이 나온다.

```
== Summary ==
  korean ok
  bash FAILED
  widget ok
```

전형적인 실패는 패키지 설치 단계에서 sudo 비밀번호를 못 받는 경우다. 그때도 설정 파일 설치는
진행되므로, 패키지만 따로 깔고 다시 돌리면 나머지는 전부 `skipped` 로 지나간다.
