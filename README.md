# Ferry

흩어진 Claude Code 세션을 한 목록에 모아 보여주고, 클릭 한 번으로 Terminal.app에서 재개시키는 macOS 메뉴바 앱.

## 요구사항

macOS 14 이상

## 빌드

    ./Scripts/bundle.sh
    open build/Ferry.app

`/Applications`로 옮겨 쓰려면 `build/Ferry.app`을 복사한다.

## 처음 실행할 때

세션을 처음 클릭하면 Terminal 제어 권한을 묻는다. 허용해야 재개가 동작한다.
거부하면 재개 명령이 클립보드에 복사되므로 터미널에 직접 붙여넣으면 된다.

권한은 시스템 설정 → 개인정보 보호 및 보안 → 자동화 에서 바꿀 수 있다.

## 동작 방식

`~/.claude/projects/` 아래 세션 로그를 **읽기만** 한다. 어떤 파일도 쓰지 않는다.

각 로그에서 `ai-title`(Claude Code가 자동 생성하는 세션 제목), `cwd`, `gitBranch`를
꺼내 작업 폴더별로 묶는다. 클릭하면 `cd <폴더> && claude --resume <세션id>`를
Terminal.app 새 탭에 넘긴다.

## 개발

    swift test     # 32개 테스트
    swift build
    swift run FerryApp

설계 문서: `docs/superpowers/specs/2026-08-30-ferry-design.md`
