import Testing
import Foundation
@testable import FerryCore

private func makeSessionFile(_ contents: String, id: String = "s1") throws -> Session {
    let url = try makeFixture(contents, name: "\(id).jsonl")
    return Session(id: id, logPath: url, cwd: "/Codes/p",
                   title: "이전 제목", gitBranch: nil, modifiedAt: Date())
}

@Test func 이름을_바꾸면_스캔_결과에_반영된다() throws {
    let session = try makeSessionFile(sampleLog(sessionId: "s1", cwd: "/Codes/p",
                                                title: "자동 생성 제목"), id: "s1")
    try SessionRenamer().rename(session, to: "내가 붙인 이름")

    let rescanned = try #require(SessionScanner.scan(logPath: session.logPath))
    #expect(rescanned.title == "내가 붙인 이름")
}

@Test func 사용자_이름이_자동_제목을_이긴다() throws {
    // custom-title이 먼저, ai-title이 나중에 와도 사용자 이름이 이겨야 한다.
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/Codes/p"}
    {"type":"custom-title","customTitle":"사용자 이름","sessionId":"s1"}
    {"type":"ai-title","aiTitle":"나중에 생성된 자동 제목","sessionId":"s1"}
    """
    let url = try makeFixture(text)
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "사용자 이름")
}

@Test func 이름을_여러번_바꾸면_마지막_것이_남는다() throws {
    let session = try makeSessionFile(sampleLog(sessionId: "s1", cwd: "/Codes/p"), id: "s1")
    let renamer = SessionRenamer()
    try renamer.rename(session, to: "첫 번째")
    try renamer.rename(session, to: "두 번째")

    let rescanned = try #require(SessionScanner.scan(logPath: session.logPath))
    #expect(rescanned.title == "두 번째")
}

@Test func 개행으로_끝나지_않는_파일에도_안전하게_덧붙인다() throws {
    // 마지막 줄에 이어붙으면 그 줄과 우리 레코드가 둘 다 깨진다.
    let noTrailingNewline = """
    {"type":"user","sessionId":"s1","cwd":"/Codes/p"}
    {"type":"ai-title","aiTitle":"자동 제목","sessionId":"s1"}
    """
    let url = try makeFixture(noTrailingNewline)
    let session = Session(id: "s1", logPath: url, cwd: "/Codes/p",
                          title: "자동 제목", gitBranch: nil, modifiedAt: Date())

    try SessionRenamer().rename(session, to: "새 이름")

    // 앞줄이 멀쩡히 남아 있어야 한다
    let written = try String(contentsOf: url, encoding: .utf8)
    let lines = written.split(separator: "\n").filter { !$0.isEmpty }
    for line in lines {
        #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil,
                "깨진 줄: \(line)")
    }
    let rescanned = try #require(SessionScanner.scan(logPath: url))
    #expect(rescanned.title == "새 이름")
    #expect(rescanned.cwd == "/Codes/p")
}

@Test func 빈_이름은_거부한다() throws {
    let session = try makeSessionFile(sampleLog(sessionId: "s1", cwd: "/Codes/p"), id: "s1")
    #expect(throws: SessionRenamer.RenameError.emptyName) {
        try SessionRenamer().rename(session, to: "   ")
    }
}

@Test func jsonl이_아니면_이름을_바꾸지_않는다() throws {
    let url = try makeFixture("x", name: "notes.txt")
    let session = Session(id: "s1", logPath: url, cwd: "/Codes/p",
                          title: "제목", gitBranch: nil, modifiedAt: Date())
    #expect(throws: SessionRenamer.RenameError.notASessionLog(url)) {
        try SessionRenamer().rename(session, to: "새 이름")
    }
}
