import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public let logPath: URL
    public let cwd: String
    public let title: String
    public let gitBranch: String?
    public let modifiedAt: Date

    public init(id: String, logPath: URL, cwd: String,
                title: String, gitBranch: String?, modifiedAt: Date) {
        self.id = id
        self.logPath = logPath
        self.cwd = cwd
        self.title = title
        self.gitBranch = gitBranch
        self.modifiedAt = modifiedAt
    }
}

public struct Project: Identifiable, Equatable, Sendable {
    public let path: String
    public var sessions: [Session]

    public var id: String { path }
    public var name: String { Project.displayName(for: path) }
    public var latestActivity: Date {
        sessions.map(\.modifiedAt).max() ?? .distantPast
    }

    public init(path: String, sessions: [Session]) {
        self.path = path
        self.sessions = sessions
    }

    /// 경로의 마지막 성분을 표시 이름으로 쓴다.
    /// 디렉토리명(`-Users-seongbin-Codes-...`) 디코딩은 불가능하므로
    /// 반드시 로그 안의 `cwd` 값을 넘겨야 한다.
    public static func displayName(for path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return (trimmed as NSString).lastPathComponent
    }
}
