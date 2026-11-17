import AppKit
import Carbon.HIToolbox

/// ⌃⌥Space로 어디서든 팝오버를 연다. 검색창이 바로 포커스를 받으므로 단축키 → 입력 → Enter로
/// 마우스 없이 세션을 다시 연다.
///
/// Carbon 핫키는 손쉬운 사용 권한 없이 동작한다. NSEvent 전역 모니터는 그 권한을 요구한다.
enum GlobalHotKey {

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // 핫키 이벤트는 메인 스레드의 애플리케이션 이벤트 타깃으로 온다.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.togglePopover() }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef?
        // 다른 앱이 이미 같은 조합을 쥐고 있으면 실패한다. 그때는 단축키 없이 메뉴바 클릭으로만 쓴다.
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: 0x4652_5259, id: 1),   // "FRRY"
                            GetApplicationEventTarget(), 0, &ref)
    }

    /// MenuBarExtra에는 팝오버를 코드로 여는 API가 없다.
    ///
    /// macOS 26까지는 메뉴바 버튼을 누르는 것(`performClick`)으로 열린다. macOS 27부터는 버튼의
    /// target/action이 비어 있고, 메뉴바가 "expanded interface session"으로 연다. 닫는 쪽
    /// (`expandedInterfaceSession.cancel()`)은 공개 API지만 여는 쪽은 공개되지 않아
    /// 비공개 `_requestExpandedInterfaceSession`을 부른다.
    /// shortcut: 비공개 API라 macOS 업데이트로 깨질 수 있다. 깨지면 단축키만 조용히 동작하지 않는다.
    @MainActor
    private static func togglePopover() {
        // MenuBarExtra가 만든 메뉴바 버튼 창. 화면 밖 복제본이 있을 수 있어 화면 위의 것만 본다.
        guard let window = NSApp.windows.first(where: {
            $0.className.contains("NSStatusBarWindow") && $0.screen != nil && $0.frame.minY >= 0
        }) else { return }

        if #available(macOS 27, *) {
            let getter = Selector(("statusItem"))
            guard window.responds(to: getter),
                  let item = window.perform(getter)?.takeUnretainedValue() as? NSStatusItem
            else { return }
            if let session = item.expandedInterfaceSession {
                session.cancel()
                return
            }
            let request = Selector(("_requestExpandedInterfaceSession"))
            guard item.responds(to: request) else { return }
            item.perform(request)
        } else {
            window.contentView.flatMap(statusButton(in:))?.performClick(nil)
        }
    }

    @MainActor
    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(statusButton(in:)).first
    }
}
