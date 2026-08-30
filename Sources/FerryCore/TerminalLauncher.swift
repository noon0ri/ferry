import Foundation
import AppKit

public protocol ScriptRunner: Sendable {
    /// AppleScript를 실행하고 결과 문자열을 돌려준다.
    /// 실행한 탭의 tty를 되받아야 하므로 반환값이 필요하다.
    @discardableResult
    func run(_ source: String) throws -> String
}

public struct AppleScriptRunner: ScriptRunner {
    public struct Failure: Error {
        public let message: String
    }

    public init() {}

    @discardableResult
    public func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw Failure(message: "AppleScript를 만들 수 없습니다")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            // 자동화 권한 거부(-1743)도 여기로 온다.
            throw Failure(message: error.description)
        }
        return result.stringValue ?? ""
    }
}

public enum LaunchOutcome: Equatable, Sendable {
    /// 새 터미널 창에서 실행했다.
    case launched
    /// 이미 열려 있던 창을 앞으로 가져왔다.
    case focused
    case copiedToClipboard
}

public struct TerminalLauncher {

    private let runner: ScriptRunner
    private let copyToClipboard: (String) -> Void
    private let registry: SessionTerminalRegistry

    public init(runner: ScriptRunner = AppleScriptRunner(),
                copyToClipboard: @escaping (String) -> Void = TerminalLauncher.pasteboardCopy,
                registry: SessionTerminalRegistry = SessionTerminalRegistry()) {
        self.runner = runner
        self.copyToClipboard = copyToClipboard
        self.registry = registry
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

    /// 재개가 아니라 그 폴더에서 새 대화를 시작하는 명령.
    public static func newSessionCommand(cwd: String) -> String {
        "cd \(shellQuote(cwd)) && claude"
    }

    /// 이미 이 세션으로 열어둔 창이 살아 있으면 그 창을 앞으로 가져오고,
    /// 없으면 새 창에서 재개한다.
    @discardableResult
    public func launch(_ session: Session) -> LaunchOutcome {
        if let tty = registry.tty(for: session.id), focusTerminal(tty: tty) {
            return .focused
        }
        let outcome = send(Self.command(cwd: session.cwd, sessionId: session.id),
                           recordTTYFor: session.id)
        if outcome == .copiedToClipboard {
            // 실행하지 못했으므로 낡은 기록을 남겨두지 않는다.
            registry.forget(session.id)
        }
        return outcome
    }

    /// 해당 tty를 가진 탭을 찾아 그 창을 앞으로 가져온다.
    /// 창이 이미 닫혔으면 false. 그때는 호출자가 새로 연다.
    private func focusTerminal(tty: String) -> Bool {
        let source = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is \(Self.appleScriptQuote(tty)) then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
            return "missing"
        end tell
        """
        guard let result = try? runner.run(source) else { return false }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
    }

    /// Terminal.app 새 창에서 해당 폴더에 새 세션을 연다.
    @discardableResult
    public func launchNew(inDirectory path: String) -> LaunchOutcome {
        send(Self.newSessionCommand(cwd: path))
    }

    /// 재개와 새 세션이 공유하는 실행부.
    /// 두 경로가 같은 폴백 규칙(자동화 권한이 없으면 클립보드로)을 따라야 하므로
    /// 한 곳에만 둔다. `do script`에 `in window` 대상이 없어 매번 새 창이 열린다.
    private func send(_ command: String, recordTTYFor sessionId: String? = nil) -> LaunchOutcome {
        // 실행한 탭의 tty를 돌려받아, 다음 클릭 때 이 창을 되찾는 데 쓴다.
        let source = """
        tell application "Terminal"
            activate
            set ferryTab to do script \(Self.appleScriptQuote(command))
            return tty of ferryTab
        end tell
        """
        do {
            let tty = try runner.run(source)
            if let sessionId {
                registry.record(tty: tty, for: sessionId)
            }
            return .launched
        } catch {
            copyToClipboard(command)
            return .copiedToClipboard
        }
    }
}
