import SwiftUI
import SwiftData

struct TicketListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.departureTime, order: .reverse) private var tickets: [Ticket]
    @State private var showAddTicket = false
    @State private var searchText = ""
    @State private var selectedYear: Int?

    private var filteredTickets: [Ticket] {
        var results = tickets
        if !searchText.isEmpty {
            results = results.filter { ticket in
                ticket.trainNumber.localizedCaseInsensitiveContains(searchText) ||
                ticket.departureStation.contains(searchText) ||
                ticket.arrivalStation.contains(searchText) ||
                ticket.passengerName.contains(searchText)
            }
        }
        if let year = selectedYear {
            results = results.filter { Calendar.current.component(.year, from: $0.departureTime) == year }
        }
        return results
    }

    private var availableYears: [Int] {
        let years = Set(tickets.map { Calendar.current.component(.year, from: $0.departureTime) })
        return years.sorted(by: >)
    }

    private var groupedTickets: [(String, [Ticket])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        let grouped = Dictionary(grouping: filteredTickets) { ticket in
            formatter.string(from: ticket.departureTime)
        }
        return grouped.sorted { a, b in
            a.value.first!.departureTime > b.value.first!.departureTime
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tickets.isEmpty {
                    emptyStateView
                } else {
                    ticketListContent
                }
            }
            .navigationTitle("我的车票")
            .searchable(text: $searchText, prompt: "搜索车次、车站、乘客")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddTicket = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }

                if !availableYears.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("全部") {
                                selectedYear = nil
                            }
                            ForEach(availableYears, id: \.self) { year in
                                Button("\(String(year))年") {
                                    selectedYear = year
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if let year = selectedYear {
                                    Text("\(String(year))年")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddTicket) {
                AddTicketView()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("还没有车票", systemImage: "ticket")
        } description: {
            Text("点击右上角 + 添加你的第一张车票")
        } actions: {
            Button("添加车票") {
                showAddTicket = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var ticketListContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // 简要统计
                headerStats

                ForEach(groupedTickets, id: \.0) { month, monthTickets in
                    Section {
                        ForEach(monthTickets) { ticket in
                            NavigationLink(value: ticket) {
                                TicketCardView(ticket: ticket, compact: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteTicket(ticket)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(month)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(monthTickets.count)张")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: Ticket.self) { ticket in
            TicketDetailView(ticket: ticket)
        }
    }

    private var headerStats: some View {
        let totalTrips = filteredTickets.count
        let totalCost = filteredTickets.reduce(0.0) { $0 + $1.price }
        let cities = Set(filteredTickets.flatMap { [$0.departureStation, $0.arrivalStation] }).count

        return HStack(spacing: 0) {
            statItem(value: "\(totalTrips)", label: "行程", icon: "train.side.front.car")
            Divider().frame(height: 30)
            statItem(value: "\(cities)", label: "城市", icon: "building.2")
            Divider().frame(height: 30)
            statItem(value: "¥\(Int(totalCost))", label: "花费", icon: "yensign")
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func deleteTicket(_ ticket: Ticket) {
        withAnimation {
            modelContext.delete(ticket)
        }
    }
}

#Preview {
    TicketListView()
        .modelContainer(for: Ticket.self, inMemory: true)
}
