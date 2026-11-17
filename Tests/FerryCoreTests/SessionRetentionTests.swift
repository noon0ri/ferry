import Testing
import Foundation
@testable import FerryCore

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func session(modifiedDaysAgo days: Double) -> Session {
    Session(id: "s", logPath: URL(fileURLWithPath: "/tmp/s.jsonl"), cwd: "/x",
            title: "t", gitBranch: nil, modifiedAt: now.addingTimeInterval(-days * day))
}

private func left(_ daysAgo: Double, period: Int = 30) -> Int? {
    SessionRetention.daysUntilDeletion(session(modifiedDaysAgo: daysAgo), periodDays: period, now: now)
}

@Test func 경고_범위_밖이면_표시하지_않는다() {
    #expect(left(0) == nil)
    #expect(left(22.5) == nil)   // 7.5일 남음
}

@Test func 경고_범위_안이면_남은_날을_올림한다() {
    #expect(left(23) == 7)
    #expect(left(29.5) == 1)     // 반나절 남아도 "1일 뒤"
}

@Test func 기한이_지났으면_0이다() {
    #expect(left(30) == 0)
    #expect(left(45) == 0)
}

@Test func 보존_기간을_따른다() {
    #expect(left(23, period: 90) == nil)
    #expect(left(85, period: 90) == 5)
}

@Test func 설정에서_보존_기간을_읽는다() throws {
    let url = try makeFixture(#"{"cleanupPeriodDays": 90, "hooks": {}}"#, name: "settings.json")
    #expect(SessionRetention.periodDays(settings: url) == 90)
}

@Test func 설정이_없거나_이상하면_기본값이다() throws {
    #expect(SessionRetention.periodDays(settings: URL(fileURLWithPath: "/nonexistent/settings.json")) == 30)
    #expect(SessionRetention.periodDays(settings: try makeFixture(#"{"hooks": {}}"#, name: "settings.json")) == 30)
    #expect(SessionRetention.periodDays(settings: try makeFixture(#"{"cleanupPeriodDays": 0}"#, name: "settings.json")) == 30)
    #expect(SessionRetention.periodDays(settings: try makeFixture("not json", name: "settings.json")) == 30)
}
