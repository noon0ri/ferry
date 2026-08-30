import Testing
import Foundation
@testable import FerryCore

@Test func 정상_로그에서_모든_필드를_뽑는다() {
    let fields = SessionScanner.parse(sampleLog(), dropFirstLine: false)
    #expect(fields.aiTitle == "Enigma 퍼즐 파이프라인 그룹4 실행")
    #expect(fields.cwd == "/Users/me/Codes/alpha")
    #expect(fields.gitBranch == "main")
    #expect(fields.sessionId == "01292266-bea7-439a-8174-de310dbb1f5f")
    #expect(fields.firstUserPrompt == "handoff.md를 읽어라")
}

@Test func gitBranch가_null이면_nil이다() {
    let fields = SessionScanner.parse(sampleLog(gitBranch: nil), dropFirstLine: false)
    #expect(fields.gitBranch == nil)
    #expect(fields.cwd == "/Users/me/Codes/alpha")
}

@Test func aiTitle이_여러번이면_마지막_값을_쓴다() {
    let text = """
    {"type":"ai-title","aiTitle":"초안 제목","sessionId":"s1"}
    {"type":"user","sessionId":"s1","cwd":"/tmp/p","gitBranch":null}
    {"type":"ai-title","aiTitle":"최종 제목","sessionId":"s1"}
    """
    let fields = SessionScanner.parse(text, dropFirstLine: false)
    #expect(fields.aiTitle == "최종 제목")
}

@Test func 배열형_content에서_첫_프롬프트를_뽑는다() {
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/tmp/p","message":{"role":"user","content":[{"type":"text","text":"이미지 설명"}]}}
    """
    let fields = SessionScanner.parse(text, dropFirstLine: false)
    #expect(fields.firstUserPrompt == "이미지 설명")
}

@Test func dropFirstLine이면_첫_줄을_버린다() {
    // 첫 줄은 유효한 JSON이다. dropFirstLine이 실제로 동작해야만 aiTitle이 nil이 된다.
    let text = """
    {"type":"ai-title","aiTitle":"버려야 할 줄","sessionId":"s1"}
    {"type":"user","sessionId":"s1","cwd":"/tmp/p"}
    """
    #expect(SessionScanner.parse(text, dropFirstLine: true).aiTitle == nil)
    #expect(SessionScanner.parse(text, dropFirstLine: false).aiTitle == "버려야 할 줄")
}

@Test func 파일을_스캔해_세션을_만든다() throws {
    let url = try makeFixture(sampleLog(),
                              name: "01292266-bea7-439a-8174-de310dbb1f5f.jsonl")
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.id == "01292266-bea7-439a-8174-de310dbb1f5f")
    #expect(session.title == "Enigma 퍼즐 파이프라인 그룹4 실행")
    #expect(session.cwd == "/Users/me/Codes/alpha")
    #expect(session.gitBranch == "main")
}

@Test func 제목이_없으면_첫_프롬프트로_폴백한다() throws {
    let url = try makeFixture(sampleLog(title: nil, prompt: "npm install이 실패해"))
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "npm install이 실패해")
}

@Test func 제목과_프롬프트가_없으면_id_앞_8자를_쓴다() throws {
    let text = """
    {"type":"assistant","sessionId":"abcdef12-3456-7890-abcd-ef1234567890","cwd":"/tmp/p"}
    """
    let url = try makeFixture(text)
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "abcdef12")
}

@Test func 손상된_라인이_섞여도_나머지를_파싱한다() throws {
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/tmp/p"}
    이건 JSON이 아니다
    {"type":"ai-title","aiTitle":"살아남은 제목","sessionId":"s1"}
    {"broken":
    """
    let url = try makeFixture(text)
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "살아남은 제목")
}

@Test func 빈_파일은_nil을_반환한다() throws {
    let url = try makeFixture("")
    #expect(SessionScanner.scan(logPath: url) == nil)
}

@Test func cwd가_없으면_nil을_반환한다() throws {
    let text = """
    {"type":"ai-title","aiTitle":"cwd 없음","sessionId":"s1"}
    """
    let url = try makeFixture(text)
    #expect(SessionScanner.scan(logPath: url) == nil)
}

@Test func 꼬리에_제목이_없으면_전체를_다시_읽는다() throws {
    // 제목을 맨 앞에 두고, 꼬리 예산을 넘기는 더미를 뒤에 채운다
    let filler = (0..<2000).map { i in
        "{\"type\":\"assistant\",\"sessionId\":\"s1\",\"cwd\":\"/tmp/p\",\"n\":\(i),\"pad\":\"\(String(repeating: "x", count: 200))\"}"
    }.joined(separator: "\n")
    let text = """
    {"type":"ai-title","aiTitle":"맨 앞의 제목","sessionId":"s1"}
    {"type":"user","sessionId":"s1","cwd":"/tmp/p"}
    \(filler)
    """
    #expect(text.utf8.count > SessionScanner.tailBytes)

    let url = try makeFixture(text)
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "맨 앞의 제목")
}

@Test func 큰_파일도_꼬리에_제목이_있으면_그대로_읽는다() throws {
    // 실제 세션 대부분이 타는 경로: 파일이 256KB를 넘고, 최신 ai-title은 끝부분에 있다.
    let filler = (0..<2000).map { i in
        "{\"type\":\"assistant\",\"sessionId\":\"s1\",\"cwd\":\"/tmp/p\",\"gitBranch\":\"main\",\"n\":\(i),\"pad\":\"\(String(repeating: "x", count: 200))\"}"
    }.joined(separator: "\n")
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/tmp/p","gitBranch":"main"}
    \(filler)
    {"type":"ai-title","aiTitle":"꼬리에 있는 제목","sessionId":"s1"}
    """
    #expect(text.utf8.count > SessionScanner.tailBytes)

    let url = try makeFixture(text)
    let session = try #require(SessionScanner.scan(logPath: url))
    #expect(session.title == "꼬리에 있는 제목")
    #expect(session.cwd == "/tmp/p")
    #expect(session.gitBranch == "main")
}

@Test func 꼬리_읽기는_잘림_여부를_알려준다() throws {
    let small = try makeFixture("한 줄\n")
    #expect(try SessionScanner.readTail(small, bytes: 1024).truncated == false)

    let big = try makeFixture(String(repeating: "가", count: 2000))
    #expect(try SessionScanner.readTail(big, bytes: 128).truncated == true)
}

@Test func 꼬리파싱은_마지막_레코드의_gitBranch를_쓴다() {
    // 앞에서는 main이었지만 마지막 cwd 레코드는 null이다.
    // 세션의 현재 상태는 "git 아님"이므로 nil이 맞다.
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/tmp/p","gitBranch":"main"}
    {"type":"ai-title","aiTitle":"제목","sessionId":"s1"}
    {"type":"assistant","sessionId":"s1","cwd":"/tmp/p","gitBranch":null}
    """
    let fields = SessionScanner.parseTail(Data(text.utf8), dropFirstLine: false)
    #expect(fields.gitBranch == nil)
    #expect(fields.cwd == "/tmp/p")
    #expect(fields.sessionId == "s1")
    #expect(fields.aiTitle == "제목")
}

@Test func 꼬리파싱은_마지막_레코드에_브랜치가_있으면_가져온다() {
    let text = """
    {"type":"user","sessionId":"s1","cwd":"/tmp/p","gitBranch":null}
    {"type":"assistant","sessionId":"s1","cwd":"/tmp/p","gitBranch":"feat/x"}
    """
    let fields = SessionScanner.parseTail(Data(text.utf8), dropFirstLine: false)
    #expect(fields.gitBranch == "feat/x")
}
