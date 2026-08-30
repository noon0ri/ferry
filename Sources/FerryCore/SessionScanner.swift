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

    public static let tailBytes = 262_144

    /// 파일 끝에서 최대 `bytes`만큼 읽는다.
    /// - Returns: 읽은 텍스트와, 앞이 잘렸는지 여부.
    public static func readTail(_ url: URL, bytes: Int = tailBytes) throws -> (text: String, truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let truncated = size > UInt64(bytes)
        let offset = truncated ? size - UInt64(bytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (String(decoding: data, as: UTF8.self), truncated)
    }

    /// jsonl 파일 하나를 Session으로 바꾼다. cwd를 못 찾으면 nil.
    public static func scan(logPath: URL) -> Session? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else { return nil }

        guard let tail = try? readTail(logPath) else { return nil }
        var fields = parse(tail.text, dropFirstLine: tail.truncated)

        // 꼬리에서 제목이나 cwd를 못 찾았고 파일이 잘렸다면 전체를 다시 읽는다.
        if tail.truncated && (fields.aiTitle == nil || fields.cwd == nil) {
            if let whole = try? String(contentsOf: logPath, encoding: .utf8) {
                fields = parse(whole, dropFirstLine: false)
            }
        }

        guard let cwd = fields.cwd else { return nil }

        let id = fields.sessionId
            ?? logPath.deletingPathExtension().lastPathComponent
        let title = fields.aiTitle
            ?? fields.firstUserPrompt
            ?? String(id.prefix(8))

        return Session(id: id, logPath: logPath, cwd: cwd,
                       title: title, gitBranch: fields.gitBranch,
                       modifiedAt: modifiedAt)
    }
}
