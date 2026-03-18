import SwiftUI
import SwiftData

struct TicketListView: View {
    private enum TicketFilter: String, CaseIterable {
        case all = "全部"
        case upcoming = "待出发"
        case finished = "已完成"
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.departureTime, order: .reverse) private var tickets: [Ticket]
    @State private var showAdd = false
    @State private var selectedFilter: TicketFilter = .all
    @State private var keyword = ""
    @State private var selectedTicket: Ticket?

    private var filteredTickets: [Ticket] {
        let now = Date()

        let byFilter: [Ticket]
        switch selectedFilter {
        case .all:
            byFilter = tickets
        case .upcoming:
            byFilter = tickets.filter { $0.departureTime >= now }
        case .finished:
            byFilter = tickets.filter { $0.departureTime < now }
        }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return byFilter }

        return byFilter.filter {
            $0.trainNumber.localizedCaseInsensitiveContains(trimmed)
            || $0.departureStation.localizedCaseInsensitiveContains(trimmed)
            || $0.arrivalStation.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var totalPrice: Double {
        tickets.reduce(0) { $0 + $1.price }
    }

    private var upcomingCount: Int {
        let now = Date()
        return tickets.filter { $0.departureTime >= now }.count
    }

    private var thisMonthCount: Int {
        let cal = Calendar.current
        let now = Date()
        return tickets.filter { cal.isDate($0.departureTime, equalTo: now, toGranularity: .month) }
            .count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.98, green: 0.97, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        overviewSection
                        searchSection
                        filterSection

                        if filteredTickets.isEmpty {
                            emptySection
                        } else {
                            ticketListSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("你的铁路档案")
            .navigationDestination(item: $selectedTicket) { ticket in
                TicketDetailView(ticket: ticket)
            }
            .sheet(isPresented: $showAdd) {
                AddTicketView()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statCard(title: "车票总数", value: "\(tickets.count)", tint: .blue)
                statCard(title: "待出发", value: "\(upcomingCount)", tint: .mint)
                statCard(title: "总票价", value: String(format: "¥%.1f", totalPrice), tint: .orange)
            }

            if thisMonthCount > 0 {
                Text("本月已记录 \(thisMonthCount) 次出行")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var searchSection: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索车次 / 出发站 / 到达站", text: $keyword)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            addButton
        }
    }

    private var filterSection: some View {
        HStack(spacing: 8) {
            ForEach(TicketFilter.allCases, id: \.self) { item in
                Button(item.rawValue) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = item
                    }
                }
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedFilter == item ? Color.blue.opacity(0.18) : Color.white.opacity(0.6), in: Capsule())
                .foregroundStyle(selectedFilter == item ? .blue : .primary)
            }
            Spacer()
        }
    }

    private var emptySection: some View {
        VStack(spacing: 10) {
            Image(systemName: "ticket")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("暂无匹配车票")
                .font(.headline)
            Text(keyword.isEmpty ? "点击搜索框右侧按钮开始记录你的第一张车票" : "尝试更换关键字或筛选条件")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var ticketListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredTickets) { ticket in
                Button {
                    selectedTicket = ticket
                } label: {
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
        }
    }

    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .blue.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tickets[index])
        }
        try? modelContext.save()
    }

    private func deleteTicket(_ ticket: Ticket) {
        modelContext.delete(ticket)
        try? modelContext.save()
    }
}
