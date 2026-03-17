import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("车票", systemImage: "ticket.fill", value: 0) {
                TicketListView()
            }

            Tab("我的", systemImage: "gearshape.fill", value: 3) {
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
