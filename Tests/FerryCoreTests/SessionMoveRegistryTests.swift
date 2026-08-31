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

private func session(_ id: String, cwd: String) -> Session {
    Session(id: id, logPath: URL(fileURLWithPath: "/tmp/\(id).jsonl"), cwd: cwd,
            title: "제목", gitBranch: nil, modifiedAt: Date())
}

@Test func 이동을_예약하고_읽는다() {
    let moves = SessionMoveRegistry(store: Store())
    moves.schedule("/Codes/ferry", for: "s1")
    #expect(moves.target(for: "s1") == "/Codes/ferry")
    #expect(moves.target(for: "s2") == nil)
}

@Test func 예약은_취소할_수_있다() {
    let moves = SessionMoveRegistry(store: Store())
    moves.schedule("/Codes/ferry", for: "s1")
    moves.cancel("s1")
    #expect(moves.target(for: "s1") == nil)
}

@Test func 목적지에_도착한_예약은_스스로_지워진다() {
    // 사용자가 옮기고 재개하면 로그의 cwd가 목표와 같아진다. 그때 예약은 소임을 다한다.
    let moves = SessionMoveRegistry(store: Store())
    moves.schedule("/Codes/ferry", for: "s1")

    moves.reconcile([session("s1", cwd: "/Codes/ferry")])

    #expect(moves.target(for: "s1") == nil)
}

@Test func 아직_옮겨지지_않았으면_예약이_남는다() {
    let moves = SessionMoveRegistry(store: Store())
    moves.schedule("/Codes/ferry", for: "s1")

    moves.reconcile([session("s1", cwd: "/Codes/any")])   // 아직 옛 폴더

    #expect(moves.target(for: "s1") == "/Codes/ferry")
}

@Test func 빈_목적지는_예약하지_않는다() {
    let moves = SessionMoveRegistry(store: Store())
    moves.schedule("   ", for: "s1")
    #expect(moves.target(for: "s1") == nil)
}
