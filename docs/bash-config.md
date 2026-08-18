# install-bash-config.sh

> [omarchy-setup](../README.md) 의 스크립트 중 하나.

저장소의 alias·function 파일을 `~/.config/minsoft1115/bash/` 로 복사하고, `~/.bashrc` 가
그것들을 읽게 만든다.

**모든 동작이 idempotent** — 여러 번 실행해도 안전하며, 이미 된 항목은 `skipped` 로 표시된다.

## 무엇이 들어오나

| 파일 | 내용 |
|---|---|
| `bash/aliases.sh` | `cat` → `bat -p` (하이라이팅), `grep` → `rg` |
| `bash/fhistory.sh` | `fhistory` — **Alt-R** 로 히스토리를 fzf 로 골라 **실행하지 않고 프롬프트에 채워 넣는다**. 목록은 `history` 순서 그대로 두고 커서만 최적 매치로 이동한다 (`--raw` + `best`). Ctrl-Y 로 명령 복사. Ctrl-R 은 fzf 기본 위젯에 그대로 둔다 |
| `bash/fkill.sh` | `fkill` — 내 프로세스를 fzf 로 골라 종료. `fkill -9` 처럼 시그널 전달 가능 |
| `bash/fsearch.sh` | `fsearch` — 파일 내용 검색(rg)을 fzf 로 훑어보기. `fsearch TODO` / `fsearch md TODO`, Enter 로 `$EDITOR`, Ctrl-Y 로 경로 복사 |
| `bash/gdiff.sh` | `gdiff` — `git diff` 를 `delta` 로 넘긴다. 인자는 그대로 전달 |
| `bash/pkg-guards.sh` | **선택** — `pacman`·`yay` 를 실행 대신 안내로 막고, `sudo` 뒤 공백으로 `sudo pacman` 도 걸리게 한다 |

---

## 요구 사항

- `bash`
- 의존 도구는 `install` 이 **`omarchy pkg` 로 먼저 깐다** — `git-delta`(명령은 `delta`),
  `bat`, `ripgrep`(명령은 `rg`), `fzf`. 이미 있으면 건너뛴다
- `omarchy` 가 없으면 경고만 하고 셸 파일 설치는 계속한다. **`pacman` 을 직접 부르지 않는다**
- 선택 파일 질문에는 `gum` 을 쓴다. 없으면 `[y/N]` 로 묻는다

`Ctrl-Y` 로 클립보드에 넣는 동작은 `wl-clipboard` 의 `wl-copy` 를 쓴다.

---

## 사용법

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓴다.

```bash
./scripts/install-bash-config.sh status     # 지금 상태 (기본 동작)
./scripts/install-bash-config.sh install    # 복사 + ~/.bashrc 에서 로드
./scripts/install-bash-config.sh remove     # 로더 제거 + 설치본 삭제
./scripts/install-bash-config.sh diff       # 소스 vs 설치본
```

| 옵션 | 하는 일 |
|---|---|
| `--skip-packages` | 패키지는 건드리지 않고 파일만 설치 |
| `--with-optional` | 선택 파일을 묻지 않고 설치 |
| `--no-optional` | 묻지 않고 제외 (이미 깔린 것도 회수) |

### status 출력 예

```
source (edit here) : /path/to/repo/bash (present)
installed copy     : ~/.config/minsoft1115/bash (present)
in sync with source: yes
loaded by .bashrc  : yes
dependencies       : git-delta(ok) bat(ok) ripgrep(ok) fzf(ok)
optional files     : pkg-guards.sh(installed)
```

---

## 지금 쓰는 셸에 반영하기

프로세스는 **자기를 실행한 셸을 바꿀 수 없다.** 그래서 실행만으로는 지금 열려 있는 터미널에
alias 가 생기지 않는다. 새로 여는 터미널은 그냥 적용된다.

지금 이 셸에도 바로 넣으려면 실행 대신 **source** 한다.

```bash
source ./scripts/install-bash-config.sh install
```

source 로 부르면 실제 작업은 자식 프로세스에 넘기고(변수·함수가 호출자에 새지 않는다)
마지막 `source ~/.bashrc` 만 호출자 셸에서 한다. 그냥 실행하면 그 사실을 알려 준다.

---

## 로더

`~/.bashrc` 끝에 마커로 감싼 블록이 들어간다. 파일마다 source 줄을 적는 대신 **폴더를 훑는
루프**라, 나중에 `bash/` 에 파일을 추가해도 `install` 만 다시 돌리면 되고 `~/.bashrc` 는 다시
안 고친다.

```bash
# minsoft1115-bash:begin
for __minsoft1115_rc in "$HOME/.config/minsoft1115/bash"/*.sh; do
  [ -r "$__minsoft1115_rc" ] && . "$__minsoft1115_rc"
done
unset __minsoft1115_rc
# minsoft1115-bash:end
```

Omarchy 가 자기 bash rc 를 읽은 **뒤에** 붙으므로, 같은 이름이면 이쪽이 이긴다.

### fzf 에 맡긴 것

`fhistory` 는 "목록 순서는 그대로, 커서만 최적 매치로" 를 fzf 기본 기능으로 한다.

```bash
fzf --tac --raw --no-sort --bind 'result:best'
```

`--raw` 는 매치되지 않는 줄도 흐리게 **화면에 남기고**, `best` 액션이 그중 최고 점수 항목으로
커서를 옮긴다. **둘은 같이 써야 의미가 있다** — `--raw` 없이는 fzf 가 비매치 줄을 걸러 내므로
`best` 가 `first` 와 같아진다 (man 에도 그렇게 적혀 있다). 실측으로도 `--raw` 없이는 첫 줄로,
있으면 실제 매치 줄로 커서가 갔다.

### 로드 순서가 규칙을 하나 만든다

파일은 **이름순**으로 로드되고, bash 는 **함수 본문을 읽는 시점에 alias 를 펼친다.**
그래서 `aliases.sh` 가 먼저 로드되면, 뒤에 오는 함수 파일 안의 명령까지 alias 로 치환된다.

`fkill.sh` 의 `ps -ef | grep "$USER"` 는 실제로 `rg "$USER"` 로 박혀 들어간다. 의도한 게
아니라면 함수 안에서 `command grep` 을 쓰면 된다. (`find -exec grep` 처럼 명령 위치가 아닌
자리는 영향받지 않는다.)

순서를 강제하고 싶으면 `10-`, `20-` 같은 숫자 접두사를 붙이면 된다.

---

## 선택 파일

`pkg-guards.sh` 는 Omarchy 가 이미 비슷한 alias 를 갖고 있어서, `install` 이 **설치할지
물어본다.**

```
┌ Install pkg-guards.sh?
│ Guards for the Arch package managers, and the sudo alias they need.
│   Yes    No
```

- 질문 문구는 **그 파일의 첫 주석 줄**을 그대로 쓴다 — 설명이 두 군데로 갈라지지 않는다
- **이미 설치돼 있으면 다시 묻지 않는다.** 매번 뜨는 프롬프트는 안 읽고 넘기게 된다
- 질문은 stdin 이 아니라 **`/dev/tty` 에** 한다. 출력을 파이프로 넘겨도 질문은 사람 앞에 뜨고,
  제어 터미널이 아예 없으면(cron·훅) 건너뛴다
- 선택 파일을 뺀 상태도 `in sync: yes` 로 본다 — 그건 차이가 아니라 선택이다

---

## 안전성

- 설치 전에 `bash -n` 으로 **모든 소스 파일을 문법 검사**한다. `~/.bashrc` 가 읽는 파일이
  깨지면 새로 여는 터미널이 전부 망가지고, 보통 모든 터미널이 죽은 뒤에야 알아차린다
- 설치 후 `bash --rcfile <파일> -i` 로 대화형 셸을 한 번 띄워 정상 로드되는지 확인한다
  (긴 옵션이 먼저 와야 한다 — `bash -i --rcfile` 은 거부된다)
- `~/.bashrc` 는 고치기 전에 `*.bak.<타임스탬프>` 로 백업
- 저장소에서 지운 파일은 다음 `install` 때 설치본에서도 정리된다

`install` → `remove` 왕복 후 `~/.bashrc` 가 **원본과 바이트 단위로 동일**한 것을 확인했다.

---

## 알아둘 것

`remove` 는 로더와 설치본을 지우지만, **이미 열려 있는 셸은 로드해 둔 정의를 그대로 갖고
있다.** `source ~/.bashrc` 로도 안 사라진다 — 이미 정의된 함수는 남는다. 그 터미널만 새로
열면 된다.

`~/.config/minsoft1115/` 상위 폴더는 남긴다. 다른 것도 같은 네임스페이스를 쓴다
([Hyprland 조각](setup-korean.md)이 그렇다).
