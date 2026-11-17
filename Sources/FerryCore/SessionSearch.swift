import Foundation

/// 팝오버 맨 위 검색창의 필터.
///
/// 대상은 이미 메모리에 있는 제목 · 폴더명 · 브랜치뿐이다. 대화 본문은 보지 않는다 —
/// 전체 로그가 수백 MB라 그건 스캔 구조를 바꾸는 별개의 기능이다.
public enum SessionSearch {

    /// 검색어를 공백으로 나눈 단어가 모두(AND) 제목 · 폴더명 · 브랜치 중 어딘가에 있는 세션만 남긴다.
    /// 대소문자는 구분하지 않는다. 폴더명이 맞으면 그 그룹의 세션이 전부 남는다.
    /// 세션이 하나도 안 남는 그룹은 빠진다. 검색어가 비어 있으면 그대로 돌려준다.
    public static func filter(_ projects: [Project], query: String) -> [Project] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return projects }

        return projects.compactMap { project in
            let sessions = project.sessions.filter { session in
                let fields = [session.title, project.name, session.gitBranch ?? ""]
                return terms.allSatisfy { term in
                    fields.contains { $0.range(of: term, options: .caseInsensitive) != nil }
                }
            }
            return sessions.isEmpty ? nil : Project(path: project.path, sessions: sessions)
        }
    }
}
