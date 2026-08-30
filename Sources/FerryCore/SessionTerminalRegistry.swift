import Foundation

/// 세션이 어느 터미널에서 열렸는지 기억한다.
///
/// 같은 프로젝트 폴더에 세션이 여러 개인 것이 보통이라, 경로로는 창을 구분할 수 없다.
/// 대신 tty(`/dev/ttys003`)를 쓴다. 터미널 세션마다 유일하고 살아 있는 동안 재사용되지 않는다.
///
/// 저장은 앱 재시작을 넘어 유지된다. 메모리에만 두면 Ferry를 껐다 켤 때마다
/// 모든 세션이 새 창을 열게 되어 기능이 반쪽이 된다.
public struct SessionTerminalRegistry: Sendable {

    /// 테스트가 메모리 구현을 끼워 넣을 수 있도록 최소 인터페이스만 요구한다.
    public protocol Store: AnyObject, Sendable {
        func string(forKey key: String) -> String?
        func set(_ value: String?, forKey key: String)
    }

    private let store: Store
    private static let prefix = "terminal.tty."

    public init(store: Store = UserDefaults.standard) {
        self.store = store
    }

    public func tty(for sessionId: String) -> String? {
        store.string(forKey: Self.prefix + sessionId)
    }

    public func record(tty: String, for sessionId: String) {
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.set(trimmed, forKey: Self.prefix + sessionId)
    }

    public func forget(_ sessionId: String) {
        store.set(nil, forKey: Self.prefix + sessionId)
    }
}

extension UserDefaults: SessionTerminalRegistry.Store {
    public func set(_ value: String?, forKey key: String) {
        if let value {
            setValue(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
