import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("车票", systemImage: "ticket.fill", value: 0) {
                TicketListView()
            }

            Tab("足迹", systemImage: "map.fill", value: 1) {
                JourneyMapView()
            }

            Tab("统计", systemImage: "chart.bar.fill", value: 2) {
                StatisticsView()
            }

            Tab("设置", systemImage: "gearshape.fill", value: 3) {
                SettingsView()
            }
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Ticket.self, inMemory: true)
}
