import SwiftUI
import SwiftData
import CoreLocation

struct StatisticsView: View {
    @Query(sort: \Ticket.departureTime, order: .reverse) private var tickets: [Ticket]

    private var totalDistance: Int {
        // 粗略估计: 根据坐标计算直线距离
        let db = StationDatabase.shared
        var total: Double = 0
        for ticket in tickets {
            if let dep = db.coordinate(for: ticket.departureStation),
               let arr = db.coordinate(for: ticket.arrivalStation) {
                let latDiff = (dep.latitude - arr.latitude) * 111
                let lonDiff = (dep.longitude - arr.longitude) * 111 * cos(dep.latitude * .pi / 180)
                total += sqrt(latDiff * latDiff + lonDiff * lonDiff)
            }
        }
        return Int(total)
    }

    private var totalCost: Double {
        tickets.reduce(0) { $0 + $1.price }
    }

    private var totalDuration: TimeInterval {
        tickets.reduce(0) { $0 + $1.duration }
    }

    private var cityCount: Int {
        let db = StationDatabase.shared
        var cities = Set<String>()
        for ticket in tickets {
            if let c = db.city(for: ticket.departureStation) { cities.insert(c) }
            if let c = db.city(for: ticket.arrivalStation) { cities.insert(c) }
        }
        return cities.count
    }

    private var provinceCount: Int {
        let db = StationDatabase.shared
        var provinces = Set<String>()
        for ticket in tickets {
            if let info = db.lookup(ticket.departureStation) { provinces.insert(info.province) }
            if let info = db.lookup(ticket.arrivalStation) { provinces.insert(info.province) }
        }
        return provinces.count
    }

    private var trainTypeStats: [(String, Int, Color)] {
        var counts: [String: (Int, Color)] = [:]
        for ticket in tickets {
            let type = ticket.trainType
            if let existing = counts[type] {
                counts[type] = (existing.0 + 1, existing.1)
            } else {
                counts[type] = (1, ticket.trainTypeColor)
            }
        }
        return counts.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    private var seatClassStats: [(String, Int, Color)] {
        var counts: [String: (Int, Color)] = [:]
        for ticket in tickets {
            if let existing = counts[ticket.seatClass] {
                counts[ticket.seatClass] = (existing.0 + 1, existing.1)
            } else {
                counts[ticket.seatClass] = (1, ticket.seatClassColor)
            }
        }
        return counts.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    private var topRoutes: [(String, Int)] {
        var routeCounts: [String: Int] = [:]
        for ticket in tickets {
            let route = "\(ticket.departureStation)→\(ticket.arrivalStation)"
            routeCounts[route, default: 0] += 1
        }
        return routeCounts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var monthlyStats: [(String, Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"
        var counts: [Int: Int] = [:]
        for ticket in tickets {
            let month = Calendar.current.component(.month, from: ticket.departureTime)
            counts[month, default: 0] += 1
        }
        return (1...12).map { (formatter.string(from: DateComponents(calendar: Calendar.current, month: $0).date!), counts[$0] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tickets.isEmpty {
                    ContentUnavailableView {
                        Label("暂无数据", systemImage: "chart.bar")
                    } description: {
                        Text("添加车票后即可查看旅行统计")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            overviewCards
                            monthlyChart
                            trainTypeSection
                            seatClassSection
                            topRoutesSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("旅行统计")
        }
    }

    // MARK: - Overview
    private var overviewCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                overviewCard(icon: "train.side.front.car", value: "\(tickets.count)", label: "总行程", color: .blue)
                overviewCard(icon: "mappin.and.ellipse", value: "\(cityCount)", label: "城市", color: .green)
            }
            HStack(spacing: 12) {
                overviewCard(icon: "map", value: "\(provinceCount)", label: "省份", color: .orange)
                overviewCard(icon: "road.lanes", value: "\(totalDistance)km", label: "总里程", color: .purple)
            }
            HStack(spacing: 12) {
                overviewCard(icon: "yensign.circle", value: "¥\(Int(totalCost))", label: "总花费", color: .red)
                overviewCard(icon: "clock", value: formatDuration(totalDuration), label: "总时长", color: .teal)
            }
        }
    }

    private func overviewCard(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Monthly Chart
    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("月度出行")
                .font(.system(size: 16, weight: .semibold))

            let maxCount = monthlyStats.map(\.1).max() ?? 1

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(monthlyStats, id: \.0) { month, count in
                    VStack(spacing: 4) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(count > 0 ? Color.blue.gradient : Color.gray.opacity(0.15).gradient)
                            .frame(height: count > 0 ? CGFloat(count) / CGFloat(maxCount) * 100 : 4)
                        Text(month)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Train Type
    private var trainTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("车型分布")
                .font(.system(size: 16, weight: .semibold))

            ForEach(trainTypeStats, id: \.0) { type, count, color in
                HStack {
                    Text(type)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(count) / CGFloat(tickets.count))
                    }
                    .frame(height: 20)

                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Seat Class
    private var seatClassSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("坐席偏好")
                .font(.system(size: 16, weight: .semibold))

            ForEach(seatClassStats, id: \.0) { cls, count, color in
                HStack {
                    Text(cls)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(count) / CGFloat(tickets.count))
                    }
                    .frame(height: 20)

                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Top Routes
    private var topRoutesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常走线路 TOP 5")
                .font(.system(size: 16, weight: .semibold))

            if topRoutes.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(topRoutes.enumerated()), id: \.offset) { index, route in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(index == 0 ? Color.orange : index == 1 ? Color.gray : Color.brown)
                            .clipShape(Circle())

                        Text(route.0)
                            .font(.system(size: 14, weight: .medium))

                        Spacer()

                        Text("\(route.1)次")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                    if index < topRoutes.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        if hours >= 24 {
            let days = hours / 24
            let remainHours = hours % 24
            return "\(days)天\(remainHours)h"
        }
        return "\(hours)h"
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: Ticket.self, inMemory: true)
}
