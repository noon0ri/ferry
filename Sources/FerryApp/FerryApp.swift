import SwiftUI

@main
struct FerryApp: App {
    init() {
        GlobalHotKey.register()
    }

    var body: some Scene {
        MenuBarExtra("Ferry", systemImage: "ferry") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
