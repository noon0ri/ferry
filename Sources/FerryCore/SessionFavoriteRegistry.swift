import Foundation

/// 자주 돌아가는 세션을 표시해 둔다.
///
/// 실제 사용 로그를 보면 두 달에 걸쳐 14일간 이어간 세션이 있고, 4일 이상 돌아간 세션이
/// 18개 중 6개였다. 그 6개가 서로 다른 6개 그룹에 흩어져 있어, 매번 그룹을 펼쳐야 닿았다.
/// 즐겨찾기는 그것들을 목록 맨 위 한 곳에 모은다.
///
/// 숨김과 마찬가지로 세션마다 키를 만들지 않고 집합 하나로 저장한다.
/// `KeyValueStore`로는 키를 열거할 수 없어, 사라진 세션의 기록을 정리할 방법이 없기 때문이다.
public struct SessionFavoriteRegistry: Sendable {

    private let store: KeyValueStore
    private static let key = "favorite.sessions"
    private static let separator = "\n"

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    public func favorites() -> Set<String> {
        guard let raw = store.string(forKey: Self.key) else { return [] }
        return Set(raw.components(separatedBy: Self.separator).filter { !$0.isEmpty })
    }

    public func isFavorite(_ sessionId: String) -> Bool {
        favorites().contains(sessionId)
    }

    public func add(_ sessionId: String) {
        guard !sessionId.isEmpty else { return }
        write(favorites().union([sessionId]))
    }

    public func remove(_ sessionId: String) {
        write(favorites().subtracting([sessionId]))
    }

    public func toggle(_ sessionId: String) {
        isFavorite(sessionId) ? remove(sessionId) : add(sessionId)
    }

    /// 사라진 세션의 기록을 지운다.
    public func reconcile(_ sessions: [Session]) {
        let alive = Set(sessions.map(\.id))
        let current = favorites()
        let kept = current.intersection(alive)
        if kept != current { write(kept) }
    }

    private func write(_ ids: Set<String>) {
        store.set(ids.isEmpty ? nil : ids.sorted().joined(separator: Self.separator),
                  forKey: Self.key)
    }
}
