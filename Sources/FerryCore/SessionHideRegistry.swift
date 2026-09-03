import Foundation

/// 목록에서 치워둔 세션을 기억한다.
///
/// "이 세션은 이제 안 볼래"가 "이 세션을 지울래"보다 훨씬 흔한 요구인데, 한동안
/// Ferry에는 삭제밖에 없었다. 도구가 하나뿐이면 사람은 그 도구를 쓰게 되고,
/// 되돌릴 수 없는 쪽으로 손이 간다.
///
/// 숨김은 파일을 건드리지 않는다. 순수하게 Ferry의 표시 문제이고 언제든 되돌린다.
/// 디스크를 비우는 것은 삭제의 몫이며, 그쪽은 숨긴 세션을 되돌아볼 때만 꺼낼 수 있다.
///
/// 세션마다 키를 만들지 않고 집합 하나로 저장한다. `KeyValueStore`로는 키를 열거할 수
/// 없어서, 세션이 사라졌을 때 남은 기록을 정리할 방법이 없기 때문이다.
public struct SessionHideRegistry: Sendable {

    private let store: KeyValueStore
    private static let key = "hidden.sessions"
    private static let separator = "\n"

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    public func hidden() -> Set<String> {
        guard let raw = store.string(forKey: Self.key) else { return [] }
        return Set(raw.components(separatedBy: Self.separator).filter { !$0.isEmpty })
    }

    public func isHidden(_ sessionId: String) -> Bool {
        hidden().contains(sessionId)
    }

    public func hide(_ sessionId: String) {
        guard !sessionId.isEmpty else { return }
        write(hidden().union([sessionId]))
    }

    public func reveal(_ sessionId: String) {
        write(hidden().subtracting([sessionId]))
    }

    /// 사라진 세션의 숨김 기록을 지운다.
    /// 그러지 않으면 삭제한 세션의 기록이 UserDefaults에 영원히 남는다.
    public func reconcile(_ sessions: [Session]) {
        let alive = Set(sessions.map(\.id))
        let current = hidden()
        let kept = current.intersection(alive)
        if kept != current { write(kept) }
    }

    private func write(_ ids: Set<String>) {
        store.set(ids.isEmpty ? nil : ids.sorted().joined(separator: Self.separator),
                  forKey: Self.key)
    }
}
