# install-lsp.sh

> [omarchy-setup](../README.ko.md) 의 스크립트 중 하나.

언어 서버 아홉 개를 깔고, 이어서 **Grok 과 Claude 를 실제로 쓸 수 있게** 세팅한다.
갓 깐 Omarchy 4.0 이상에서 `install.sh` 체크리스트의 `lsp` 한 줄이다.

Grok 은 `~/.grok/lsp.json` 과 `lsp_tools` 로 서버를 찾고, Claude Code 는
공식 LSP 플러그인이 같은 바이너리를 띄운다. 둘 다 `~/.local/bin` 의
Omarchy 래퍼로 PATH 와 Super 키에서 실행된다. 기본 에이전트
(`omarchy default agent`) 는 바꾸지 않는다 — 둘 다 실행 가능한 상태로 둔다.

**모든 동작이 idempotent** — 여러 번 돌려도 안전하며, 이미 된 항목은
`skipped` 로 표시된다.

## 무엇이 들어오나

세 채널이다. Arch extra 에 없는 것은 mise 나 `dotnet tool` 로 간다.

| 채널 | 서버 / 도구 |
|---|---|
| `omarchy pkg add` | `clang` (clangd 만. 컴파일러라 remove 때도 안 지움) |
| mise / rustup | **rust-analyzer** — mise rust 위의 rustup 컴포넌트. Arch `extra/rust-analyzer` 는 `extra/rust` 전체를 끌어와서 쓰지 않는다 |
| mise | basedpyright, bash-language-server, typescript, typescript-language-server, gopls (`v0.23.0`), lua-language-server, marksman, 런타임(node·go·dotnet) |
| `omarchy-mise-install` | **claude**, **grok** — `~/.local/bin` 래퍼 (Omarchy 가 에이전트를 켜는 방식) + mise 패키지 |
| `dotnet tool install -g` | `roslyn-language-server` (Grok), `csharp-ls` (Claude 의 csharp-lsp 플러그인) |

Grok·Claude 를 쓸 수 있게 (래퍼가 없을 때만 만들고, 이미 Omarchy 가 깐 것은 그대로):

- `omarchy-mise-install claude`
- `omarchy-mise-install npm:@xai-official/grok grok`
- 패키지는 그 자리에서 `mise use -g` 로 받아서, 래퍼를 처음 실행할 때 내려받는 일이 없게 한다

Grok 쪽 LSP 설정:

- `lsp/lsp.json` → `~/.grok/lsp.json` (`__HOME__` 만 그 머신의 `$HOME` 으로 치환)
- `~/.grok/config.toml` 의 `lsp_tools = true` (다른 키는 유지)

Claude 쪽 설정:

- 공식 플러그인 `clangd-lsp`, `rust-analyzer-lsp`, `pyright-lsp`, `gopls-lsp`,
  `lua-lsp`, `typescript-lsp`, `csharp-lsp`
- `pyright-lsp` 는 `pyright-langserver` 를 부르는데, basedpyright 가 그 명령을
  제공한다
- bash 와 marksman 은 공식 플러그인이 없다. 바이너리는 깔리므로 Grok 은
  쓰고, Claude 는 위 일곱 개만 플러그인으로 연결된다

C# 이 둘인 이유: Grok 의 `lsp.json` 은 `roslyn-language-server` 를 쓰고,
Claude 공식 플러그인은 `csharp-ls` 를 쓴다. 각각 그 쪽에서 기대하는 명령을
깐다.

## 요구 사항

- **Omarchy 4.0 이상** — mise 와 `omarchy pkg add` 가 기본이다. 버전이 더
  낮으면 멈춘다
- `python3`, `jq` — Omarchy 기본. json 치환과 Claude 플러그인 목록 확인
- `mise` — 없으면 그 채널만 건너뛰고 나머지는 계속한다
- `dotnet` — roslyn / csharp-ls. mise 가 깐 뒤 `mise exec` 로도 부른다

`omarchy` 가 없으면 패키지 단계는 경고만 하고 파일·mise 설치는 계속한다.

## 사용법

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓴다.

```bash
./scripts/install-lsp.sh status     # 지금 상태 (기본 동작)
./scripts/install-lsp.sh install    # 바이너리 + Grok/Claude 사용 가능 세팅
./scripts/install-lsp.sh remove     # 이 스텝이 넣은 것만 회수
./scripts/install-lsp.sh diff       # 소스 vs 설치본 lsp.json
```

| 옵션 | 하는 일 |
|---|---|
| `--skip-packages` | `omarchy pkg add` 를 건너뛰고 나머지 만 |

### status 출력 예

```
source (edit here) : /path/to/repo/lsp/lsp.json (present)
Grok lsp.json      : ~/.grok/lsp.json (present)
in sync with source: yes
Grok lsp_tools     : true
packages           : clang(ok)
binaries           : clangd(ok) rust-analyzer(ok) ... csharp-ls(ok) grok(ok) claude(ok)
AI wrappers        : claude(ok) grok(ok)
Claude plugins     : clangd-lsp(ok) ...
```

## 되돌리기 (remove)

이 스텝이 **이번에 새로 넣은 것만** 회수한다. 장부는
`~/.local/state/minsoft1115/lsp/` 에 있다.

| 되돌림 | 그대로 둠 |
|---|---|
| 소스가 아직 같은 `~/.grok/lsp.json` | 손댄 `lsp.json` |
| 이 스텝이 `true` 로 켠 `lsp_tools` | 원래 `true` 였던 값 |
| 장부에 있는 mise 키 | PATH 에 이미 있어서 mise 에 안 넣은 툴, node/go/dotnet 이 원래 있던 경우 |
| 옛 장부의 pacman `rust-analyzer` (그리고 따라온 rust/rust-src/lld) | **clang**, mise/rustup 의 rust-analyzer |
| 장부에 있는 roslyn / csharp-ls | 원래 깔려 있던 dotnet tool |
| 장부에 있는 `~/.local/bin` 심볼릭 링크 | 원래 있던 링크, 또는 가리키는 곳이 다른 링크 |
| 장부에 있는 Claude 플러그인 | 마켓플레이스 등록 |
| 장부에 있는 `~/.local/bin/{claude,grok}` | Omarchy 가 원래 깔아 둔 래퍼 |

clang 은 장부에 안 적혀 절대 안 지운다. node·go·rust 는 **PATH 에 원래 있어서
mise 에 안 넣은 경우**만 남는다. rust 가 없어서 rust-analyzer 용으로 이 스텝이
깐 툴체인은 장부에 있고 remove 때 `mise unuse` 된다.

이미 떠 있는 Grok·Claude 세션은 재시작할 때까지 이전 LSP 목록을 유지한다.

## 설치본이 outdated 로 뜰 때

`install.sh` 의 판정은 체크리스트용이고, 이 스크립트의 `status` 와는 별개다.

| | 보는 것 | 아니면 |
|---|---|---|
| 설치 여부 | `~/.grok/lsp.json` 과 `~/.local/bin/{grok,claude}` 래퍼 | PATH 에 `grok` 이 있는지가 아니다. 래퍼가 없으면 `not installed` |
| 최신 여부 | json 이 소스(`__HOME__` 만 펼친 것)와 같은지, `lsp_tools = true` 인지 | json 을 손댔거나 플래그가 꺼져 있으면 `installed / outdated` |

언어 서버 바이너리(`csharp-ls` 포함)와 Claude 플러그인은 이 판정에 넣지 않는다.
빠진 것은 이 스크립트의 `status` 가 보여 준다 — 다시 `install` 하면 없는 것만
채운다. json 이 소스와 다르면 백업한 뒤 덮어쓴다.

## 왜 mise 전부가 아닌가

`clangd` 는 단독 패키지가 아니라 `clang` 안에 있다. `roslyn-language-server`
는 Arch 에 없다. rust-analyzer 는 extra 에 있지만 `extra/rust` 컴파일러를
의존성으로 끌어와서, 이미 mise/rustup 으로 rust 를 쓰는 머신에 툴체인이
두 벌이 된다. 그래서 rust-analyzer 는 rustup 컴포넌트로 깐다.
typescript-language-server 의 extra 패키지는 5.1.3 이라, 지금 쓰는 6.x 를
유지하려고 mise 에 둔다.

이전에 이 스텝이 pacman `rust-analyzer` 를 깔았던 머신에서는 `install` 을
다시 돌리면 그 패키지와 따라온 `rust` / `rust-src` / `lld` (다른 패키지가
안 쓰는 것만) 를 지우고 mise 쪽으로 옮긴다.
