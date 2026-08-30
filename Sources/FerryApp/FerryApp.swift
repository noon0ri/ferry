import SwiftUI

@main
struct FerryApp: App {
    var body: some Scene {
        MenuBarExtra("Ferry", systemImage: "ferry") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
