import SwiftUI
import SwiftData
import MapKit

struct TicketDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @Bindable var ticket: Ticket

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var fullDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }

    private var routeRegion: MKCoordinateRegion? {
        let db = StationDatabase.shared
        guard let dep = db.coordinate(for: ticket.departureStation),
              let arr = db.coordinate(for: ticket.arrivalStation) else { return nil }
        let midLat = (dep.latitude + arr.latitude) / 2
        let midLon = (dep.longitude + arr.longitude) / 2
        let latSpan = abs(dep.latitude - arr.latitude) * 1.6
        let lonSpan = abs(dep.longitude - arr.longitude) * 1.6
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: max(latSpan, 2), longitudeDelta: max(lonSpan, 2))
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 完整车票卡片
                TicketCardView(ticket: ticket)
                    .padding(.horizontal)

                // 路线地图
                if let region = routeRegion {
                    routeMapSection(region: region)
                }

                // 详细信息
                detailInfoSection

                // 备注
                notesSection

                // 操作按钮
                actionSection
            }
            .padding(.vertical)
        }
        .navigationTitle("车票详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            EditTicketView(ticket: ticket)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") {
                    isEditing = true
                }
            }
        }
    }

    // MARK: - Route Map
    private func routeMapSection(region: MKCoordinateRegion) -> some View {
        let db = StationDatabase.shared
        let depCoord = db.coordinate(for: ticket.departureStation)!
        let arrCoord = db.coordinate(for: ticket.arrivalStation)!

        return VStack(alignment: .leading, spacing: 8) {
            Label("行程路线", systemImage: "map")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Map(initialPosition: .region(region)) {
                Marker(ticket.departureStation, coordinate: depCoord)
                    .tint(.green)
                Marker(ticket.arrivalStation, coordinate: arrCoord)
                    .tint(.red)
                MapPolyline(coordinates: [depCoord, arrCoord])
                    .stroke(ticket.trainTypeColor, lineWidth: 3)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Detail Info
    private var detailInfoSection: some View {
        VStack(spacing: 0) {
            infoRow(icon: "calendar", label: "日期", value: fullDateFormatter.string(from: ticket.departureTime))
            Divider().padding(.leading, 44)
            infoRow(icon: "clock", label: "时间", value: "\(timeFormatter.string(from: ticket.departureTime)) → \(timeFormatter.string(from: ticket.arrivalTime))")
            Divider().padding(.leading, 44)
            infoRow(icon: "timer", label: "用时", value: ticket.durationText)
            Divider().padding(.leading, 44)
            infoRow(icon: "carseat.right.fill", label: "座位", value: ticket.formattedSeat.isEmpty ? "未指定" : ticket.formattedSeat)
            Divider().padding(.leading, 44)
            infoRow(icon: "ticket.fill", label: "坐席", value: ticket.seatClass)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Notes
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("备注", systemImage: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            if ticket.notes.isEmpty {
                Text("暂无备注")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(ticket.notes)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Actions
    private var actionSection: some View {
        VStack(spacing: 12) {
            ShareLink(item: shareText) {
                Label("分享车票", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                modelContext.delete(ticket)
                dismiss()
            } label: {
                Label("删除车票", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal)
    }

    private var shareText: String {
        """
        🚄 \(ticket.trainNumber) \(ticket.trainType)
        📍 \(ticket.departureStation) → \(ticket.arrivalStation)
        📅 \(fullDateFormatter.string(from: ticket.departureTime))
        ⏰ \(timeFormatter.string(from: ticket.departureTime)) - \(timeFormatter.string(from: ticket.arrivalTime))
        💺 \(ticket.seatClass) \(ticket.formattedSeat)
        💰 ¥\(String(format: "%.1f", ticket.price))
        """
    }
}

// MARK: - Edit Ticket View
struct EditTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var ticket: Ticket

    let seatClasses = ["商务座", "一等座", "二等座", "特等座", "硬卧", "软卧", "硬座", "软座", "无座"]

    @State private var editCarriage = "01"
    @State private var editSeatRow = "01"
    @State private var editSeatLetter = "A"

    var body: some View {
        NavigationStack {
            Form {
                Section("车次信息") {
                    TextField("车次号", text: $ticket.trainNumber)
                }

                Section("行程") {
                    TextField("出发站", text: $ticket.departureStation)
                    TextField("到达站", text: $ticket.arrivalStation)
                    DatePicker("出发时间", selection: $ticket.departureTime)
                    DatePicker("到达时间", selection: $ticket.arrivalTime)
                }

                Section("座位") {
                    Picker("坐席", selection: $ticket.seatClass) {
                        ForEach(seatClasses, id: \.self) { Text($0) }
                    }
                    .onChange(of: ticket.seatClass) { _, newClass in
                        editSeatLetter = editLetterOptions(for: newClass).first ?? "A"
                    }
                    if ticket.seatClass != "无座" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("车厢 / 排位 / 席位")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 0) {
                                VStack(spacing: 2) {
                                    Text("车厢").font(.caption2).foregroundStyle(.secondary)
                                    Picker("车厢", selection: $editCarriage) {
                                        ForEach((1...20).map { String(format: "%02d", $0) }, id: \.self) { opt in
                                            Text(opt + "车").tag(opt)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 90, height: 100)
                                    .clipped()
                                }
                                VStack(spacing: 2) {
                                    Text("排位").font(.caption2).foregroundStyle(.secondary)
                                    Picker("排位", selection: $editSeatRow) {
                                        ForEach(editRowOptions(for: ticket.seatClass), id: \.self) { opt in
                                            Text(opt + (editIsSleeper ? "铺" : "排")).tag(opt)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 90, height: 100)
                                    .clipped()
                                }
                                VStack(spacing: 2) {
                                    Text("席位").font(.caption2).foregroundStyle(.secondary)
                                    Picker("席位", selection: $editSeatLetter) {
                                        ForEach(editLetterOptions(for: ticket.seatClass), id: \.self) { opt in
                                            Text(opt).tag(opt)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 90, height: 100)
                                    .clipped()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("其他") {
                    HStack {
                        Text("¥")
                        TextField("价格", value: $ticket.price, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    TextField("备注", text: $ticket.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("编辑车票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { initEditSeatState() }
            .onChange(of: editCarriage)    { _, v in ticket.carriageNumber = v }
            .onChange(of: editSeatRow)     { _, _ in syncSeatNumber() }
            .onChange(of: editSeatLetter)  { _, _ in syncSeatNumber() }
        }
    }

    // MARK: - 座位滚轮辅助
    private func initEditSeatState() {
        editCarriage = ticket.carriageNumber.isEmpty ? "01" : ticket.carriageNumber
        let seat = ticket.seatNumber
        let posChars = Set(["A","B","C","D","F","上","中","下"])
        if let last = seat.last, posChars.contains(String(last)) {
            editSeatLetter = String(last)
            let rowPart = String(seat.dropLast())
            editSeatRow = String(format: "%02d", Int(rowPart) ?? 1)
        } else {
            editSeatRow = "01"
            editSeatLetter = editLetterOptions(for: ticket.seatClass).first ?? "A"
        }
    }

    private func syncSeatNumber() {
        ticket.seatNumber = editSeatRow + editSeatLetter
    }

    private func editRowOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return (1...9).map  { String(format: "%02d", $0) }
        case "一等座":           return (1...18).map { String(format: "%02d", $0) }
        case "硬卧", "软卧", "动卧": return (1...12).map { String(format: "%02d", $0) }
        default:                 return (1...20).map { String(format: "%02d", $0) }
        }
    }

    private func editLetterOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return ["A", "C", "F"]
        case "一等座":           return ["A", "C", "D", "F"]
        case "硬卧":             return ["上", "中", "下"]
        case "软卧", "动卧":     return ["上", "下"]
        default:                 return ["A", "B", "C", "D", "F"]
        }
    }

    private var editIsSleeper: Bool {
        ["硬卧", "软卧", "动卧"].contains(ticket.seatClass)
    }
}
