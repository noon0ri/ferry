import Testing
import Foundation
@testable import FerryCore

@Test func 명령은_cd와_resume을_잇는다() {
    let cmd = TerminalLauncher.command(cwd: "/Users/me/Codes/alpha", sessionId: "abc123")
    #expect(cmd == "cd '/Users/me/Codes/alpha' && claude --resume abc123")
}

@Test func 공백_경로를_인용한다() {
    let cmd = TerminalLauncher.command(cwd: "/Users/me/Codes/my project", sessionId: "x")
    #expect(cmd == "cd '/Users/me/Codes/my project' && claude --resume x")
}

@Test func 작은따옴표_경로를_이스케이프한다() {
    let quoted = TerminalLauncher.shellQuote("/tmp/it's here")
    #expect(quoted == "'/tmp/it'\\''s here'")
}

@Test func 애플스크립트_역슬래시와_큰따옴표를_이스케이프한다() {
    #expect(TerminalLauncher.appleScriptQuote(#"a"b"#) == #""a\"b""#)
    #expect(TerminalLauncher.appleScriptQuote(#"a\b"#) == #""a\\b""#)
    // 역슬래시를 먼저 치환해야 한다. 순서가 틀리면 아래가 깨진다.
    #expect(TerminalLauncher.appleScriptQuote(#"a\"b"#) == #""a\\\"b""#)
}

@Test func 실행에_성공하면_launched를_돌려준다() {
    let runner = StubRunner(shouldThrow: false)
    var copied: [String] = []
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { copied.append($0) })

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .launched)
    #expect(copied.isEmpty)
    #expect(runner.received.contains("claude --resume s1"))
    #expect(runner.received.contains(#"tell application "Terminal""#))
}

@Test func 실행에_실패하면_클립보드로_폴백한다() {
    let runner = StubRunner(shouldThrow: true)
    var copied: [String] = []
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { copied.append($0) })

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .copiedToClipboard)
    #expect(copied == ["cd '/Codes/p' && claude --resume s1"])
}

private func makeSession() -> Session {
    Session(id: "s1", logPath: URL(fileURLWithPath: "/tmp/s1.jsonl"),
            cwd: "/Codes/p", title: "제목", gitBranch: nil, modifiedAt: Date())
}

private final class StubRunner: ScriptRunner, @unchecked Sendable {
    struct Failure: Error {}
    let shouldThrow: Bool
    /// 실행된 스크립트를 순서대로 모은다. 포커스 시도와 새 실행을 구분하는 데 쓴다.
    var scripts: [String] = []
    /// run이 돌려줄 값. 포커스 스크립트에는 "found"/"missing", 실행에는 tty를 흉내낸다.
    var responses: [String] = []

    /// 마지막 스크립트(기존 테스트가 참조한다)
    var received: String { scripts.last ?? "" }

    init(shouldThrow: Bool) { self.shouldThrow = shouldThrow }

    @discardableResult
    func run(_ source: String) throws -> String {
        scripts.append(source)
        if shouldThrow { throw Failure() }
        return responses.isEmpty ? "" : responses.removeFirst()
    }
}

/// 지문 값을 테스트 도중 바꿀 수 있게 담아두는 상자.
/// @Sendable 클로저가 가변 변수를 캡처할 수 없어서 필요하다.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ value: String?) { stored = value }
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// 메모리 저장소. 실제 UserDefaults를 건드리지 않는다.
private final class MemoryStore: SessionTerminalRegistry.Store, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { lock.withLock { values[key] } }
    func set(_ value: String?, forKey key: String) {
        lock.withLock { if let value { values[key] = value } else { values[key] = nil } }
    }
}

@Test func 열려있는_창이_있으면_포커스만_한다() {
    let store = MemoryStore()
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in "fp" })
    registry.record(tty: "/dev/ttys003", for: "s1")

    let runner = StubRunner(shouldThrow: false)
    runner.responses = ["found"]
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { _ in }, registry: registry)

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .focused)
    #expect(runner.scripts.count == 1)                      // 새 실행이 없어야 한다
    #expect(runner.scripts[0].contains("/dev/ttys003"))
    #expect(!runner.scripts[0].contains("--resume"))
}

@Test func 기록이_없으면_실행하고_tty를_기록한다() {
    let store = MemoryStore()
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in "fp" })

    let runner = StubRunner(shouldThrow: false)
    runner.responses = ["/dev/ttys007"]
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { _ in }, registry: registry)

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .launched)
    #expect(runner.scripts.count == 1)
    #expect(runner.scripts[0].contains("--resume s1"))
    #expect(registry.liveTTY(for: "s1") == "/dev/ttys007")
}

@Test func 창이_닫혔으면_새로_실행한다() {
    let store = MemoryStore()
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in "fp" })
    registry.record(tty: "/dev/ttys003", for: "s1")

    let runner = StubRunner(shouldThrow: false)
    runner.responses = ["missing", "/dev/ttys009"]   // 포커스 실패 → 실행
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { _ in }, registry: registry)

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .launched)
    #expect(runner.scripts.count == 2)
    #expect(runner.scripts[1].contains("--resume s1"))
    #expect(registry.liveTTY(for: "s1") == "/dev/ttys009")   // 새 tty로 갱신
}

@Test func 실행에_실패하면_낡은_기록을_지운다() {
    let store = MemoryStore()
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in "fp" })
    registry.record(tty: "/dev/ttys003", for: "s1")

    // 포커스도 실행도 모두 실패하는 상황(자동화 권한 거부)
    let runner = StubRunner(shouldThrow: true)
    var copied: [String] = []
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { copied.append($0) },
                                    registry: registry)

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .copiedToClipboard)
    #expect(copied == ["cd '/Codes/p' && claude --resume s1"])
    #expect(registry.liveTTY(for: "s1") == nil)
}

@Test func 레지스트리는_빈_tty를_기록하지_않는다() {
    let registry = SessionTerminalRegistry(store: MemoryStore(), fingerprint: { _ in "fp" })
    registry.record(tty: "   ", for: "s1")
    #expect(registry.liveTTY(for: "s1") == nil)
}

@Test func 새_세션_명령은_resume_없이_cd만_잇는다() {
    let cmd = TerminalLauncher.newSessionCommand(cwd: "/Users/me/Codes/alpha")
    #expect(cmd == "cd '/Users/me/Codes/alpha' && claude")
    #expect(!cmd.contains("--resume"))
}

@Test func 새_세션_명령도_공백_경로를_인용한다() {
    let cmd = TerminalLauncher.newSessionCommand(cwd: "/Users/me/Codes/my project")
    #expect(cmd == "cd '/Users/me/Codes/my project' && claude")
}

@Test func 새_세션_실행에_성공하면_launched를_돌려준다() {
    let runner = StubRunner(shouldThrow: false)
    var copied: [String] = []
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { copied.append($0) })

    let outcome = launcher.launchNew(inDirectory: "/Codes/p")

    #expect(outcome == .launched)
    #expect(copied.isEmpty)
    #expect(runner.received.contains("&& claude"))
    #expect(!runner.received.contains("--resume"))
}

@Test func 새_세션_실행에_실패하면_그_명령이_클립보드로_간다() {
    let runner = StubRunner(shouldThrow: true)
    var copied: [String] = []
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { copied.append($0) })

    let outcome = launcher.launchNew(inDirectory: "/Codes/my project")

    #expect(outcome == .copiedToClipboard)
    #expect(copied == ["cd '/Codes/my project' && claude"])
}

@Test func 새_세션은_tty를_기록하지_않는다() {
    // 새 세션은 아직 sessionId가 없다. 기록은 다음 스캔에서 그 세션을 발견한 뒤
    // 사용자가 클릭할 때 만들어진다.
    let registry = SessionTerminalRegistry(store: MemoryStore(), fingerprint: { _ in "fp" })
    let runner = StubRunner(shouldThrow: false)
    runner.responses = ["/dev/ttys011"]
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { _ in }, registry: registry)

    _ = launcher.launchNew(inDirectory: "/Codes/p")

    #expect(registry.liveTTY(for: "/Codes/p") == nil)
}

@Test func 창이_닫히면_살아있지_않다고_본다() {
    // 지문 함수가 nil을 주면 장치 파일이 사라진 상태다.
    let store = MemoryStore()
    let mark = Box("fp")
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in mark.value })
    registry.record(tty: "/dev/ttys002", for: "s1")
    #expect(registry.isLive("s1"))

    mark.value = nil
    #expect(!registry.isLive("s1"))
    #expect(registry.liveTTY(for: "s1") == nil)
}

@Test func tty_번호가_재사용되면_다른_창으로_본다() {
    // 같은 번호라도 할당 시각이 다르면 남의 창이다. 이걸 놓치면 엉뚱한 창을 포커스한다.
    let store = MemoryStore()
    let mark = Box("ctime-1")
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in mark.value })
    registry.record(tty: "/dev/ttys002", for: "s1")
    #expect(registry.isLive("s1"))

    mark.value = "ctime-2"   // 창이 닫히고 같은 번호가 새로 할당됨
    #expect(!registry.isLive("s1"))
}

@Test func 재사용된_tty면_포커스하지_않고_새로_연다() {
    let store = MemoryStore()
    let mark = Box("ctime-1")
    let registry = SessionTerminalRegistry(store: store, fingerprint: { _ in mark.value })
    registry.record(tty: "/dev/ttys002", for: "s1")
    mark.value = "ctime-2"

    let runner = StubRunner(shouldThrow: false)
    runner.responses = ["/dev/ttys005"]
    let launcher = TerminalLauncher(runner: runner, copyToClipboard: { _ in }, registry: registry)

    let outcome = launcher.launch(makeSession())

    #expect(outcome == .launched)
    #expect(runner.scripts.count == 1)                   // 포커스 시도조차 하지 않는다
    #expect(runner.scripts[0].contains("--resume s1"))
}
