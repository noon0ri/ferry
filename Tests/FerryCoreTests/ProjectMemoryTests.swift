import Testing
import Foundation
@testable import FerryCore

private func makeProject(withMemory files: [String]) throws -> Session {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ferry-mem-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let log = dir.appendingPathComponent("s1.jsonl")
    try "x".write(to: log, atomically: true, encoding: .utf8)

    if !files.isEmpty {
        let memory = dir.appendingPathComponent("memory")
        try fm.createDirectory(at: memory, withIntermediateDirectories: true)
        for name in files {
            try "내용".write(to: memory.appendingPathComponent(name),
                            atomically: true, encoding: .utf8)
        }
    }
    return Session(id: "s1", logPath: log, cwd: "/Codes/p",
                   title: "제목", gitBranch: nil, modifiedAt: Date())
}

@Test func 메모리_파일_수를_센다() throws {
    let session = try makeProject(withMemory: ["MEMORY.md", "a.md", "b.md"])
    #expect(ProjectMemory.fileCount(for: session) == 3)
}

@Test func 메모리가_없으면_0이다() throws {
    let session = try makeProject(withMemory: [])
    #expect(ProjectMemory.fileCount(for: session) == 0)
}

@Test func md가_아닌_파일은_세지_않는다() throws {
    let session = try makeProject(withMemory: ["MEMORY.md", "notes.txt", "a.md"])
    #expect(ProjectMemory.fileCount(for: session) == 2)
}

@Test func 메모리_디렉토리는_로그_옆에서_찾는다() throws {
    // 디렉토리 이름 인코딩을 되돌리지 않고 로그 경로에서 얻는다.
    let session = try makeProject(withMemory: ["a.md"])
    let dir = ProjectMemory.directory(for: session)
    #expect(dir.lastPathComponent == "memory")
    #expect(dir.deletingLastPathComponent() == session.logPath.deletingLastPathComponent())
}
