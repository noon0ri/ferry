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
    var received = ""
    init(shouldThrow: Bool) { self.shouldThrow = shouldThrow }
    func run(_ source: String) throws {
        received = source
        if shouldThrow { throw Failure() }
    }
}
