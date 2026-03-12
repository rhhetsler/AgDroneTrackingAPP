import SwiftUI

@main
struct AgSprayDroneApp: App {
    @StateObject private var api = AgAPI()

    var body: some Scene {
        WindowGroup {
            JobEditorView()
                .environmentObject(api)
        }
    }
}
