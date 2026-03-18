import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let ocrUseCase = TicketOCRUseCase()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    @State private var isRecognizing = false
    @State private var progressMessage = "等待上传图片"
    @State private var progressEvents: [AddTicketOCRProgress] = []

    @State private var showError = false
    @State private var errorMessage = ""

    @State private var orderNumber = ""
    @State private var trainNumber = ""
    @State private var departureStation = ""
    @State private var arrivalStation = ""
    @State private var departureTime = Date()
    @State private var arrivalTime = Date().addingTimeInterval(2 * 3600)
    @State private var carriageNumber = "01"
    @State private var seatNumber = "01A"
    @State private var seatClass = "二等座"
    @State private var ticketType = ""
    @State private var passengerName = ""
    @State private var price: Double = 0
    @State private var notes = ""

    @State private var scheduleTrainDate = ""
    @State private var scheduleSourceURL = ""
    @State private var scheduleStopCount = 0
    @State private var rawLines: [String] = []

    @State private var seatRow = "01"
    @State private var seatLetter = "A"

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                progressSection
                basicSection
                timeSection
                seatSection
                otherSection
                rawTextSection
            }
            .navigationTitle("添加车票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isRecognizing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveTicket()
                    }
                    .disabled(!canSave || isRecognizing)
                }
            }
            .alert("识别失败", isPresented: $showError) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadSelectedPhoto(item: newItem)
                }
            }
            .onChange(of: seatClass) { _, newClass in
                if newClass == "无座" {
                    seatNumber = ""
                    carriageNumber = ""
                    return
                }

                if carriageNumber.isEmpty {
                    carriageNumber = "01"
                }

                let rows = rowOptions(for: newClass)
                if !rows.contains(seatRow) {
                    seatRow = rows.first ?? "01"
                }

                let letters = letterOptions(for: newClass)
                if !letters.contains(seatLetter) {
                    seatLetter = letters.first ?? "A"
                }

                syncSeatNumber()
            }
            .onChange(of: seatRow) { _, _ in
                syncSeatNumber()
            }
            .onChange(of: seatLetter) { _, _ in
                syncSeatNumber()
            }
        }
    }

    private var imageSection: some View {
        Section("车票图片") {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView {
                    Label("尚未选择图片", systemImage: "photo")
                } description: {
                    Text("选择一张车票图片后可自动识别")
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }

            Button {
                Task {
                    await runOCR()
                }
            } label: {
                if isRecognizing {
                    HStack {
                        ProgressView()
                        Text("识别中")
                    }
                } else {
                    Label("开始识别", systemImage: "sparkles.rectangle.stack")
                }
            }
            .disabled(selectedImage == nil || isRecognizing)
        }
    }

    private var progressSection: some View {
        Section("后端处理流程") {
            HStack {
                Text("状态")
                Spacer()
                Text(progressMessage)
                    .foregroundStyle(.secondary)
            }

            if !progressEvents.isEmpty {
                ForEach(progressEvents.indices, id: \.self) { index in
                    let event = progressEvents[index]
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: event.stage))
                            .foregroundStyle(color(for: event.stage))
                            .frame(width: 16)
                        Text(event.message)
                            .font(.footnote)
                    }
                }
            }

            if !scheduleSourceURL.isEmpty {
                HStack {
                    Text("时刻表站点")
                    Spacer()
                    Text("\(scheduleStopCount) 站")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("时刻表日期")
                    Spacer()
                    Text(scheduleTrainDate)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var basicSection: some View {
        Section("基础信息") {
            TextField("订单号", text: $orderNumber)
            TextField("车次", text: $trainNumber)
                .textInputAutocapitalization(.characters)
            TextField("出发站", text: $departureStation)
            TextField("到达站", text: $arrivalStation)
            TextField("票种", text: $ticketType)
            TextField("乘车人", text: $passengerName)
            HStack {
                Text("票价")
                Spacer()
                TextField("0", value: $price, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var timeSection: some View {
        Section("时间") {
            DatePicker("出发时间", selection: $departureTime)
            DatePicker("到达时间", selection: $arrivalTime)
        }
    }

    private var seatSection: some View {
        Section("座位") {
            Picker("坐席", selection: $seatClass) {
                ForEach(seatClassOptions, id: \.self) { item in
                    Text(item)
                }
            }

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
                            ForEach(rowOptions(for: seatClass), id: \.self) { opt in
                                Text(opt + (isSleeper(seatClass) ? "铺" : "排")).tag(opt)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipped()

                        Picker("席位", selection: $seatLetter) {
                            ForEach(letterOptions(for: seatClass), id: \.self) { opt in
                                Text(opt).tag(opt)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipped()
                    }
                }

                HStack {
                    Text("当前座位")
                    Spacer()
                    Text(formattedSeat)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var otherSection: some View {
        Section("备注") {
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var rawTextSection: some View {
        Section("OCR 原始文本") {
            if rawLines.isEmpty {
                Text("暂无")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rawLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                }
            }
        }
    }

    private var canSave: Bool {
        !trainNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !departureStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !arrivalStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var seatClassOptions: [String] {
        ["商务座", "一等座", "二等座", "特等座", "硬卧", "软卧", "硬座", "软座", "无座"]
    }

    private var formattedSeat: String {
        if seatClass == "无座" { return "无座" }
        return carriageNumber + "车" + seatNumber
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "图片读取失败"
                showError = true
                return
            }

            selectedImage = image
            progressMessage = "图片已就绪，点击开始识别"
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func runOCR() async {
        guard let image = selectedImage else {
            return
        }

        isRecognizing = true
        progressEvents.removeAll()
        progressMessage = "正在识别"

        do {
            let result = try await ocrUseCase.recognizeTicket(from: image, modelContext: modelContext) { progress in
                Task { @MainActor in
                    progressEvents.append(progress)
                    progressMessage = progress.message
                    applySnapshot(progress.snapshot)
                }
            }

            applySnapshot(result)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            progressMessage = "识别失败"
        }

        isRecognizing = false
    }

    private func applySnapshot(_ snapshot: AddTicketOCRResult) {
        if !snapshot.trainNumber.isEmpty {
            trainNumber = snapshot.trainNumber
        }
        if !snapshot.departureStation.isEmpty {
            departureStation = snapshot.departureStation
        }
        if !snapshot.arrivalStation.isEmpty {
            arrivalStation = snapshot.arrivalStation
        }
        if snapshot.departureTime != .distantPast {
            departureTime = snapshot.departureTime
        }
        if snapshot.arrivalTime != .distantPast {
            arrivalTime = snapshot.arrivalTime
        }
        if !snapshot.ticketType.isEmpty {
            ticketType = snapshot.ticketType
        }
        if !snapshot.seatClass.isEmpty {
            seatClass = snapshot.seatClass
        }
        if !snapshot.carriageNumber.isEmpty {
            carriageNumber = snapshot.carriageNumber
        }
        if !snapshot.seatNumber.isEmpty {
            seatNumber = snapshot.seatNumber
            parseSeatNumber(snapshot.seatNumber)
        }
        if snapshot.price > 0 {
            price = snapshot.price
        }

        scheduleTrainDate = snapshot.schedule.trainDate
        scheduleSourceURL = snapshot.schedule.sourceURL
        scheduleStopCount = snapshot.schedule.stops.count

        if !snapshot.rawLines.isEmpty {
            rawLines = snapshot.rawLines
        }
    }

    private func parseSeatNumber(_ value: String) {
        let marker = Set(["A", "B", "C", "D", "F", "上", "中", "下"])
        guard let last = value.last else { return }

        let lastString = String(last)
        if marker.contains(lastString) {
            let rowPart = String(value.dropLast())
            let parsed = String(format: "%02d", Int(rowPart) ?? 1)
            seatRow = parsed
            seatLetter = lastString
        }
    }

    private func syncSeatNumber() {
        guard seatClass != "无座" else {
            seatNumber = ""
            return
        }
        seatNumber = seatRow + seatLetter
    }

    private func rowOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return (1...9).map { String(format: "%02d", $0) }
        case "一等座": return (1...18).map { String(format: "%02d", $0) }
        case "硬卧", "软卧", "动卧": return (1...12).map { String(format: "%02d", $0) }
        default: return (1...20).map { String(format: "%02d", $0) }
        }
    }

    private func letterOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return ["A", "C", "F"]
        case "一等座": return ["A", "C", "D", "F"]
        case "硬卧": return ["上", "中", "下"]
        case "软卧", "动卧": return ["上", "下"]
        default: return ["A", "B", "C", "D", "F"]
        }
    }

    private func isSleeper(_ seatClass: String) -> Bool {
        ["硬卧", "软卧", "动卧"].contains(seatClass)
    }

    private func icon(for stage: AddTicketOCRStage) -> String {
        switch stage {
        case .preparing: return "hourglass"
        case .ocrCompleted: return "text.viewfinder"
        case .scheduleCompleted: return "map"
        case .finished: return "checkmark.circle.fill"
        }
    }

    private func color(for stage: AddTicketOCRStage) -> Color {
        switch stage {
        case .preparing: return .orange
        case .ocrCompleted: return .blue
        case .scheduleCompleted: return .mint
        case .finished: return .green
        }
    }

    private func saveTicket() {
        var ticket = Ticket(
            orderNumber: orderNumber,
            trainNumber: trainNumber,
            departureStation: departureStation,
            arrivalStation: arrivalStation,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            seatNumber: seatNumber,
            carriageNumber: carriageNumber,
            seatClass: seatClass,
            ticketType: ticketType,
            price: price,
            passengerName: passengerName,
            scheduleTrainDate: scheduleTrainDate,
            scheduleSourceURL: scheduleSourceURL,
            scheduleStopCount: scheduleStopCount,
            notes: notes
        )

        if let data = selectedImage?.jpegData(compressionQuality: 0.92) {
            ticket.ticketImageData = data
        }

        modelContext.insert(ticket)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    AddTicketView()
        .modelContainer(for: [Ticket.self, TrainScheduleCache.self], inMemory: true)
}
