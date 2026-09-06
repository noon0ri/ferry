import Testing
import Foundation
@testable import FerryCore

private final class Store: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { lock.withLock { values[key] } }
    func set(_ value: String?, forKey key: String) {
        lock.withLock { if let value { values[key] = value } else { values[key] = nil } }
    }
}

private func session(_ id: String) -> Session {
    Session(id: id, logPath: URL(fileURLWithPath: "/tmp/\(id).jsonl"), cwd: "/Codes/p",
            title: "제목", gitBranch: nil, modifiedAt: Date())
}

@Test func 즐겨찾기를_켜고_끈다() {
    let favorites = SessionFavoriteRegistry(store: Store())
    #expect(!favorites.isFavorite("s1"))

    favorites.toggle("s1")
    #expect(favorites.isFavorite("s1"))

    favorites.toggle("s1")
    #expect(!favorites.isFavorite("s1"))
}

@Test func 여러_세션을_담는다() {
    let favorites = SessionFavoriteRegistry(store: Store())
    favorites.add("s1")
    favorites.add("s2")
    #expect(favorites.favorites() == ["s1", "s2"])

    favorites.remove("s1")
    #expect(favorites.favorites() == ["s2"])
}

@Test func 사라진_세션의_즐겨찾기는_정리된다() {
    let favorites = SessionFavoriteRegistry(store: Store())
    favorites.add("s1")
    favorites.add("gone")

    favorites.reconcile([session("s1")])

    #expect(favorites.favorites() == ["s1"])
}

@Test func 즐겨찾기가_저장소에_남는다() {
    let store = Store()
    SessionFavoriteRegistry(store: store).add("s1")
    #expect(SessionFavoriteRegistry(store: store).isFavorite("s1"))
}

@Test func 같은_세션을_두_번_담아도_하나다() {
    let favorites = SessionFavoriteRegistry(store: Store())
    favorites.add("s1")
    favorites.add("s1")
    #expect(favorites.favorites() == ["s1"])
}
