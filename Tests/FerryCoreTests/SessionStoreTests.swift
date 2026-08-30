import Testing
import Foundation
@testable import FerryCore

/// 가짜 로그 루트를 만든다. 반환값은 루트 URL.
private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ferry-root-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func addLog(_ root: URL, projectDir: String, sessionId: String,
                    contents: String) throws -> URL {
    let dir = root.appendingPathComponent(projectDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(sessionId).jsonl")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func 세션을_cwd로_묶는다() throws {
    let root = try makeRoot()
    _ = try addLog(root, projectDir: "-Users-x-Codes-alpha", sessionId: "s1",
                   contents: sampleLog(sessionId: "s1", cwd: "/Codes/alpha", title: "첫째"))
    _ = try addLog(root, projectDir: "-Users-x-Codes-alpha", sessionId: "s2",
                   contents: sampleLog(sessionId: "s2", cwd: "/Codes/alpha", title: "둘째"))
    _ = try addLog(root, projectDir: "-Users-x-Codes-beta", sessionId: "s3",
                   contents: sampleLog(sessionId: "s3", cwd: "/Codes/beta", title: "셋째"))

    let store = SessionStore(root: root)
    store.refresh()

    #expect(store.projects.count == 2)
    let alpha = try #require(store.projects.first { $0.path == "/Codes/alpha" })
    #expect(alpha.sessions.count == 2)
    #expect(alpha.name == "alpha")
}

@Test func subagents_하위는_스캔하지_않는다() throws {
    let root = try makeRoot()
    _ = try addLog(root, projectDir: "-p", sessionId: "main",
                   contents: sampleLog(sessionId: "main", cwd: "/Codes/p"))
    let subDir = root.appendingPathComponent("-p/main/subagents")
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    try sampleLog(sessionId: "agent-1", cwd: "/Codes/p")
        .write(to: subDir.appendingPathComponent("agent-1.jsonl"),
               atomically: true, encoding: .utf8)

    let store = SessionStore(root: root)
    store.refresh()

    let all = store.projects.flatMap(\.sessions)
    #expect(all.count == 1)
    #expect(all.first?.id == "main")
}

@Test func 프로젝트는_최근활동_내림차순이다() throws {
    let root = try makeRoot()
    let oldURL = try addLog(root, projectDir: "-old", sessionId: "o",
                            contents: sampleLog(sessionId: "o", cwd: "/Codes/old"))
    _ = try addLog(root, projectDir: "-new", sessionId: "n",
                   contents: sampleLog(sessionId: "n", cwd: "/Codes/new"))
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: oldURL.path)

    let store = SessionStore(root: root)
    store.refresh()

    #expect(store.projects.map(\.path) == ["/Codes/new", "/Codes/old"])
}

@Test func 세션은_그룹_안에서_최근순이다() throws {
    let root = try makeRoot()
    let older = try addLog(root, projectDir: "-p", sessionId: "older",
                           contents: sampleLog(sessionId: "older", cwd: "/Codes/p"))
    _ = try addLog(root, projectDir: "-p", sessionId: "newer",
                   contents: sampleLog(sessionId: "newer", cwd: "/Codes/p"))
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: older.path)

    let store = SessionStore(root: root)
    store.refresh()

    #expect(store.projects[0].sessions.map(\.id) == ["newer", "older"])
}

@Test func mtime이_그대로면_다시_파싱하지_않는다() throws {
    let root = try makeRoot()
    _ = try addLog(root, projectDir: "-p", sessionId: "s1",
                   contents: sampleLog(sessionId: "s1", cwd: "/Codes/p"))

    let counter = ScanCounter()
    let store = SessionStore(root: root, scan: { url in
        counter.increment()
        return SessionScanner.scan(logPath: url)
    })

    store.refresh()
    store.refresh()

    #expect(counter.value == 1)
}

@Test func 루트가_없으면_빈_목록이다() {
    let missing = URL(fileURLWithPath: "/tmp/ferry-does-not-exist-\(UUID().uuidString)")
    let store = SessionStore(root: missing)
    store.refresh()
    #expect(store.projects.isEmpty)
}

/// 스캔 호출 횟수를 세는 테스트 보조 타입.
private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// 실제 로그가 있을 때만 도는 성능 확인용 테스트.
@Test func 실제_로그_스캔이_예산_안에_든다() throws {
    let root = SessionStore.defaultRoot
    try #require(FileManager.default.fileExists(atPath: root.path),
                 "~/.claude/projects 가 없어 건너뜁니다")

    let store = SessionStore(root: root)
    let start = Date()
    store.refresh()
    let elapsed = Date().timeIntervalSince(start)

    let count = store.projects.flatMap(\.sessions).count
    let budget = max(0.2, 0.2 * Double(count) / 300.0)

    print("세션 \(count)개, 첫 스캔 \(Int(elapsed * 1000))ms (예산 \(Int(budget * 1000))ms)")
    #expect(elapsed < budget)
}
