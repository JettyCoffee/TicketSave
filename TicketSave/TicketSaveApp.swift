import SwiftUI
import SwiftData

@main
struct TicketSaveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Ticket.self, TrainScheduleCache.self])
    }
}
