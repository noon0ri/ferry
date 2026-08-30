import Testing
import Foundation
@testable import FerryCore

@Test func 정상_로그에서_모든_필드를_뽑는다() {
    let fields = SessionScanner.parse(sampleLog(), dropFirstLine: false)
    #expect(fields.aiTitle == "Enigma 퍼즐 파이프라인 그룹4 실행")
    #expect(fields.cwd == "/Users/seongbin/Codes/enigma")
    #expect(fields.gitBranch == "main")
    #expect(fields.sessionId == "01292266-bea7-439a-8174-de310dbb1f5f")
    #expect(fields.firstUserPrompt == "handoff.md를 읽어라")
}

@Test func gitBranch가_null이면_nil이다() {
    let fields = SessionScanner.parse(sampleLog(gitBranch: nil), dropFirstLine: false)
    #expect(fields.gitBranch == nil)
    #expect(fields.cwd == "/Users/seongbin/Codes/enigma")
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
