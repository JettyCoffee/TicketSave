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
}

// MARK: - Edit Ticket View
struct EditTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var ticket: Ticket

    @State private var trainNumber = ""
    @State private var departureStation = ""
    @State private var arrivalStation = ""
    @State private var departureTime = Date()
    @State private var arrivalTime = Date()
    @State private var seatClass = "二等座"
    @State private var carriageNumber = "01"
    @State private var seatNumber = "01A"
    @State private var seatRow = "01"
    @State private var seatLetter = "A"
    @State private var ticketType = ""
    @State private var price: Double = 0
    @State private var notes = ""

    @State private var didLoadInitialValue = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("车次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("G123", text: $trainNumber)
                                .textInputAutocapitalization(.characters)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("票种")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("成人票", text: $ticketType)
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("出发站")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("北京南", text: $departureStation)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("到达站")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("上海虹桥", text: $arrivalStation)
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("票价（元）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", value: $price, format: .number)
                                .keyboardType(.decimalPad)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("坐席")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Menu {
                                ForEach(TicketSeatFormService.seatClassOptions, id: \.self) { item in
                                    Button(item) {
                                        seatClass = item
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(seatClass)
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Section("时间") {
                    DatePicker("出发时间", selection: $departureTime)
                    DatePicker("到达时间", selection: $arrivalTime)
                }

                Section("座位") {
                    if seatClass != "无座" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("车厢 / 排位 / 席位")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 0) {
                                Picker("车厢", selection: $carriageNumber) {
                                    ForEach((1...20).map { String(format: "%02d", $0) }, id: \.self) { opt in
                                        Text(opt + "车").tag(opt)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity, maxHeight: 110)
                                .clipped()

                                Picker("排位", selection: $seatRow) {
                                    ForEach(TicketSeatFormService.rowOptions(for: seatClass), id: \.self) { opt in
                                        Text(opt + (TicketSeatFormService.isSleeper(seatClass) ? "铺" : "排")).tag(opt)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity, maxHeight: 110)
                                .clipped()

                                Picker("席位", selection: $seatLetter) {
                                    ForEach(TicketSeatFormService.letterOptions(for: seatClass), id: \.self) { opt in
                                        Text(opt).tag(opt)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity, maxHeight: 110)
                                .clipped()
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑车票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        applyChanges()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard !didLoadInitialValue else { return }
                loadFromTicket()
                didLoadInitialValue = true
            }
            .onChange(of: seatClass) { _, newClass in
                let normalized = TicketSeatFormService.normalizeAfterSeatClassChange(
                    seatClass: newClass,
                    carriageNumber: carriageNumber,
                    seatRow: seatRow,
                    seatLetter: seatLetter
                )
                carriageNumber = normalized.carriageNumber
                seatRow = normalized.seatRow
                seatLetter = normalized.seatLetter
                seatNumber = normalized.seatNumber
            }
            .onChange(of: seatRow) { _, _ in
                syncSeatNumber()
            }
            .onChange(of: seatLetter) { _, _ in
                syncSeatNumber()
            }
        }
    }

    private var canSave: Bool {
        !trainNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !departureStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !arrivalStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadFromTicket() {
        trainNumber = ticket.trainNumber
        departureStation = ticket.departureStation
        arrivalStation = ticket.arrivalStation
        departureTime = ticket.departureTime
        arrivalTime = ticket.arrivalTime
        seatClass = ticket.seatClass
        carriageNumber = ticket.carriageNumber
        seatNumber = ticket.seatNumber
        ticketType = ticket.ticketType
        price = ticket.price
        notes = ticket.notes

        if let parsed = TicketSeatFormService.parseSeatNumber(ticket.seatNumber) {
            seatRow = parsed.seatRow
            seatLetter = parsed.seatLetter
        }

        let normalized = TicketSeatFormService.normalizeAfterSeatClassChange(
            seatClass: seatClass,
            carriageNumber: carriageNumber,
            seatRow: seatRow,
            seatLetter: seatLetter
        )
        carriageNumber = normalized.carriageNumber
        seatRow = normalized.seatRow
        seatLetter = normalized.seatLetter
        seatNumber = seatClass == "无座" ? "" : (ticket.seatNumber.isEmpty ? normalized.seatNumber : ticket.seatNumber)
    }

    private func syncSeatNumber() {
        seatNumber = TicketSeatFormService.syncSeatNumber(
            seatClass: seatClass,
            seatRow: seatRow,
            seatLetter: seatLetter
        )
    }

    private func applyChanges() {
        ticket.trainNumber = trainNumber
        ticket.departureStation = departureStation
        ticket.arrivalStation = arrivalStation
        ticket.departureTime = departureTime
        ticket.arrivalTime = arrivalTime
        ticket.seatClass = seatClass
        ticket.carriageNumber = carriageNumber
        ticket.seatNumber = seatNumber
        ticket.ticketType = ticketType
        ticket.price = price
        ticket.notes = notes
    }
}
