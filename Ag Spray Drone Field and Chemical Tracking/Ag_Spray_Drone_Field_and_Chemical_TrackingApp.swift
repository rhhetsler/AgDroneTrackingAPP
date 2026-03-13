import SwiftUI
import Combine

protocol AgAPIDebugStub: ObservableObject {
    func addJob(from draft: SprayJobDraft)
}

private struct AgAPIKey: EnvironmentKey {
    static var defaultValue: (any AgAPIDebugStub)? { nil }
}

extension EnvironmentValues {
    var agAPI: (any AgAPIDebugStub) {
        get {
            guard let value = self[AgAPIKey.self] else {
                fatalError("agAPI not set in Environment. Provide an implementation via .environment(\\.agAPI, ...) before presenting NewJobView.")
            }
            return value
        }
        set { self[AgAPIKey.self] = newValue }
    }
}

struct NewJobView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.agAPI) var api: any AgAPIDebugStub

    @State private var draft = SprayJobDraft()
    var body: some View {
        NavigationStack {
            Form {
                // form fields here
            }
            .navigationTitle("New Spray Job")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        print("Cancel tapped")
                        dismiss()
                        // If not presented modally, dismiss() does nothing.
                        print("Attempted dismiss after Cancel; ensure NewJobView is presented as a sheet or navigation destination.")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        print("Save tapped")
                        api.addJob(from: draft)
                        print("Dismissing sheet after save")
                        dismiss()
                        // If not presented modally, dismiss() does nothing.
                        print("Attempted dismiss after Save; ensure NewJobView is presented as a sheet or navigation destination.")
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear { print("NewJobView appeared") }
    }
}

#if DEBUG
@MainActor final class MockAgAPI: ObservableObject, AgAPIDebugStub {
    let objectWillChange = ObservableObjectPublisher()
    func addJob(from draft: SprayJobDraft) {
        // mock implementation for preview/builds without backend
        print("MockAgAPI.addJob called with draft: \(draft)")
    }
}
struct SprayJobDraft: CustomStringConvertible {
    var description: String { "SprayJobDraft()" }
}

#Preview {
    NewJobView()
        .environment(\.agAPI, MockAgAPI())
}
#endif

