import SwiftUI

import SwiftUI

@main
struct AgSprayDroneApp: App {
    @StateObject private var api = AgAPI()

    var body: some Scene {
        WindowGroup {
            SprayJobManagementView()
                .environmentObject(api)
        }
    }
}
struct HomeView: View {

    @State private var showNewJob = false

    var body: some View {

        VStack(spacing: 30) {

            Text("Ag Spray Drone")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button("Create New Spray Job") {
                showNewJob = true
            }
            .font(.title2)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))

        }
        .sheet(isPresented: $showNewJob) {
            JobEditorView()
        }
    }
}
