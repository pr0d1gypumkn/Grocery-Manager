import SwiftUI
import SwiftData

@main
struct GroceryManagerApp: App {
    private let sharedModelContainer = PersistenceController.shared
    @State private var isLaunching = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(isLaunching ? 0 : 1)
                    .animation(.easeInOut(duration: 0.6), value: isLaunching)

                LaunchScreenView()
                    .opacity(isLaunching ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6), value: isLaunching)
            }
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                isLaunching = false
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

