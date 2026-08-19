import SwiftUI

@main
struct BoseControlApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("Bose Control", systemImage: "headphones") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
