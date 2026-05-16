import SwiftUI

@main
struct IdeaQueueApp: App {
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            DashboardView(store: store)
        }
    }
}
