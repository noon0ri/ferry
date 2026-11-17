import Testing
import Foundation
@testable import FerryCore

private func session(_ id: String, _ title: String, branch: String? = nil) -> Session {
    Session(id: id, logPath: URL(fileURLWithPath: "/tmp/\(id).jsonl"), cwd: "/x",
            title: title, gitBranch: branch, modifiedAt: Date())
}

private let projects = [
    Project(path: "/Codes/lab2", sessions: [
        session("a", "웹 기반 인터랙티브 3D 아이콘 세트 만들기", branch: "main"),
        session("b", "Meshy AI 도입"),
    ]),
    Project(path: "/Codes/ferry", sessions: [
        session("c", "검색 기능 추가", branch: "feature/search"),
    ]),
]

private func ids(_ result: [Project]) -> [String] {
    result.flatMap(\.sessions).map(\.id)
}

@Test func 빈_검색어는_그대로_돌려준다() {
    #expect(SessionSearch.filter(projects, query: "") == projects)
    #expect(SessionSearch.filter(projects, query: "   ") == projects)
}

@Test func 제목_부분문자열을_대소문자_없이_찾는다() {
    #expect(ids(SessionSearch.filter(projects, query: "meshy")) == ["b"])
    #expect(ids(SessionSearch.filter(projects, query: "아이콘")) == ["a"])
}

@Test func 단어는_모두_들어_있어야_한다() {
    #expect(ids(SessionSearch.filter(projects, query: "3d 아이콘")) == ["a"])
    #expect(ids(SessionSearch.filter(projects, query: "3d 검색")).isEmpty)
}

@Test func 단어는_서로_다른_필드에_있어도_된다() {
    // 제목의 "아이콘"과 브랜치의 "main"
    #expect(ids(SessionSearch.filter(projects, query: "아이콘 main")) == ["a"])
}

@Test func 브랜치로_찾는다() {
    #expect(ids(SessionSearch.filter(projects, query: "feature/")) == ["c"])
}

@Test func 폴더명이_맞으면_그룹_세션이_전부_남는다() {
    #expect(ids(SessionSearch.filter(projects, query: "LAB2")) == ["a", "b"])
}

@Test func 폴더명은_전체_경로가_아니라_마지막_성분만_본다() {
    #expect(SessionSearch.filter(projects, query: "Codes").isEmpty)
}

@Test func 맞는_세션이_없는_그룹은_빠진다() {
    #expect(SessionSearch.filter(projects, query: "검색").map(\.path) == ["/Codes/ferry"])
}
