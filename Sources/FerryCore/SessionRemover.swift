import Foundation

/// 세션을 디스크에서 치운다.
///
/// Ferry는 그 외 모든 곳에서 `~/.claude/projects`를 읽기만 한다. 여기가 유일한 예외이며,
/// 그래서 제거 대상을 좁게 못박는다. 세션 하나는 두 가지로 이루어진다.
///
///   <프로젝트디렉토리>/<세션id>.jsonl     대화 로그
///   <프로젝트디렉토리>/<세션id>/          서브에이전트 로그 (실측상 로그의 10~30배)
///
/// 같은 디렉토리에 있는 `memory/`는 세션이 아니라 프로젝트 메모리다. 절대 대상이 아니다.
public struct SessionRemover {

    public enum RemovalError: Error, Equatable {
        /// 세션 로그로 보이지 않는 경로. 방어적으로 거부한다.
        case notASessionLog(URL)
        /// 세션이 아닌 보호 대상 디렉토리.
        case protectedPath(URL)
    }

    private let move: (URL) throws -> Void

    /// - Parameter move: 경로 하나를 치우는 동작. 기본값은 휴지통 이동이며,
    ///   테스트는 임시 폴더로 옮기는 구현을 주입한다.
    public init(move: @escaping (URL) throws -> Void = SessionRemover.trash) {
        self.move = move
    }

    /// macOS 휴지통으로 옮긴다. 같은 볼륨 안 이동이라 용량과 무관하게 즉시 끝나고,
    /// 잘못 지웠을 때 Finder에서 되돌릴 수 있다.
    public static func trash(_ url: URL) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }

    /// 세션의 로그와 서브에이전트 디렉토리를 치운다.
    public func remove(_ session: Session) throws {
        let log = session.logPath
        guard log.pathExtension == "jsonl" else {
            throw RemovalError.notASessionLog(log)
        }

        // 서브에이전트 디렉토리는 로그와 이름이 같은 형제 디렉토리다.
        // logPath에서 확장자만 떼어 얻으므로 다른 경로가 끼어들 여지가 없다.
        let subagents = log.deletingPathExtension()
        guard subagents.lastPathComponent != "memory" else {
            throw RemovalError.protectedPath(subagents)
        }

        try move(log)

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: subagents.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            try move(subagents)
        }
    }

    /// 확인 대화상자에 보여줄 용량. 로그와 서브에이전트를 합친다.
    /// 서브에이전트 쪽이 대부분을 차지하므로 로그 크기만 보여주면 오해를 준다.
    public static func totalSize(of session: Session) -> Int64 {
        let fm = FileManager.default
        var total = fileSize(session.logPath)

        let subagents = session.logPath.deletingPathExtension()
        if let walker = fm.enumerator(at: subagents,
                                      includingPropertiesForKeys: [.fileSizeKey],
                                      options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                total += fileSize(url)
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
