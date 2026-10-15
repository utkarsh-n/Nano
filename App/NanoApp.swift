import SwiftUI

@main
struct NanoApp: App {
    @State private var store = LabStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NanoHome(store: store)
                .tint(.blue)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { store.save(); return }
                    await store.runClock()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.save() }
                }
        }
    }
}
