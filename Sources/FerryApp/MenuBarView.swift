import SwiftUI
import AppKit
import FerryCore

/// 패키지 타깃의 문자열은 Bundle.main이 아니라 모듈 번들에 있다.
/// 시스템 로케일에 따라 en/ko가 선택된다.
private func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .module)
}
private func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

struct MenuBarView: View {
    private enum LoadState { case loading, loaded }

    private static let moveRegistry = SessionMoveRegistry()
    @State private var store = SessionStore(moves: MenuBarView.moveRegistry)
    @State private var expanded: Set<String> = []
    @State private var didSetInitialExpansion = false
    @State private var notice: String?
    @State private var noticeSetAt: Date?
    @State private var missingPaths: Set<String> = []
    @State private var liveSessions: Set<String> = []
    @State private var pendingMoves: [String: String] = [:]
    @State private var hiddenIds: Set<String> = []
    /// 숨긴 세션을 되돌아보는 모드. 삭제는 여기서만 꺼낼 수 있다.
    @State private var showingHidden = false
    @State private var favoriteIds: Set<String> = []
    @State private var favoritesExpanded = true
    @State private var loadState: LoadState = .loading
    @State private var pendingDelete: Session?
    @State private var pendingRename: Session?
    @State private var hoveredProject: String?
    @State private var renameText: String = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    /// ↑↓로 고른 행. 같은 세션이 즐겨찾기와 그룹 양쪽에 나오므로 세션 id가 아니라 행 키로 가리킨다.
    @State private var selectedRow: String?
    @State private var keyMonitor: Any?

    private let remover = SessionRemover()
    private let renamer = SessionRenamer()

    private let launcher = TerminalLauncher()
    private let registry = SessionTerminalRegistry()
    private var moves: SessionMoveRegistry { MenuBarView.moveRegistry }
    private let hides = SessionHideRegistry()
    private let favorites = SessionFavoriteRegistry()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            if visibleProjects.isEmpty && !isSearching {
                emptyState
            } else {
                list
            }
            if let session = pendingRename {
                renamePanel(session)
            } else if let session = pendingDelete {
                deleteConfirmation(session)
            } else {
                footer
            }
        }
        .frame(width: 320)
        .background(GeometryReader { WindowHeightFitter(height: $0.size.height) })
        // 창이 내용 높이를 따라잡기 전 한 박자 동안 SwiftUI는 내용을 세로 중앙에 둔다.
        // 위아래로 튀어 보이므로 위쪽에 붙여, 그 사이에도 아래쪽만 바뀌게 한다.
        .frame(maxHeight: .infinity, alignment: .top)
        // 창은 높이가 바뀌는 즉시 맞춰진다(WindowHeightFitter). 그 안의 배치가 애니메이션되면
        // 검색창과 푸터가 옛 자리에서 미끄러져 움찔거린다. 높이가 바뀔 때는 전부 한 번에 바꾼다.
        .animation(nil, value: listHeight)
        .onAppear {
            installKeyMonitor()
            searchFieldFocused = true
        }
        // 뷰는 팝오버를 닫아도 남으므로 onAppear는 다시 열 때 돌지 않는다.
        // 창의 키 상태로 열고 닫힘을 안다 — 닫히면 검색을 비우고, 열리면 바로 타이핑할 수 있게 한다.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            resetSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if pendingRename == nil { searchFieldFocused = true }
        }
        .task {
            // .task는 뷰 생명주기당 한 번만 돈다. MenuBarExtra(.window)는 팝오버를
            // 닫아도 뷰를 버리지 않으므로, 한 번만 스캔하면 목록이 그대로 굳는다.
            // 웜 스캔이 ~1ms라 주기적으로 다시 읽어도 비용이 없다.
            while !Task.isCancelled {
                await store.refreshAsync()
                updateMissingPaths()
                updateLiveSessions()
                updatePendingMoves()
                updateHidden()
                updateFavorites()
                applyInitialExpansion()
                loadState = .loaded
                clearStaleNotice()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onSubmit(openSelectedRow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: searchText) {
            // 타이핑하고 바로 Enter로 갈 수 있게 첫 결과를 고른다.
            selectedRow = isSearching ? navigableRows.first?.key : nil
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if visibleProjects.isEmpty {
                        Text(L("search.noResults"))
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    // 자주 돌아가는 세션은 그룹을 펼치지 않고 바로 닿아야 한다.
                    // 원래 그룹에도 그대로 남는다 — Finder 사이드바나 북마크와 같은 방식.
                    if !showingHidden && !favoriteSessions.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { favoritesShown },
                            set: { favoritesExpanded = $0 }
                        )) {
                            ForEach(favoriteSessions) { sessionRow($0, inFavorites: true) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(L("favorites.title")).fontWeight(.medium)
                                Text("(\(favoriteSessions.count))")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .background(selectionBackground(Self.favoritesHeaderKey))
                            .id(Self.favoritesHeaderKey)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { favoritesExpanded.toggle() }
                            }
                        }
                        .padding(.horizontal, 12)
                        Divider().padding(.horizontal, 12).padding(.vertical, 2)
                    }

                    ForEach(visibleProjects) { project in
                        DisclosureGroup(isExpanded: binding(for: project)) {
                            ForEach(project.sessions) { sessionRow($0, inFavorites: false) }
                        } label: {
                            HStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(project.name).fontWeight(.medium)
                                    Text("(\(project.sessions.count))")
                                        .foregroundStyle(.secondary)
                                    Spacer()   // 이름 오른쪽 빈 공간까지 접기 영역
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        binding(for: project).wrappedValue.toggle()
                                    }
                                }
                                // 버튼을 Spacer 뒤에 두고 탭 제스처는 앞쪽 HStack에만 건다.
                                // 라벨 전체에 제스처를 걸면 + 클릭이 접기/펼치기까지 발동시킨다.
                                //
                                // 호버할 때 버튼을 끼워 넣으면 그때마다 이름이 밀린다.
                                // 자리는 항상 차지하게 두고 보이기만 바꾼다.
                                Button {
                                    newSession(in: project)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L("action.newSession"))
                                .opacity(hoveredProject == project.id ? 1 : 0)
                                .allowsHitTesting(hoveredProject == project.id)
                            }
                            .contentShape(Rectangle())   // 빈 공간도 히트 테스트 대상
                            .background(selectionBackground(headerKey(project)))
                            .id(headerKey(project))
                            .onHover { inside in
                                hoveredProject = inside ? project.id : nil
                            }
                            .contextMenu {
                                Button(L("action.newSession")) { newSession(in: project) }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: listHeight)
            .onChange(of: selectedRow) {
                if let selectedRow { proxy.scrollTo(selectedRow) }
            }
        }
    }

    /// 세션 행 하나. 즐겨찾기 섹션과 그룹 양쪽에서 같은 것을 쓴다.
    @ViewBuilder
    private func sessionRow(_ session: Session, inFavorites: Bool) -> some View {
        let key = rowKey(session, inFavorites: inFavorites)
        SessionRow(session: session,
                   exists: !missingPaths.contains(session.cwd),
                   hasTerminal: liveSessions.contains(session.id),
                   movingTo: pendingMoves[session.id],
                   // 즐겨찾기 섹션 안에서는 섹션 자체가 그것을 말하므로 별표를 붙이지 않는다.
                   isFavorite: !inFavorites && favoriteIds.contains(session.id),
                   isSelected: selectedRow == key,
                   memoryCount: ProjectMemory.fileCount(for: session)) { open(session) }
            .id(key)
            .contextMenu {
                if showingHidden {
                    // 숨긴 것을 되돌아보는 자리. 삭제는 여기서만 나온다.
                    Button(L("action.reveal")) {
                        hides.reveal(session.id)
            favorites.remove(session.id)
                        updateHidden()
                        updateFavorites()
                    }
                    Divider()
                    Button(L("action.deleteSession"), role: .destructive) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                            pendingRename = nil
                            pendingDelete = session
                        }
                    }
                } else {
                    Button(favoriteIds.contains(session.id)
                           ? L("action.unfavorite") : L("action.favorite")) {
                        favorites.toggle(session.id)
                        withAnimation(.easeInOut(duration: 0.15)) { updateFavorites() }
                    }
                    Menu(L("action.moveTo")) {
                        ForEach(store.projects.filter { $0.path != session.cwd }) { other in
                            Button(other.name) { scheduleMove(session, to: other.path) }
                        }
                        // Ferry는 이미 세션이 있는 폴더만 안다. 아직 세션이 없는
                        // 폴더로는 목록만으로 옮길 수 없으므로 직접 고르게 한다.
                        Divider()
                        Button(L("move.chooseFolder")) { chooseFolder(for: session) }
                    }
                    if pendingMoves[session.id] != nil {
                        Button(L("move.cancel")) {
                            moves.cancel(session.id)
                            updatePendingMoves()
                        }
                    }
                    Divider()
                    Button(L("action.renameSession")) {
                        renameText = session.title
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                            pendingDelete = nil
                            pendingRename = session
                        }
                    }
                    Button(L("action.hide")) {
                        hides.hide(session.id)
                        updateHidden()
                    }
                }
            }
    }

    /// ScrollView는 세로 방향 고유 크기가 없다. maxHeight만 주면 "이만큼까지 허용"일 뿐
    /// "이만큼 달라"가 아니어서, 콘텐츠에 맞춰 크기가 정해지는 MenuBarExtra 창 안에서는
    /// 최소 크기로 쪼그라든다(행 텍스트가 세로로 잘리는 증상). 그래서 높이를 계산해 명시한다.
    ///
    /// 펼쳐진 그룹만큼 늘어나고, 화면 높이를 넘지 않는다.
    ///
    /// 검색은 높이에 반영하지 않는다. 타이핑할 때마다 결과 수에 맞춰 창이 줄면 MenuBarExtra 창의
    /// 위쪽이 제대로 다시 그려지지 않아 빈 반투명 영역이 남는다. 검색 전 크기를 유지하고 넘치면 스크롤한다.
    private var listHeight: CGFloat {
        let projects = modeProjects
        let favoriteCount = projects.flatMap(\.sessions).filter { favoriteIds.contains($0.id) }.count
        var needed: CGFloat = 16                       // LazyVStack 위아래 여백
        if !showingHidden && favoriteCount > 0 {
            needed += 26 + 9                           // 섹션 헤더 + 구분선
            if favoritesExpanded { needed += CGFloat(favoriteCount) * 39 }
        }
        for project in projects {
            needed += 26                               // 그룹 헤더 한 줄
            if expanded.contains(project.id) {
                needed += CGFloat(project.sessions.count) * 39   // 세션 행(2줄)
            }
        }
        var screenCap = (NSScreen.main?.visibleFrame.height ?? 800) - 140 - 36   // 36: 검색창
        if pendingDelete != nil { screenCap -= 160 }   // 확인 영역이 차지하는 만큼
        if pendingRename != nil { screenCap -= 160 }
        return min(max(needed, 160), min(900, screenCap))
    }

    /// projects.isEmpty는 "첫 스캔이 아직 안 끝남"과 "스캔은 끝났는데 세션이 없음"을
    /// 구분하지 못한다. loadState로 그 둘을 가른다.
    private var emptyState: some View {
        Group {
            switch loadState {
            case .loading:
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("state.loading")).fontWeight(.medium)
                }
                .padding(16)
            case .loaded:
                if showingHidden {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("hidden.empty")).fontWeight(.medium)
                    }
                    .padding(16)
                } else if FileManager.default.fileExists(atPath: SessionStore.defaultRoot.path) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("state.noSessions")).fontWeight(.medium)
                        Text(L("state.noSessionsDetail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("state.noSessions")).fontWeight(.medium)
                        Text(L("state.rootMissing"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
        }
    }

    /// 삭제 확인과 같은 이유로 시스템 모달을 쓰지 않고 팝오버 안에서 입력받는다.
    private func renamePanel(_ session: Session) -> some View {
        actionPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("rename.title"))
                    .font(.headline)
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFieldFocused)
                    .onSubmit { confirmRename(session) }
                Text(L("rename.detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button(L("rename.cancel")) { dismissPanels() }
                .keyboardShortcut(.cancelAction)
            Button(L("rename.save")) { confirmRename(session) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { renameFieldFocused = true }
    }

    /// 삭제 확인과 이름 변경이 공유하는 껍데기.
    ///
    /// 팝오버 자체가 이미 반투명 재료라 그 위에 또 반투명 배경을 얹으면 대비가 무너진다.
    /// 불투명한 컨트롤 배경으로 영역을 분리하고, 경계는 구분선 하나로 처리한다.
    private func actionPanel<Content: View, Actions: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
            HStack(spacing: 10) {
                Spacer()
                actions()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dismissPanels() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
            pendingDelete = nil
            pendingRename = nil
        }
        searchFieldFocused = true
    }

    private func confirmRename(_ session: Session) {
        let name = renameText
        dismissPanels()
        do {
            try renamer.rename(session, to: name)
        } catch {
            setNotice(L("notice.renameFailed", error.localizedDescription))
            return
        }
        Task {
            await store.refreshAsync()
            updateMissingPaths()
        }
    }

    /// MenuBarExtra의 팝오버는 포커스를 잃으면 닫히는 패널이다. 그 위에 시스템 모달
    /// (confirmationDialog/alert)을 띄우면 버튼을 누르는 순간 패널이 키 상태를 잃고
    /// 사라지면서 액션이 실행되지 않는다. 그래서 확인을 팝오버 안에서 처리한다.
    private func deleteConfirmation(_ session: Session) -> some View {
        actionPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("delete.title"))
                    .font(.headline)
                Text(session.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(L("delete.detail", formattedSize(session)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            // macOS 관례: 버튼은 오른쪽 아래, 기본 동작이 가장 오른쪽, 취소는 그 왼쪽.
            Button(L("delete.cancel")) { dismissPanels() }
                .keyboardShortcut(.cancelAction)
            Button(L("delete.confirm"), role: .destructive) { confirmDelete(session) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)   // 잘리지 않고 줄바꿈
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            // 새로고침은 항상 왼쪽 끝, 종료는 항상 오른쪽 끝에 고정한다.
            // 숨김 버튼은 있을 때만 새로고침 옆에 붙으므로, 없어도 나머지가 움직이지 않는다.
            HStack(spacing: 12) {
                Button(L("action.refresh")) {
                    Task {
                        await store.refreshAsync()
                        updateMissingPaths()
                        updateLiveSessions()
                        updatePendingMoves()
                        updateHidden()
                    }
                }
                if showingHidden {
                    Button(L("hidden.back")) {
                        withAnimation(.easeInOut(duration: 0.15)) { showingHidden = false }
                    }
                } else if !hiddenIds.isEmpty {
                    Button(L("hidden.show %d", hiddenIds.count)) {
                        withAnimation(.easeInOut(duration: 0.15)) { showingHidden = true }
                    }
                }
                Spacer()
                Button(L("action.quit")) { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(12)
    }

    private func binding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { isExpanded(project) },
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

    /// 확인 대화상자에 보여줄 용량. 서브에이전트 로그가 대부분을 차지하므로 합산해서 보여준다.
    private func formattedSize(_ session: Session) -> String {
        ByteCountFormatter.string(fromByteCount: SessionRemover.totalSize(of: session),
                                  countStyle: .file)
    }

    private func confirmDelete(_ session: Session) {
        dismissPanels()
        do {
            try remover.remove(session)
            registry.forget(session.id)
            hides.reveal(session.id)
        } catch {
            setNotice(L("notice.deleteFailed", error.localizedDescription))
            return
        }
        Task {
            await store.refreshAsync()
            updateMissingPaths()
        }
    }

    /// 터미널이 열려 있는 세션 집합. 세션당 stat 한 번이라 새로고침마다 다시 계산해도 싸다.
    private func updateLiveSessions() {
        let ids = store.projects.flatMap(\.sessions).map(\.id)
        liveSessions = Set(ids.filter { registry.isLive($0) })
    }

    /// 숨김 상태를 다시 읽는다. 사라진 세션의 기록은 여기서 정리된다.
    private func updateHidden() {
        let sessions = store.projects.flatMap(\.sessions)
        hides.reconcile(sessions)
        hiddenIds = hides.hidden()
        if showingHidden && hiddenIds.isEmpty { showingHidden = false }
    }

    /// 즐겨찾기 상태를 다시 읽는다. 사라진 세션의 기록은 여기서 정리된다.
    private func updateFavorites() {
        let sessions = store.projects.flatMap(\.sessions)
        favorites.reconcile(sessions)
        favoriteIds = favorites.favorites()
    }

    /// 즐겨찾기 섹션에 보여줄 세션. 숨긴 것은 빠지고, 검색 필터를 거치고, 최근 활동순이다.
    private var favoriteSessions: [Session] {
        visibleProjects.flatMap(\.sessions)
            .filter { favoriteIds.contains($0.id) && !hiddenIds.contains($0.id) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 모드(평소/숨긴 세션)에 따라 보여줄 그룹. 세션이 하나도 안 남는 그룹은 빠진다.
    private var modeProjects: [Project] {
        store.projects.compactMap { project in
            let sessions = project.sessions.filter {
                showingHidden ? hiddenIds.contains($0.id) : !hiddenIds.contains($0.id)
            }
            return sessions.isEmpty ? nil : Project(path: project.path, sessions: sessions)
        }
    }

    /// 화면에 그릴 그룹. 모드에 검색어 필터까지 거친다.
    private var visibleProjects: [Project] {
        SessionSearch.filter(modeProjects, query: searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 검색 중에는 맞는 그룹이 모두 펼쳐진다. 사용자가 고른 펼침 상태는 건드리지 않으므로
    /// 검색을 지우면 원래대로 돌아간다.
    private func isExpanded(_ project: Project) -> Bool {
        isSearching || expanded.contains(project.id)
    }

    private var favoritesShown: Bool { isSearching || favoritesExpanded }

    private func rowKey(_ session: Session, inFavorites: Bool) -> String {
        (inFavorites ? "favorite:" : "group:") + session.id
    }

    private static let favoritesHeaderKey = "favorites-header"

    private func headerKey(_ project: Project) -> String { "group-header:" + project.id }

    private func selectionBackground(_ key: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(selectedRow == key ? Color.accentColor.opacity(0.2) : .clear)
    }

    /// ↑↓로 지나가는 행 하나. 헤더에서 Enter는 펼치고 접고, 세션에서 Enter는 연다.
    private enum NavRow {
        case favoritesHeader
        case header(Project)
        case session(Session)
    }

    /// 화면에 보이는 순서대로의 행. ↑↓는 이 순서를 따른다.
    ///
    /// 접힌 그룹에도 키보드로 닿도록 헤더를 포함한다. 단 검색 중에는 그룹이 모두 펼쳐져 있어
    /// 헤더가 할 일이 없고, 타이핑 후 Enter가 첫 결과를 열어야 하므로 세션만 지난다.
    private var navigableRows: [(key: String, row: NavRow)] {
        let headers = !isSearching
        var rows: [(key: String, row: NavRow)] = []
        if !showingHidden && !favoriteSessions.isEmpty {
            if headers { rows.append((Self.favoritesHeaderKey, .favoritesHeader)) }
            if favoritesShown {
                rows += favoriteSessions.map { (rowKey($0, inFavorites: true), .session($0)) }
            }
        }
        for project in visibleProjects {
            if headers { rows.append((headerKey(project), .header(project))) }
            if isExpanded(project) {
                rows += project.sessions.map { (rowKey($0, inFavorites: false), .session($0)) }
            }
        }
        return rows
    }

    private func moveSelection(by step: Int) {
        let keys = navigableRows.map(\.key)
        guard !keys.isEmpty else { return }
        if let current = selectedRow, let index = keys.firstIndex(of: current) {
            selectedRow = keys[min(max(index + step, 0), keys.count - 1)]
        } else {
            selectedRow = step > 0 ? keys.first : keys.last
        }
    }

    private func openSelectedRow() {
        guard let key = selectedRow,
              let entry = navigableRows.first(where: { $0.key == key }) else { return }
        switch entry.row {
        case .favoritesHeader: favoritesExpanded.toggle()
        case .header(let project): binding(for: project).wrappedValue.toggle()
        case .session(let session): open(session)
        }
    }

    private func resetSearch() {
        searchText = ""
        selectedRow = nil
    }

    /// 검색창에 포커스가 있는 채로 ↑↓와 Esc를 목록 조작에 쓴다. 이 키들은 TextField의
    /// 필드 에디터가 먼저 처리하므로 SwiftUI 키 처리 대신 앱 이벤트 모니터로 가로챈다.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard pendingRename == nil, pendingDelete == nil,
              !(event.window is NSSavePanel),   // 폴더 선택 창의 키는 건드리지 않는다
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        else { return false }
        // 한글 조합 중에는 화살표가 조합을 끝내는 데 쓰인다. 가로채면 글자가 조합 상태로 남는다.
        if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        switch event.keyCode {
        case 125: moveSelection(by: 1); return true    // ↓
        case 126: moveSelection(by: -1); return true   // ↑
        case 53 where !searchText.isEmpty: resetSearch(); return true   // Esc
        default: return false
        }
    }

    private func scheduleMove(_ session: Session, to path: String) {
        moves.schedule(path, for: session.id)
        updatePendingMoves()
        // 메모리는 프로젝트 디렉토리 단위라 따라가지 않는다. 조용히 잃게 두지 않고 알린다.
        let count = ProjectMemory.fileCount(for: session)
        if count > 0 {
            setNotice(L("move.memoryWarning %d", count))
        }
    }

    /// 아직 세션이 없는 폴더로 옮기기 위한 표준 폴더 선택 창.
    ///
    /// 팝오버는 포커스를 잃으면 닫히지만, 메뉴 항목을 누르는 순간 이 코드가 먼저 돌아
    /// 창을 띄우므로 상관없다. 앱이 accessory(LSUIElement)라 패널을 앞으로 가져오려면
    /// 먼저 활성화해야 한다.
    private func chooseFolder(for session: Session) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = L("move.chooseFolderPrompt")
        panel.prompt = L("action.moveTo")
        // 형제 프로젝트가 한눈에 보이도록 현재 폴더의 상위에서 시작한다.
        panel.directoryURL = URL(fileURLWithPath: session.cwd).deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            setNotice(L("move.notADirectory"))
            return
        }
        scheduleMove(session, to: url.path)
    }

    /// 예약 목록을 다시 읽는다. 이미 목적지에 도착한 예약은 여기서 정리된다.
    private func updatePendingMoves() {
        let sessions = store.projects.flatMap(\.sessions)
        moves.reconcile(sessions)
        var found: [String: String] = [:]
        for session in sessions {
            if let target = moves.pendingTarget(for: session.id) { found[session.id] = target }
        }
        pendingMoves = found
    }

    private func newSession(in project: Project) {
        guard FileManager.default.fileExists(atPath: project.path) else {
            setNotice(L("notice.folderMissing", project.path))
            return
        }
        switch launcher.launchNew(inDirectory: project.path) {
        case .launched, .focused:
            notice = nil
        case .copiedToClipboard:
            setNotice(L("notice.launchFailed"))
        }
    }

    private func open(_ session: Session) {
        // 클릭 시점에 직접 확인한다. 마지막 새로고침 이후 폴더가 사라졌을 수 있고,
        // 클릭 한 번에 stat 한 번은 렌더 경로와 달리 비용이 아니다.
        // missingPaths는 렌더링(흐리게 표시) 전용으로만 쓴다.
        guard FileManager.default.fileExists(atPath: session.cwd) else {
            setNotice(L("notice.folderMissing", session.cwd))
            return
        }
        // 이동 예약이 있으면 그 폴더에서 연다. 기존 창 포커스는 건너뛴다 —
        // 그 창은 옛 폴더에 있어서, 거기로 가면 이동이 일어나지 않는다.
        let moveTarget = moves.target(for: session.id)
        switch launcher.launch(session, movingTo: moveTarget) {
        case .launched, .focused:
            notice = nil
            // 그 폴더에서 실제로 열었다면 사용자가 결정을 실행한 것이다.
            // 로그의 cwd는 첫 메시지 전까지 갱신되지 않으므로 그 사이를 메운다.
            if moveTarget != nil {
                moves.markApplied(session.id)
                Task {
                    await store.refreshAsync()
                    updateMissingPaths()
                    updatePendingMoves()
                }
            }
            noticeSetAt = nil
        case .copiedToClipboard:
            setNotice(L("notice.launchFailed"))
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

/// MenuBarExtra 창은 내용이 작아져도 줄지 않고, 한 번 직접 크기를 바꾸면 커지는 것도 따라오지
/// 않는다. 줄어든 만큼이 빈 반투명 영역으로 남는다(그룹을 접거나 검색 결과가 줄 때).
/// 그래서 내용 높이가 바뀔 때마다 창 높이를 직접 맞춘다. 메뉴바에 붙은 위쪽 모서리는 그대로 둔다.
///
/// 높이가 애니메이션되면 매 프레임 창을 바꾸게 되어 튀고 깜빡인다. 목록 높이가 바뀔 때는
/// 애니메이션을 걸지 않으므로(body 참고) 한 번만 맞춘다.
private struct WindowHeightFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // 내용과 같은 프레임에 창을 바꿔야 튀지 않는다. 다음 런루프로 미루면 새 높이의 내용이
        // 옛 크기의 창에 한 프레임 그려진다. 창이 아직 없을 때(처음 붙을 때)만 미룬다.
        if let window = view.window {
            fit(window)
        } else {
            DispatchQueue.main.async { [weak view] in
                if let window = view?.window { fit(window) }
            }
        }
    }

    private func fit(_ window: NSWindow) {
        guard height > 0, abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }
}

private struct SessionRow: View {
    let session: Session
    let exists: Bool
    /// 이 세션의 터미널 창이 아직 열려 있는가. 점 색과 클릭 결과가 여기서 갈린다.
    let hasTerminal: Bool
    /// 다음 재개 때 옮겨갈 폴더. 아직 옮겨지지 않았으므로 행은 원래 그룹에 남는다.
    let movingTo: String?
    /// 즐겨찾기 여부. 그룹 안에서도 알아볼 수 있게 별표를 붙인다.
    let isFavorite: Bool
    /// 키보드(↑↓)로 고른 행인가. Enter가 이 행을 연다.
    let isSelected: Bool
    /// 이 프로젝트에 딸린 메모리 파일 수. 이동하면 따라가지 않으므로 툴팁에 밝힌다.
    let memoryCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 초록 = 창이 열려 있음(클릭하면 그 창으로), 회색 = 클릭하면 새 창.
                // 점이 클릭의 결과를 미리 알려준다.
                Circle()
                    .fill(hasTerminal ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .help(hasTerminal ? L("dot.hasTerminal") : L("dot.noTerminal"))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(session.title)
                            .lineLimit(1)
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(relativeTime)
                        if let branch = session.gitBranch {
                            Text("· \(branch)")
                        }
                        if let movingTo {
                            let name = (movingTo as NSString).lastPathComponent
                            Text("→ \(name)")
                                .foregroundStyle(.orange)
                                .help(memoryCount > 0
                                      ? L("move.pendingWithMemory %1$@ %2$d", name, memoryCount)
                                      : L("move.pending %@", name))
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
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear))
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
