import Foundation

/// 임시 디렉토리에 jsonl 픽스처를 만들고 URL을 돌려준다.
func makeFixture(_ contents: String, name: String = "\(UUID().uuidString).jsonl") throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ferry-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// 실제 로그와 같은 모양의 최소 세션 본문.
func sampleLog(sessionId: String = "01292266-bea7-439a-8174-de310dbb1f5f",
               cwd: String = "/Users/me/Codes/alpha",
               gitBranch: String? = "main",
               title: String? = "Enigma 퍼즐 파이프라인 그룹4 실행",
               prompt: String = "handoff.md를 읽어라") -> String {
    let branchField = gitBranch.map { "\"\($0)\"" } ?? "null"
    var lines = [
        """
        {"type":"user","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":\(branchField),"timestamp":"2026-08-23T03:50:11.142Z","message":{"role":"user","content":"\(prompt)"}}
        """,
        """
        {"type":"assistant","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":\(branchField),"timestamp":"2026-08-23T03:50:20.000Z"}
        """,
    ]
    if let title {
        lines.append("""
        {"type":"ai-title","aiTitle":"\(title)","sessionId":"\(sessionId)"}
        """)
    }
    return lines.joined(separator: "\n") + "\n"
}
