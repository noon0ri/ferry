import SwiftUI
import AppKit
import FerryCore

struct MenuBarView: View {
    @State private var store = SessionStore()
    @State private var expanded: Set<String> = []
    @State private var didSetInitialExpansion = false
    @State private var notice: String?
    @State private var missingPaths: Set<String> = []

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
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 420)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("세션이 없습니다").fontWeight(.medium)
            Text("~/.claude/projects 를 찾지 못했습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
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
            notice = "폴더가 없습니다: \(session.cwd)"
            return
        }
        switch launcher.launch(session) {
        case .launched:
            notice = nil
        case .copiedToClipboard:
            notice = "Terminal 제어 권한이 없어 명령을 복사했습니다"
        }
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

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: session.modifiedAt, relativeTo: Date())
    }
}
