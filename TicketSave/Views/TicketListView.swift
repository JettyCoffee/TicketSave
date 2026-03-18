import SwiftUI
import SwiftData

struct TicketListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.departureTime, order: .reverse) private var tickets: [Ticket]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if tickets.isEmpty {
                    ContentUnavailableView {
                        Label("暂无车票", systemImage: "ticket")
                    } description: {
                        Text("点击右上角添加车票")
                    }
                } else {
                    List {
                        ForEach(tickets) { ticket in
                            NavigationLink {
                                TicketDetailView(ticket: ticket)
                            } label: {
                                TicketCardView(ticket: ticket, compact: true)
                                    .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("车票")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTicketView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tickets[index])
        }
        try? modelContext.save()
    }
}
