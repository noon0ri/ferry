import Foundation
import Observation

@Observable
public final class SessionStore {

    public private(set) var projects: [Project] = []

    private let root: URL
    private let scan: @Sendable (URL) -> Session?
    private var cache: [URL: CacheEntry] = [:]
    private let moves: SessionMoveRegistry
    private var inFlight: Task<Void, Never>?

    struct CacheEntry: Sendable {
        let mtime: Date
        let session: Session
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    public init(root: URL = SessionStore.defaultRoot,
                scan: @escaping @Sendable (URL) -> Session? = { SessionScanner.scan(logPath: $0) },
                moves: SessionMoveRegistry = SessionMoveRegistry()) {
        self.root = root
        self.scan = scan
        self.moves = moves
    }

    /// 로그 루트를 훑어 projects를 다시 만든다.
    /// mtime이 바뀌지 않은 파일은 캐시를 재사용한다.
    public func refresh() {
        let result = Self.scanAll(root: root, scan: scan, cache: cache)
        cache = result.cache
        projects = group(result.sessions)
    }

    /// 스캔을 백그라운드에서 돌리고 결과만 main에서 반영한다.
    /// 팝오버가 열릴 때 UI를 막지 않기 위한 경로다.
    @MainActor
    public func refreshAsync() async {
        inFlight?.cancel()
        let task = Task { @MainActor in
            let root = self.root
            let scan = self.scan
            let snapshot = self.cache

            let result = await Task.detached(priority: .userInitiated) {
                SessionStore.scanAll(root: root, scan: scan, cache: snapshot)
            }.value

            guard !Task.isCancelled else { return }
            self.cache = result.cache
            self.projects = group(result.sessions)
        }
        inFlight = task
        await task.value
    }

    /// 스캔 본체. main actor와 무관한 순수 작업이라 어느 스레드에서든 돌 수 있다.
    static func scanAll(root: URL,
                        scan: @Sendable (URL) -> Session?,
                        cache: [URL: CacheEntry]) -> (sessions: [Session], cache: [URL: CacheEntry]) {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], cache)
        }

        var sessions: [Session] = []
        var freshCache: [URL: CacheEntry] = [:]

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
                    freshCache[file] = CacheEntry(mtime: mtime, session: session)
                }
            }
        }

        return (sessions, freshCache)
    }

    /// cwd로 묶고 스펙 §4의 표시 규칙대로 정렬한다.
    ///
    /// 이동을 실행한 세션은 로그의 cwd가 아직 옛 폴더일 수 있다. 사용자가 첫 메시지를
    /// 보내야 Claude Code가 새 cwd를 기록하기 때문이다. 그 사이에도 옮긴 곳으로 보여준다.
    func group(_ sessions: [Session]) -> [Project] {
        Dictionary(grouping: sessions, by: { moves.appliedTarget(for: $0.id) ?? $0.cwd })
            .map { path, group in
                Project(path: path, sessions: group.sorted { $0.modifiedAt > $1.modifiedAt })
            }
            .sorted { $0.latestActivity > $1.latestActivity }
    }
}
