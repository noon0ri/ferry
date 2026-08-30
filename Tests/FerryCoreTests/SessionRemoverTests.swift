import Testing
import Foundation
@testable import FerryCore

/// 세션 로그 + 서브에이전트 디렉토리 + memory 디렉토리를 갖춘 프로젝트 폴더를 만든다.
private func makeProjectDir() throws -> (dir: URL, session: Session) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ferry-remove-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let id = "01292266-bea7-439a-8174-de310dbb1f5f"
    let log = dir.appendingPathComponent("\(id).jsonl")
    try String(repeating: "x", count: 100).write(to: log, atomically: true, encoding: .utf8)

    let subagents = dir.appendingPathComponent(id)
    try fm.createDirectory(at: subagents.appendingPathComponent("subagents"),
                           withIntermediateDirectories: true)
    try String(repeating: "y", count: 250)
        .write(to: subagents.appendingPathComponent("subagents/agent-1.jsonl"),
               atomically: true, encoding: .utf8)

    // 세션이 아닌 것. 절대 치워지면 안 된다.
    try fm.createDirectory(at: dir.appendingPathComponent("memory"),
                           withIntermediateDirectories: true)

    let session = Session(id: id, logPath: log, cwd: "/Codes/p",
                          title: "제목", gitBranch: nil, modifiedAt: Date())
    return (dir, session)
}

@Test func 로그와_서브에이전트_디렉토리를_함께_치운다() throws {
    let (_, session) = try makeProjectDir()
    var moved: [String] = []
    let remover = SessionRemover { moved.append($0.lastPathComponent) }

    try remover.remove(session)

    #expect(moved.count == 2)
    #expect(moved.contains("01292266-bea7-439a-8174-de310dbb1f5f.jsonl"))
    #expect(moved.contains("01292266-bea7-439a-8174-de310dbb1f5f"))
}

@Test func memory_디렉토리는_절대_대상이_아니다() throws {
    let (_, session) = try makeProjectDir()
    var moved: [URL] = []
    let remover = SessionRemover { moved.append($0) }

    try remover.remove(session)

    #expect(moved.allSatisfy { $0.lastPathComponent != "memory" })
    #expect(moved.allSatisfy { !$0.path.contains("/memory") })
}

@Test func memory를_세션인_척_넘겨도_거부한다() throws {
    let (dir, _) = try makeProjectDir()
    // logPath가 memory.jsonl이면 형제 디렉토리가 memory/가 되어버린다. 그 경로를 막는다.
    let fake = Session(id: "memory", logPath: dir.appendingPathComponent("memory.jsonl"),
                       cwd: "/Codes/p", title: "위장", gitBranch: nil, modifiedAt: Date())
    var moved: [URL] = []
    let remover = SessionRemover { moved.append($0) }

    // URL 동등 비교는 디렉토리 실재 여부에 따라 끝 슬래시가 붙어 어긋난다.
    // 어떤 경로를 보호했는지만 확인한다.
    do {
        try remover.remove(fake)
        Issue.record("memory를 거부하지 않았다")
    } catch let error as SessionRemover.RemovalError {
        guard case .protectedPath(let url) = error else {
            Issue.record("예상과 다른 오류: \(error)")
            return
        }
        #expect(url.lastPathComponent == "memory")
    }
    #expect(moved.isEmpty)
}

@Test func jsonl이_아니면_거부한다() throws {
    let (dir, _) = try makeProjectDir()
    let fake = Session(id: "x", logPath: dir.appendingPathComponent("something.txt"),
                       cwd: "/Codes/p", title: "위장", gitBranch: nil, modifiedAt: Date())
    var moved: [URL] = []
    let remover = SessionRemover { moved.append($0) }

    #expect(throws: SessionRemover.RemovalError.notASessionLog(dir.appendingPathComponent("something.txt"))) {
        try remover.remove(fake)
    }
    #expect(moved.isEmpty)
}

@Test func 서브에이전트_디렉토리가_없어도_로그는_치운다() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ferry-remove-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let log = dir.appendingPathComponent("s1.jsonl")
    try "x".write(to: log, atomically: true, encoding: .utf8)
    let session = Session(id: "s1", logPath: log, cwd: "/Codes/p",
                          title: "제목", gitBranch: nil, modifiedAt: Date())

    var moved: [URL] = []
    let remover = SessionRemover { moved.append($0) }
    try remover.remove(session)

    #expect(moved.count == 1)
}

@Test func 용량은_로그와_서브에이전트를_합친다() throws {
    let (_, session) = try makeProjectDir()
    // 로그 100바이트 + 서브에이전트 250바이트
    #expect(SessionRemover.totalSize(of: session) >= 350)
}
