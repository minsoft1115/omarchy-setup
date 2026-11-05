# 이전 한글 설정만 제거

[uninstall-korean.sh](../scripts/uninstall-korean.sh)는 보관한 `setup-korean.sh`의
`run_remove`와 관련 함수를 바탕으로 만든 별도 제거 스크립트다.
`install.sh`에는 연결하지 않는다. 현재 사용 중인 fcitx5 한글 입력은 유지하고
이 저장소가 추가한 설정을 정리할 때 직접 실행한다.

저장소 루트에서:

```bash
./scripts/uninstall-korean.sh --dry-run
./scripts/uninstall-korean.sh
```

`--dry-run`은 대상만 출력하며 백업·삭제·설정 저장·IPC 호출을 하지 않는다.
`--no-reload`는 파일만 정리하고 Hyprland reload와 셸 플러그인 재검색을 생략한다.
스크립트는 보관 폴더나 위젯 원본을 읽지 않으므로 파일 하나만으로 실행할 수 있다.
필요 도구는 Bash, Python 3, 기본 파일 명령과 tar다. sudo는 사용하지 않는다.

| 대상 | 처리 |
|---|---|
| `hyprland.lua`의 `setup-korean:begin/end` 블록 | 그 블록과 바로 앞 빈 줄 하나만 제거. 끝 마커가 없으면 중단 |
| `minsoft1115/hypr/korean-{input,bindings}.lua` | 백업 후 제거 |
| `~/.local/bin/omarchy-latin-launch` | 이전 설치기 주석이 있고 `bindings.lua`가 참조하지 않을 때 제거 |
| `environment.d/fcitx.conf` | 이전 설치 내용과 같고 Omarchy 기본 IM 환경변수 파일이 있을 때 제거 |
| `autostart/org.fcitx.Fcitx5.desktop` | Omarchy 기본 파일이 있으면 유지. 없으면 이전 설치 내용과 같은 경우만 제거 |
| `omarchy/shell.json` | `minsoft1115.fcitx`의 바 배치·플러그인 등록만 제거 |
| `omarchy/plugins/minsoft1115.fcitx/` | tar.gz로 백업 후 제거. 심볼릭 링크는 보존 |
| fcitx5 `config/profile`, 패키지·서비스 | 유지. 입력기 재시작과 백업 복원도 하지 않음 |
| 공식 `keyboard-layouts`·언어·글꼴 설정 | 유지 |

기본 설정 경로는 `${XDG_CONFIG_HOME:-$HOME/.config}`다. 다른 설치 경로는
`--config-dir DIR`, 실행 파일 경로는 `--bin-dir DIR`로 지정한다.
이전 설치에서 사용자 지정 래퍼 이름이나 경로를 사용했다면 해당 파일은 별도 확인이 필요하다.

수정·삭제 전 백업은 원래 파일 옆의 `*.bak.<timestamp>`에 남는다.
위젯 백업은 플러그인 폴더 옆의 `minsoft1115.fcitx.bak.<timestamp>.tar.gz`다.
수정한 공유 파일과 마커 없이 직접 작성된 오래된 키 설정은 자동 추정해 지우지 않고
경고와 함께 남긴다. 다른 도구의 Lua 조각과 공식 입력 상태 위젯은 유지한다.

Hyprland 블록을 제거하면 기본 실행은 `hyprctl reload`와 `hyprctl configerrors`로
검증한다. 세션 밖에서 정리했다면 재로그인하거나 세션에서 두 명령을 실행한다.
사용자 IM 환경변수 파일을 제거한 효과는 재로그인 후 반영된다.

현재 한/영키가 이 저장소의 오른쪽 Alt 매핑에 의존한다면 제거 후 동작이 달라질 수 있다.
공식 **Setup > Typing > Keyboard Layouts > Korean** 설정은 이 스크립트가 건드리지 않는다.
