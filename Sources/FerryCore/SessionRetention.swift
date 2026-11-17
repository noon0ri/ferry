import Foundation

/// Claude Code는 `cleanupPeriodDays`(기본 30일)가 지난 세션 로그를 지운다. 세션별 예외는 없다.
/// 즐겨찾기 세션까지 조용히 사라졌던 일이 있어, 언제 사라질지 미리 보여주기 위한 계산이다.
///
/// 무엇을 기준으로 "오래됐다"고 보는지는 문서에 없다. 로그 수정 시각으로 본다(추정).
/// 남아 있는 로그 중 가장 오래된 것이 29일 전이었던 관찰과는 맞는다.
public enum SessionRetention {

    public static let defaultPeriodDays = 30
    /// 삭제 며칠 전부터 표시하는가. 주 1회 쓰는 세션도 한 번은 보고 지나가도록.
    public static let warningDays = 7

    public static var userSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// 사용자 설정의 `cleanupPeriodDays`. 없거나 읽을 수 없거나 1 미만이면 기본값.
    /// shortcut: 사용자 설정만 본다. 프로젝트·관리형 설정이 덮어쓰면 틀린다 — 그런 설정을 쓰게 되면 함께 읽는다.
    public static func periodDays(settings: URL = userSettings) -> Int {
        guard let data = try? Data(contentsOf: settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = object["cleanupPeriodDays"] as? Int, days >= 1
        else { return defaultPeriodDays }
        return days
    }

    /// 삭제까지 남은 날(올림). 표시할 범위(`warningDays`)보다 멀면 nil, 이미 지났으면 0.
    /// 정리는 Claude Code를 실행할 때 돌므로 기한이 지나도 한동안 남아 있을 수 있다.
    public static func daysUntilDeletion(_ session: Session, periodDays: Int,
                                         now: Date = Date()) -> Int? {
        let deadline = session.modifiedAt.addingTimeInterval(TimeInterval(periodDays) * 86_400)
        let days = Int((deadline.timeIntervalSince(now) / 86_400).rounded(.up))
        return days <= warningDays ? max(days, 0) : nil
    }
}
