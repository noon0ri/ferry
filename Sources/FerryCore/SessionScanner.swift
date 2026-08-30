import Foundation

public struct SessionScanner {

    public struct ParsedFields: Equatable, Sendable {
        /// 사용자가 직접 붙인 이름(`claude -n` 또는 Ferry의 이름 변경).
        /// 자동 생성된 aiTitle보다 우선한다.
        public var customTitle: String?
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
            if let type = record["type"] as? String, type == "custom-title",
               let title = record["customTitle"] as? String, !title.isEmpty {
                fields.customTitle = title
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

    /// 꼬리에서 필요한 두 줄만 바이트 검색으로 찾아 그 줄만 파싱한다.
    /// Swift String은 grapheme cluster 인지 처리 때문에 256KB를 문자열로 만들어
    /// split 하는 것만으로도 비싸다. 그래서 String을 아예 만들지 않는다.
    /// JSONSerialization은 Data를 직접 받으므로 문자열 변환이 필요 없다.
    static func parseTail(_ data: Data, dropFirstLine: Bool) -> ParsedFields {
        var fields = ParsedFields()
        let newline = UInt8(0x0A)

        var region = data[...]
        if dropFirstLine, let firstNL = region.firstIndex(of: newline) {
            region = region[region.index(after: firstNL)...]
        }

        /// pattern을 뒤에서부터 찾아, 그 줄 전체를 잘라 돌려준다.
        /// 파싱에 실패하면(마지막 줄이 쓰이는 중이라 잘렸을 수 있다) 그 앞 줄로 물러나 다시 시도한다.
        func lastRecord(containing pattern: String) -> [String: Any]? {
            let needle = Data(pattern.utf8)
            var search = region
            for _ in 0..<3 {
                guard let hit = search.range(of: needle, options: .backwards) else { return nil }
                let lineStart = search[search.startIndex..<hit.lowerBound]
                    .lastIndex(of: newline).map { search.index(after: $0) } ?? search.startIndex
                let lineEnd = search[hit.upperBound...]
                    .firstIndex(of: newline) ?? search.endIndex

                if let obj = try? JSONSerialization.jsonObject(with: Data(search[lineStart..<lineEnd])),
                   let record = obj as? [String: Any] {
                    return record
                }
                guard lineStart > search.startIndex else { return nil }
                search = search[search.startIndex..<lineStart]   // 이 줄은 버리고 앞쪽에서 재시도
            }
            return nil
        }

        if let record = lastRecord(containing: "\"custom-title\""),
           (record["type"] as? String) == "custom-title",
           let title = record["customTitle"] as? String, !title.isEmpty {
            fields.customTitle = title
        }

        if let record = lastRecord(containing: "\"ai-title\""),
           (record["type"] as? String) == "ai-title",
           let title = record["aiTitle"] as? String, !title.isEmpty {
            fields.aiTitle = title
        }

        // gitBranch는 마지막 cwd 레코드의 값을 그대로 쓴다 — null이면 nil이다.
        // 세션의 "현재" 상태를 나타내는 값이므로 최신 레코드가 이긴다.
        // 앞쪽에서 본 브랜치명을 들고 오면 폴더가 git 저장소가 아니게 된 뒤에도
        // 낡은 값을 보고하게 된다. 정방향 parse()의 "마지막 non-null" 동작과는
        // 여기서 의도적으로 갈린다.
        if let record = lastRecord(containing: "\"cwd\""),
           let cwd = record["cwd"] as? String, !cwd.isEmpty {
            fields.cwd = cwd
            fields.sessionId = record["sessionId"] as? String
            fields.gitBranch = (record["gitBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
    /// - Returns: 읽은 바이트와, 앞이 잘렸는지 여부.
    public static func readTail(_ url: URL, bytes: Int = tailBytes) throws -> (data: Data, truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let truncated = size > UInt64(bytes)
        let offset = truncated ? size - UInt64(bytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (data, truncated)
    }

    /// jsonl 파일 하나를 Session으로 바꾼다. cwd를 못 찾으면 nil.
    public static func scan(logPath: URL) -> Session? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else { return nil }

        guard let tail = try? readTail(logPath) else { return nil }
        var fields = tail.truncated
            ? parseTail(tail.data, dropFirstLine: true)
            : parse(String(decoding: tail.data, as: UTF8.self), dropFirstLine: false)

        // 꼬리에서 제목이나 cwd를 못 찾았고 파일이 잘렸다면 전체를 다시 읽는다.
        if tail.truncated && (fields.aiTitle == nil || fields.cwd == nil) {
            if let whole = try? String(contentsOf: logPath, encoding: .utf8) {
                fields = parse(whole, dropFirstLine: false)
            }
        }

        guard let cwd = fields.cwd else { return nil }

        let id = fields.sessionId
            ?? logPath.deletingPathExtension().lastPathComponent
        // 사용자가 붙인 이름이 자동 생성 제목을 이긴다.
        let title = fields.customTitle
            ?? fields.aiTitle
            ?? fields.firstUserPrompt
            ?? String(id.prefix(8))

        return Session(id: id, logPath: logPath, cwd: cwd,
                       title: title, gitBranch: fields.gitBranch,
                       modifiedAt: modifiedAt)
    }
}
