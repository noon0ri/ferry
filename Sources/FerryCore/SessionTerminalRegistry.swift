import Foundation

/// 세션이 어느 터미널에서 열렸는지 기억하고, 그 터미널이 아직 살아 있는지 답한다.
///
/// 같은 프로젝트 폴더에 세션이 여러 개인 것이 보통이라, 경로로는 창을 구분할 수 없다.
/// 대신 tty(`/dev/ttys003`)를 쓴다.
///
/// 다만 tty 번호는 **재사용된다**. 창을 닫으면 장치 파일이 사라지고, 다음에 열리는
/// 창이 같은 번호를 받는 일이 흔하다. 번호만 보면 남의 창을 내 세션으로 착각한다.
/// 그래서 `TTYProbe`가 만드는 지문(그 tty의 세션 리더 프로세스)을 함께 기록한다.
/// 번호가 같아도 지문이 다르면 다른 창이다.
///
/// 확인은 sysctl 한 번이라 AppleScript도 권한도 프로세스 스폰도 필요 없다.
/// 목록을 그릴 때마다 세션별로 물어봐도 부담이 없다.
public struct SessionTerminalRegistry: Sendable {

    private let store: KeyValueStore
    /// tty 경로 → 지문. 기본 구현은 장치 파일의 ctime을 읽는다.
    private let fingerprint: @Sendable (String) -> String?
    private static let prefix = "terminal.tty."
    private static let separator = "\u{1F}"

    public init(store: KeyValueStore = UserDefaults.standard,
                fingerprint: @escaping @Sendable (String) -> String? = TTYProbe.fingerprint) {
        self.store = store
        self.fingerprint = fingerprint
    }

    public func record(tty: String, for sessionId: String) {
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mark = fingerprint(trimmed) ?? ""
        store.set(trimmed + Self.separator + mark, forKey: Self.prefix + sessionId)
    }

    /// 기록된 터미널이 아직 살아 있으면 그 tty를, 닫혔거나 다른 창으로 바뀌었으면 nil.
    public func liveTTY(for sessionId: String) -> String? {
        guard let raw = store.string(forKey: Self.prefix + sessionId) else { return nil }
        let parts = raw.components(separatedBy: Self.separator)
        guard let tty = parts.first, !tty.isEmpty else { return nil }
        let recorded = parts.count > 1 ? parts[1] : ""
        guard let current = fingerprint(tty) else { return nil }   // 파일 없음 = 창 닫힘
        guard current == recorded else { return nil }              // 번호 재사용
        return tty
    }

    public func isLive(_ sessionId: String) -> Bool {
        liveTTY(for: sessionId) != nil
    }

    public func forget(_ sessionId: String) {
        store.set(nil, forKey: Self.prefix + sessionId)
    }
}
