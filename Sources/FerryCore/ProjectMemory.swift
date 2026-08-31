import Foundation

/// 세션이 속한 프로젝트에 딸린 자동 메모리를 들여다본다.
///
/// 메모리는 프로젝트 디렉토리 단위로 쌓인다. 세션을 다른 폴더로 옮기면 cwd가 바뀌고,
/// 그때부터는 새 폴더의 메모리를 읽는다. 옛 메모리는 지워지지 않지만 따라오지도 않는다.
/// 오래 쓴 프로젝트일수록 잃는 것이 크므로, 옮기기 전에 알려주기 위한 정보다.
///
/// 프로젝트 디렉토리는 로그 파일이 있는 곳이다. 디렉토리 이름은 cwd를 인코딩한
/// 것이지만 그 인코딩을 되돌릴 수 없으므로(하이픈이 경로 구분자인지 이름의 일부인지
/// 알 수 없다) 직접 만들지 않고 로그 경로에서 얻는다.
public enum ProjectMemory {

    public static func directory(for session: Session) -> URL {
        session.logPath.deletingLastPathComponent().appendingPathComponent("memory")
    }

    /// 메모리 파일 수. 디렉토리가 없으면 0.
    public static func fileCount(for session: Session) -> Int {
        let dir = directory(for: session)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return 0
        }
        return names.filter { $0.hasSuffix(".md") }.count
    }
}
