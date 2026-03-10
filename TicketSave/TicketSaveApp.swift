import SwiftUI
import SwiftData

@main
struct TicketSaveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 从 bundle 内 data/station_name.js 加载全量站点（同步，毫秒级）
                    await StationLoader.shared.loadBundledIfNeeded()
                }
        }
        .modelContainer(for: [Ticket.self, TrainScheduleCache.self])
    }
}
