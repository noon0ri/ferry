import Foundation

/// 세션에 사용자 이름을 붙인다.
///
/// Claude Code가 `claude -n`으로 쓰는 것과 같은 형식(`custom-title` 레코드)을 로그 끝에 덧붙인다.
/// 그래서 Ferry에서 바꾼 이름이 `claude --resume` 목록과 터미널 타이틀에도 그대로 나타난다.
/// 이름이 두 군데로 갈라지지 않는 대신, Ferry가 로그 파일에 쓰는 유일한 지점이 된다.
public struct SessionRenamer {

    public enum RenameError: Error, Equatable {
        case notASessionLog(URL)
        case emptyName
    }

    public init() {}

    public func rename(_ session: Session, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RenameError.emptyName }
        guard session.logPath.pathExtension == "jsonl" else {
            throw RenameError.notASessionLog(session.logPath)
        }

        let record: [String: Any] = [
            "type": "custom-title",
            "customTitle": trimmed,
            "sessionId": session.id,
        ]
        var line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        line.append(0x0A)

        // 마지막 바이트를 읽어야 하므로 쓰기 전용(forWritingTo)이 아니라 읽기·쓰기로 연다.
        let handle = try FileHandle(forUpdating: session.logPath)
        defer { try? handle.close() }

        // 마지막 줄이 개행으로 끝나지 않았다면(세션이 쓰이는 중일 수 있다) 먼저 개행을 넣는다.
        // 그러지 않으면 우리 레코드가 앞줄에 이어붙어 두 줄 다 깨진다.
        let size = try handle.seekToEnd()
        if size > 0 {
            try handle.seek(toOffset: size - 1)
            let last = try handle.read(upToCount: 1) ?? Data()
            if last.first != 0x0A {
                line.insert(0x0A, at: 0)
            }
            try handle.seekToEnd()
        }

        try handle.write(contentsOf: line)
    }
}
