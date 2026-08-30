import Foundation
import AppKit

public protocol ScriptRunner: Sendable {
    func run(_ source: String) throws
}

public struct AppleScriptRunner: ScriptRunner {
    public struct Failure: Error {
        public let message: String
    }

    public init() {}

    public func run(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw Failure(message: "AppleScript를 만들 수 없습니다")
        }
        script.executeAndReturnError(&error)
        if let error {
            // 자동화 권한 거부(-1743)도 여기로 온다.
            throw Failure(message: error.description)
        }
    }
}

public enum LaunchOutcome: Equatable, Sendable {
    case launched
    case copiedToClipboard
}

public struct TerminalLauncher {

    private let runner: ScriptRunner
    private let copyToClipboard: (String) -> Void

    public init(runner: ScriptRunner = AppleScriptRunner(),
                copyToClipboard: @escaping (String) -> Void = TerminalLauncher.pasteboardCopy) {
        self.runner = runner
        self.copyToClipboard = copyToClipboard
    }

    public static func pasteboardCopy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 셸 단일 인용. 내부의 작은따옴표는 '\'' 로 끊어 붙인다.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript 문자열 리터럴. 역슬래시를 먼저 치환해야 한다.
    public static func appleScriptQuote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    public static func command(cwd: String, sessionId: String) -> String {
        "cd \(shellQuote(cwd)) && claude --resume \(sessionId)"
    }

    /// Terminal.app 새 탭에서 세션을 재개한다.
    /// 자동화 권한이 없으면 명령을 클립보드에 복사하는 것으로 폴백한다.
    @discardableResult
    public func launch(_ session: Session) -> LaunchOutcome {
        let command = Self.command(cwd: session.cwd, sessionId: session.id)
        let source = """
        tell application "Terminal"
            activate
            do script \(Self.appleScriptQuote(command))
        end tell
        """
        do {
            try runner.run(source)
            return .launched
        } catch {
            copyToClipboard(command)
            return .copiedToClipboard
        }
    }
}
