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

@Test func 숨기고_되돌린다() {
    let hides = SessionHideRegistry(store: Store())
    #expect(!hides.isHidden("s1"))

    hides.hide("s1")
    #expect(hides.isHidden("s1"))

    hides.reveal("s1")
    #expect(!hides.isHidden("s1"))
}

@Test func 여러_세션을_숨긴다() {
    let hides = SessionHideRegistry(store: Store())
    hides.hide("s1")
    hides.hide("s2")
    #expect(hides.hidden() == ["s1", "s2"])

    hides.reveal("s1")
    #expect(hides.hidden() == ["s2"])
}

@Test func 사라진_세션의_기록은_정리된다() {
    // 삭제한 세션의 숨김 표시가 영원히 남지 않게 한다.
    let hides = SessionHideRegistry(store: Store())
    hides.hide("s1")
    hides.hide("gone")

    hides.reconcile([session("s1")])

    #expect(hides.hidden() == ["s1"])
}

@Test func 숨김이_저장소에_남는다() {
    // 앱을 껐다 켜도 유지되어야 한다.
    let store = Store()
    SessionHideRegistry(store: store).hide("s1")
    #expect(SessionHideRegistry(store: store).isHidden("s1"))
}

@Test func 같은_세션을_두_번_숨겨도_하나다() {
    let hides = SessionHideRegistry(store: Store())
    hides.hide("s1")
    hides.hide("s1")
    #expect(hides.hidden() == ["s1"])
}
