import SwiftUI
import AppKit
import FerryCore

struct MenuBarView: View {
    private enum LoadState { case loading, loaded }

    @State private var store = SessionStore()
    @State private var expanded: Set<String> = []
    @State private var didSetInitialExpansion = false
    @State private var notice: String?
    @State private var noticeSetAt: Date?
    @State private var missingPaths: Set<String> = []
    @State private var loadState: LoadState = .loading

    private let launcher = TerminalLauncher()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.projects.isEmpty {
                emptyState
            } else {
                list
            }
            footer
        }
        .frame(width: 320)
        .task {
            // .task는 뷰 생명주기당 한 번만 돈다. MenuBarExtra(.window)는 팝오버를
            // 닫아도 뷰를 버리지 않으므로, 한 번만 스캔하면 목록이 그대로 굳는다.
            // 웜 스캔이 ~1ms라 주기적으로 다시 읽어도 비용이 없다.
            while !Task.isCancelled {
                await store.refreshAsync()
                updateMissingPaths()
                applyInitialExpansion()
                loadState = .loaded
                clearStaleNotice()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.projects) { project in
                    DisclosureGroup(isExpanded: binding(for: project)) {
                        ForEach(project.sessions) { session in
                            SessionRow(session: session,
                                       exists: !missingPaths.contains(session.cwd)) { open(session) }
                        }
                    } label: {
                        HStack {
                            Text(project.name).fontWeight(.medium)
                            Text("(\(project.sessions.count))")
                                .foregroundStyle(.secondary)
                            Spacer()   // 행 끝까지 채워 클릭 영역을 넓힌다
                        }
                        .contentShape(Rectangle())   // 빈 공간도 히트 테스트 대상
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                binding(for: project).wrappedValue.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(height: listHeight)
    }

    /// ScrollView는 세로 방향 고유 크기가 없다. maxHeight만 주면 "이만큼까지 허용"일 뿐
    /// "이만큼 달라"가 아니어서, 콘텐츠에 맞춰 크기가 정해지는 MenuBarExtra 창 안에서는
    /// 최소 크기로 쪼그라든다(행 텍스트가 세로로 잘리는 증상). 그래서 높이를 계산해 명시한다.
    ///
    /// 펼쳐진 그룹만큼 늘어나고, 화면 높이를 넘지 않는다.
    private var listHeight: CGFloat {
        var needed: CGFloat = 16                       // LazyVStack 위아래 여백
        for project in store.projects {
            needed += 26                               // 그룹 헤더 한 줄
            if expanded.contains(project.id) {
                needed += CGFloat(project.sessions.count) * 39   // 세션 행(2줄)
            }
        }
        let screenCap = (NSScreen.main?.visibleFrame.height ?? 800) - 140
        return min(max(needed, 160), min(900, screenCap))
    }

    /// projects.isEmpty는 "첫 스캔이 아직 안 끝남"과 "스캔은 끝났는데 세션이 없음"을
    /// 구분하지 못한다. loadState로 그 둘을 가른다.
    private var emptyState: some View {
        Group {
            switch loadState {
            case .loading:
                VStack(alignment: .leading, spacing: 6) {
                    Text("불러오는 중…").fontWeight(.medium)
                }
                .padding(16)
            case .loaded:
                if FileManager.default.fileExists(atPath: SessionStore.defaultRoot.path) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("세션이 없습니다").fontWeight(.medium)
                        Text("Claude Code 세션을 찾지 못했습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("세션이 없습니다").fontWeight(.medium)
                        Text("~/.claude/projects 를 찾지 못했습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("새로고침") {
                    Task {
                        await store.refreshAsync()
                        updateMissingPaths()
                    }
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(12)
    }

    private func binding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(project.id) },
            set: { isOn in
                if isOn { expanded.insert(project.id) } else { expanded.remove(project.id) }
            }
        )
    }

    /// 스펙 §4: 기본 접힘, 최상단 1개만 펼침. 앱 실행 중에는 사용자 선택을 유지한다.
    private func applyInitialExpansion() {
        guard !didSetInitialExpansion, let first = store.projects.first else { return }
        expanded = [first.id]
        didSetInitialExpansion = true
    }

    /// cwd 존재 여부는 새로고침 시점에 한 번만 확인한다.
    /// 뷰 body에서 확인하면 스크롤·호버 같은 무관한 재렌더마다 파일시스템을 두드리게 된다.
    private func updateMissingPaths() {
        let paths = Set(store.projects.flatMap(\.sessions).map(\.cwd))
        missingPaths = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
    }

    private func open(_ session: Session) {
        // 클릭 시점에 직접 확인한다. 마지막 새로고침 이후 폴더가 사라졌을 수 있고,
        // 클릭 한 번에 stat 한 번은 렌더 경로와 달리 비용이 아니다.
        // missingPaths는 렌더링(흐리게 표시) 전용으로만 쓴다.
        guard FileManager.default.fileExists(atPath: session.cwd) else {
            setNotice("폴더가 없습니다: \(session.cwd)")
            return
        }
        switch launcher.launch(session) {
        case .launched:
            notice = nil
            noticeSetAt = nil
        case .copiedToClipboard:
            setNotice("Terminal을 열지 못해 명령을 클립보드에 복사했습니다 (자동화 권한을 확인해 보세요)")
        }
    }

    private func setNotice(_ text: String) {
        notice = text
        noticeSetAt = Date()
    }

    /// notice는 방치하면 영원히 떠 있는다. 10초 지나면 폴링 루프에서 지운다.
    private func clearStaleNotice() {
        guard let noticeSetAt, Date().timeIntervalSince(noticeSetAt) > 10 else { return }
        notice = nil
        self.noticeSetAt = nil
    }
}

private struct SessionRow: View {
    let session: Session
    let exists: Bool
    let action: () -> Void

    private var isActive: Bool {
        Date().timeIntervalSince(session.modifiedAt) < 60
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(relativeTime)
                        if let branch = session.gitBranch {
                            Text("· \(branch)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .opacity(exists ? 1 : 0.45)
        .help(session.cwd)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: session.modifiedAt, relativeTo: Date())
    }
}
