import Foundation
import Observation

@Observable
public final class SessionStore {

    public private(set) var projects: [Project] = []

    private let root: URL
    private let scan: @Sendable (URL) -> Session?
    private var cache: [URL: (mtime: Date, session: Session)] = [:]

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    public init(root: URL = SessionStore.defaultRoot,
                scan: @escaping @Sendable (URL) -> Session? = { SessionScanner.scan(logPath: $0) }) {
        self.root = root
        self.scan = scan
    }

    /// 로그 루트를 훑어 projects를 다시 만든다.
    /// mtime이 바뀌지 않은 파일은 캐시를 재사용한다.
    public func refresh() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            projects = []
            return
        }

        var sessions: [Session] = []
        var freshCache: [URL: (mtime: Date, session: Session)] = [:]

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            // depth 1만 본다. <세션id>/subagents/ 는 자연히 제외된다.
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate

                if let mtime, let cached = cache[file], cached.mtime == mtime {
                    sessions.append(cached.session)
                    freshCache[file] = cached
                    continue
                }

                guard let session = scan(file) else { continue }
                sessions.append(session)
                if let mtime {
                    freshCache[file] = (mtime, session)
                }
            }
        }

        cache = freshCache
        projects = Self.group(sessions)
    }

    /// cwd로 묶고 스펙 §4의 표시 규칙대로 정렬한다.
    static func group(_ sessions: [Session]) -> [Project] {
        Dictionary(grouping: sessions, by: \.cwd)
            .map { path, group in
                Project(path: path, sessions: group.sorted { $0.modifiedAt > $1.modifiedAt })
            }
            .sorted { $0.latestActivity > $1.latestActivity }
    }
}
