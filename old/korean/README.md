# 이전 한글 입력 설정

Omarchy 4.5rc3의 공식 한글 입력·키보드 배열·상태 표시 기능으로 대체한 구현이다.
공식 기능에서 한/영 전환까지 정상 동작하는 것을 확인해 설치 목록에서 제외했다.
현재 설정 방법은 [프로젝트 README](../../README.ko.md#한글-입력)를 참고한다.

이 폴더는 이전 코드와 동작을 참고하기 위한 보관본이며, 현재 Omarchy용 설치 경로로
권장하지 않는다. 특히 이전 스크립트는 4.5rc3의 `Super+Space` 메뉴 바인딩
(`{ menu = "root" }`)을 읽지 못하므로 영문 우선 실행을 그대로 적용할 수 없다.

```text
scripts/setup-korean.sh       이전 설치·제거 스크립트
hypr/korean-input.lua         오른쪽 Alt 매핑·입력기 종료 시 키 반복 방지
hypr/korean-bindings.lua.in   메뉴를 영문 입력으로 여는 바인딩 템플릿
minsoft1115.fcitx/            태극/A 입력 상태 위젯과 SVG
docs/setup-korean.md          이전 설치 문서
```

스크립트가 상대 위치에서 Lua 조각과 위젯을 찾을 수 있도록 기존 디렉터리 구조를
유지했다. [이전 문서](docs/setup-korean.md)의 상대 경로와 명령 예시는 이 폴더를 기준으로 한다.

루트 `install.sh`의 체크리스트·상태 판정·`--all`·`--remove`에는 포함되지 않는다.
보관 과정에서 현재 시스템의 fcitx5, Hyprland, 바 위젯 설정은 변경하거나 제거하지 않았다.
이전에 설치한 설정만 정리하려면 루트의
[별도 제거 스크립트](../../docs/uninstall-korean.md)를 사용한다.
보관된 `remove` 로직을 바탕으로 만들었으며 현재 fcitx5 프로필·전환키·패키지는 유지한다.

공식 동작 비교 근거:

- [4.5rc3 입력 설정 문서](https://github.com/omacom/omarchy/blob/v4.5.0-rc3/docs/input-methods.md)
- [입력기와 키보드 설정 통합 변경](https://github.com/omacom/omarchy/pull/14433)
