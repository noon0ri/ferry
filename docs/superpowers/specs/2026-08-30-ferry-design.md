# Ferry — 설계 문서

작성일: 2026-08-30
상태: 승인 대기

## 1. 개요

Ferry는 흩어진 Claude Code 세션을 한 목록에 모아 보여주고, 클릭 한 번으로 해당 세션을 재개시키는 macOS 메뉴바 앱이다.

"건너다 준다"는 이름 그대로, 세션을 붙들고 있는 게 아니라 세션으로 데려다주는 역할만 한다. 작업 자체는 Terminal.app에서 일어난다.

## 2. 문제 정의

현재 회사 PC에 터미널 창 10개가 열려 있다. 전부 동시에 쓰는 게 아니라 주 1회씩 재방문하는 세션들이며, 닫지 못하는 이유는 다음 두 가지다.

1. **세션이 프로젝트 폴더별로 흩어져 있다.** `claude --resume`은 현재 디렉토리 기준으로 목록을 보여주므로, 폴더를 하나씩 옮겨다니며 찾아야 한다.
2. **목록에서 어떤 세션인지 식별하기 어렵다.** UUID와 타임스탬프만 보고 고르게 된다.

창을 열어두는 것이 이 두 문제를 회피하는 유일한 방법이었다.

### 이미 해결되어 있는 부분

조사 결과 Claude Code는 모든 세션 로그에 `ai-title` 레코드를 기록하고 있다. 한국어 제목까지 자동 생성된다.

```
enigma            "Enigma 퍼즐 파이프라인 그룹4 실행"
figma             "Astryx 디자인 시스템 design.md"
huddling-lab2     "웹 기반 인터랙티브 3D 아이콘 세트 만들기"
```

또한 `claude --resume <session-id>`는 임의의 디렉토리에서 실행 가능하다.

즉 필요한 데이터와 실행 수단은 모두 존재하며, 없는 것은 **이를 한 화면에 모으는 표면**뿐이다. Ferry는 그 표면이다.

### 성공 기준

터미널 창 10개를 모두 닫고도 불편하지 않은 상태. 각 세션에 3초 안에 도달할 수 있어야 한다.

## 3. 범위

### 1차 (이번 구현)

- `~/.claude/projects/` 전체 세션 스캔
- 프로젝트(작업 폴더) 단위 그룹, 접기/펼치기
- 세션별 제목 · 마지막 활동 시각 표시
- 최근 60초 내 활동 시 활동 표시(●)
- 클릭 시 Terminal.app 새 탭에서 재개

### 2차 (실사용 후 판단)

검색(`.searchable`), 핀 고정, 전역 단축키

### 범위 밖

실행중/입력대기 상태 추론, 세션 삭제·이름 편집, 토큰·비용 표시, 앱 내장 터미널

2주 사용 후 실제로 아쉬운 항목만 2차로 승격한다.

## 4. 사용자 흐름

```
메뉴바 아이콘 클릭
  → 팝오버 열림, 프로젝트 목록 (최근 활동순)
  → 프로젝트 펼침
  → 세션 클릭
  → Terminal.app 새 탭: cd '<cwd>' && claude --resume <id>
  → 작업 종료 후 ⌘W (목록은 메뉴바에 남음)
```

핵심은 터미널 창의 성격 전환이다. 보관용에서 일회용이 된다.

## 5. 아키텍처

### 접근 방식

SwiftUI `MenuBarExtra` + 온디맨드 스캔. macOS 13+, Swift 6.

백그라운드 데몬이나 FSEvents 감시는 채택하지 않는다 (§7 성능 근거).

향후 AppKit `NSStatusItem` + `NSPopover`로 확장할 수 있도록 뷰와 로직을 분리한다. 확장 시 `MenuBarView`만 교체하고 나머지는 재사용한다.

### 모델

```swift
struct Session: Identifiable {
    let id: String          // sessionId (UUID)
    let logPath: URL        // ~/.claude/projects/<enc>/<id>.jsonl
    let cwd: String         // 실제 작업 폴더 — 그룹핑 키
    let title: String       // ai-title → 첫 프롬프트 → id 앞 8자
    let gitBranch: String?  // nil = git 아닌 폴더 (정상)
    let modifiedAt: Date    // 파일 mtime
}

struct Project: Identifiable {
    let path: String        // cwd
    var name: String        // 마지막 경로 성분
    var sessions: [Session] // 최근순
    var latestActivity: Date
}
```

### 컴포넌트

| 파일 | 책임 | 의존 |
|---|---|---|
| `SessionScanner` | jsonl 1개 → `Session?` (순수 함수) | Foundation |
| `SessionStore` | 폴더 순회 · mtime 캐시 · 그룹핑 (`@Observable`) | Scanner |
| `TerminalLauncher` | 명령 문자열 생성 + AppleScript 실행 | — |
| `MenuBarView` | `MenuBarExtra` + `DisclosureGroup` | Store, Launcher |
| `FerryApp` | 진입점 | — |

`SessionScanner`를 순수 함수로 분리하는 것이 설계의 중심이다. 파싱 로직 전체가 픽스처 파일만으로 테스트되고, 확장 시 그대로 재사용된다.

### 데이터 흐름

```
팝오버 열림
  → .task → store.refresh()
  → ~/.claude/projects/*/ 순회
  → depth 1의 *.jsonl만 수집 (subagents/ 하위 제외)
  → mtime을 캐시와 비교, 변경분만 TaskGroup으로 병렬 재파싱
  → cwd 기준 그룹핑
  → 최근 활동순 정렬
  → 렌더
```

### 데이터 소스

`~/.claude/projects/<encoded-path>/<session-id>.jsonl` — JSON Lines. 필요한 레코드는 두 종류다.

```jsonc
// 제목 (세션 내 반복 기록, 최신 값이 뒤쪽)
{"type":"ai-title","aiTitle":"...","sessionId":"..."}

// 메타 (모든 user/assistant 라인에 존재)
{"type":"user","sessionId":"...","cwd":"/Users/...","gitBranch":"main","timestamp":"..."}
```

같은 디렉토리의 `<session-id>/subagents/*.jsonl`은 서브에이전트 로그이며 **무시한다**. 현재 로컬 기준 메인 세션 23개에 서브에이전트 467개로, 이를 거르지 않으면 스캔 대상이 20배가 된다.

## 6. 핵심 결정

### 6.1 그룹핑 키는 폴더명이 아니라 로그의 `cwd` 필드

디렉토리명 `-Users-seongbin-Codes-side-scrolling-action-game`은 원래 경로로 **디코딩할 수 없다**. 하이픈이 경로 구분자인지 이름에 포함된 하이픈인지 구분할 방법이 없기 때문이다.

실제로 `~/Codes/side scrolling action game`(공백)처럼 공백을 쓰는 폴더와 하이픈을 쓰는 폴더가 섞여 있다. 폴더명 파싱은 반드시 깨진다.

로그 내부 `cwd` 필드가 정답을 그대로 갖고 있으므로 이를 사용한다.

### 6.2 파일 꼬리 256KB만 읽는다

`aiTitle`은 세션 진행 중 반복 기록되므로(단일 세션에서 112회 관측) 최신 값이 항상 파일 뒤쪽에 있다. 꼬리에서 찾지 못한 경우에만 앞에서부터 읽는 폴백을 둔다.

가장 큰 세션 파일이 20.2MB이므로, 이 결정이 스캔 비용을 두 자릿수 배로 줄인다.

### 6.3 실행을 Terminal.app에 위임한다

앱이 직접 프로세스를 띄우지 않고 AppleScript로 Terminal.app에 명령을 넘긴다.

부수 효과로 `PATH` 문제를 회피한다. GUI 앱은 로그인 셸의 `PATH`를 물려받지 못해 `claude` 실행 파일을 찾지 못하지만, Terminal.app이 로그인 셸을 띄우므로 이 문제가 발생하지 않는다. 앱 내장 터미널 방식이었다면 정면으로 부딪혔을 지점이다.

## 7. 성능

실측 (2026-08-30, 로컬):

| 항목 | 값 |
|---|---|
| 스캔 대상 메인 세션 | 23개 |
| 가장 큰 세션 파일 | 20.2 MB |
| 꼬리 256KB 읽기 | 17 ms |
| 23개 전체 스캔 (셸) | 356 ms |

셸 기준 356ms이며 Swift 네이티브 + 병렬 처리로 더 내려간다. 팝오버 열림 시점 스캔으로 충분하므로 백그라운드 인덱싱이 필요 없다.

**예산:** 세션 300개 기준 팝오버 표시까지 200ms 이내. 초과 시 mtime 캐시 적중률을 먼저 점검한다.

## 8. 오류 처리

| 상황 | 처리 |
|---|---|
| Terminal 자동화 권한 거부 | 안내 표시 + 명령어 클립보드 복사로 폴백 |
| 경로에 공백 포함 | `cd '<cwd>'` 단일 인용 + AppleScript 문자열 이스케이프 |
| `cwd` 폴더 삭제됨 | 항목 흐리게 표시, 클릭 시 알림 |
| jsonl 손상 라인 | 해당 라인만 skip, 파일 전체를 버리지 않음 |
| 빈 파일 | `nil` 반환, 목록에서 제외 |
| `aiTitle` 없음 | 첫 user 프롬프트 → id 앞 8자 순으로 폴백 |
| `~/.claude/projects` 없음 | 빈 상태 + 안내 문구 |

`Info.plist`에 `NSAppleEventsUsageDescription`이 필요하다. 없으면 권한 다이얼로그가 뜨지 않고 조용히 실패한다.

공백 경로는 가정이 아니라 현재 상태다. `claude work`, `interaction study`, `Fidget Toy`, `side scrolling action game` 네 곳이 해당한다.

## 9. 테스트

Swift Testing (`@Test`). TDD로 진행한다.

`SessionScanner` — 픽스처 jsonl 기반:

```
정상 세션           → title / cwd / gitBranch 추출
aiTitle 없음        → 첫 user 프롬프트로 폴백
제목·프롬프트 없음   → id 앞 8자
손상 JSON 라인 섞임  → skip 후 나머지 파싱 성공
gitBranch null      → nil (git 아닌 폴더, 정상 케이스)
빈 파일             → nil
꼬리에 제목 없음     → 전체 읽기 폴백 발동
```

`TerminalLauncher` — 명령 문자열 생성만 검증(실행과 분리):

```
공백 포함 경로       → 올바른 인용
따옴표 포함 경로     → 이스케이프
```

`SessionStore`:

```
mtime 미변경 파일    → 재파싱하지 않음
subagents/ 하위      → 스캔 대상에서 제외
```

## 10. 확장 경로

전역 단축키가 필요해지면 AppKit `NSStatusItem` + `NSPopover`로 옮긴다. `MenuBarView`만 교체하고 `SessionScanner` · `SessionStore` · `TerminalLauncher`는 그대로 재사용한다.
