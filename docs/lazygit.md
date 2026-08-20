# install-lazygit.sh

> [omarchy-setup](../README.ko.md) 의 스크립트 중 하나.

저장소의 lazygit 설정을 `~/.config/lazygit/config.yml` 로 복사한다. diff 가 lazygit 안에서
`delta` 로 렌더된다.

**모든 동작이 idempotent** — 여러 번 실행해도 안전하며, 이미 된 항목은 `skipped` 로 표시된다.

## 무엇이 바뀌나

| 파일 | 내용 |
|---|---|
| `lazygit/config.yml` | `git.diffRenderers` — diff 를 `delta --paging=never` 로 렌더 (`colorArg: always`) |

## 이 스크립트가 다른 것들과 다른 점

**통파일 복사다.** 다른 스크립트들은 우리 네임스페이스(`~/.config/minsoft1115/`)에 조각을
두고 마커 한 줄만 남의 파일에 넣지만, lazygit 은 설정 경로가 하나뿐이고 include 가 없어서
파일을 통째로 복사한다. 그래도 안전한 이유는 **Omarchy 가 그 자리를 빈 파일로 깔아 두기
때문**이다 — 병합할 남의 내용이 없고, 백업만 있으면 된다.

`LG_CONFIG_FILE` 로 기본 설정과 우리 것을 병합하는 방식도 검토했다가 기각했다. bashrc 에서
export 한 환경변수는 대화형 셸에서 띄운 lazygit 에만 닿고, 키바인딩·런처로 띄운 것에는 안
닿는다.

---

## 요구 사항

- 의존 패키지는 `install` 이 **`omarchy pkg` 로 먼저 깐다** — `lazygit` 자신과,
  diff 렌더러인 `git-delta`. 이미 있으면 건너뛴다
- `omarchy` 가 없으면 경고만 하고 파일 설치는 계속한다

---

## 사용법

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓴다.

```bash
./scripts/install-lazygit.sh status     # 지금 상태 (기본 동작)
./scripts/install-lazygit.sh install    # 패키지 확인 + 설정 복사
./scripts/install-lazygit.sh remove     # 되돌리기 (아래)
./scripts/install-lazygit.sh diff       # 소스 vs 설치본
```

| 옵션 | 하는 일 |
|---|---|
| `--skip-packages` | 패키지는 건드리지 않고 파일만 설치 |

### status 출력 예

```
source (edit here) : /path/to/repo/lazygit/config.yml (present)
installed copy     : ~/.config/lazygit/config.yml (present)
in sync with source: yes
dependencies       : lazygit(ok) git-delta(ok)
```

---

## 알아둘 것

**lazygit 이 이 파일을 스스로 고쳐 쓴다.** 업데이트로 키 이름이 바뀌면 lazygit 이 첫 실행 때
설치본을 제자리에서 마이그레이션한다 — 0.64 에서 실측: `git.pagers` → `git.diffRenderers`,
`pager:` → `command:`. 그러면 아무도 고치지 않았는데 설치본이 소스와 달라져 체크리스트가
`installed / outdated` 로 바뀐다. **그때는 재설치가 아니라 저장소 쪽을 갱신하는 게 답이다** —
재설치하면 옛 키를 도로 복사하고, 다음 실행이 또 마이그레이션하는 핑퐁이 된다. `diff` 가
rename 을 보여 주면 그 내용을 `lazygit/config.yml` 에 받아들이면 된다.

**`remove` 는 파일을 지우지 않는다.** 그 자리는 Omarchy 의 것이라(빈 파일로 깔린다), 설치본이
소스와 같으면 **백업 후 비운다** — 그게 설치 전 상태다. 소스와 다르면(직접 고쳤거나 lazygit 이
마이그레이션했으면) 판단하지 않고 **그대로 두고 백업 위치만 알려 준다** — 한글 스텝이 fcitx
설정을 다루는 것과 같은 규칙이다. 가장 최근 백업을 복원하지 않는 이유: 두 번째 설치 뒤의
최신 백업은 원본이 아니라 **우리 이전 버전**이다.

**설치본을 직접 고치면 `outdated` 로 뜬다.** 반영 경로는 저장소 파일을 고치고 `install` 을
다시 돌리는 것이다 — 이 저장소의 다른 스크립트들과 같다.

기존 파일은 수정 전에 `*.bak.<타임스탬프>` 로 백업된다.

```bash
ls ~/.config/lazygit/*.bak.*
```
