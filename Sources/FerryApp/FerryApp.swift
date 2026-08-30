import SwiftUI

@main
struct FerryApp: App {
    var body: some Scene {
        MenuBarExtra("Ferry", systemImage: "ferry") {
            Text("준비 중")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
