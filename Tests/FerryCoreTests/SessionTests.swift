import Testing
import Foundation
@testable import FerryCore

@Test func 프로젝트명은_경로_마지막_성분이다() {
    #expect(Project.displayName(for: "/Users/me/Codes/alpha") == "alpha")
}

@Test func 프로젝트명은_공백_포함_이름을_보존한다() {
    #expect(Project.displayName(for: "/Users/me/Codes/my project") == "my project")
}

@Test func 프로젝트명은_끝의_슬래시를_무시한다() {
    #expect(Project.displayName(for: "/Users/me/Codes/beta/") == "beta")
}

@Test func 최근활동은_세션들_중_최댓값이다() {
    let old = Date(timeIntervalSince1970: 1000)
    let new = Date(timeIntervalSince1970: 2000)
    let project = Project(path: "/tmp/p", sessions: [
        Session(id: "a", logPath: URL(fileURLWithPath: "/tmp/a.jsonl"),
                cwd: "/tmp/p", title: "A", gitBranch: nil, modifiedAt: old),
        Session(id: "b", logPath: URL(fileURLWithPath: "/tmp/b.jsonl"),
                cwd: "/tmp/p", title: "B", gitBranch: "main", modifiedAt: new),
    ])
    #expect(project.latestActivity == new)
}

@Test func 세션이_없는_프로젝트의_최근활동은_먼_과거다() {
    let project = Project(path: "/tmp/p", sessions: [])
    #expect(project.latestActivity == .distantPast)
}
