import Foundation

public struct SessionScanner {

    public struct ParsedFields: Equatable, Sendable {
        public var aiTitle: String?
        public var cwd: String?
        public var gitBranch: String?
        public var sessionId: String?
        public var firstUserPrompt: String?
    }

    /// JSON Lines 텍스트에서 필요한 필드만 훑는다.
    /// - Parameter dropFirstLine: 파일 꼬리만 읽어 첫 줄이 잘렸을 수 있을 때 true.
    public static func parse(_ text: String, dropFirstLine: Bool) -> ParsedFields {
        var fields = ParsedFields()
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if dropFirstLine && !lines.isEmpty {
            lines.removeFirst()
        }

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let record = obj as? [String: Any]
            else { continue }  // 손상 라인은 건너뛴다

            if let id = record["sessionId"] as? String {
                fields.sessionId = id
            }
            if let type = record["type"] as? String, type == "ai-title",
               let title = record["aiTitle"] as? String, !title.isEmpty {
                fields.aiTitle = title   // 나중 값이 이긴다
            }
            if let cwd = record["cwd"] as? String, !cwd.isEmpty {
                fields.cwd = cwd
            }
            if let branch = record["gitBranch"] as? String, !branch.isEmpty {
                fields.gitBranch = branch
            }
            if fields.firstUserPrompt == nil,
               let type = record["type"] as? String, type == "user",
               let message = record["message"] as? [String: Any],
               let prompt = extractText(from: message["content"]) {
                fields.firstUserPrompt = prompt
            }
        }
        return fields
    }

    /// content는 문자열이거나 `[{"type":"text","text":...}]` 배열이다.
    private static func extractText(from content: Any?) -> String? {
        var raw: String?
        if let string = content as? String {
            raw = string
        } else if let parts = content as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            raw = texts.joined(separator: " ")
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
