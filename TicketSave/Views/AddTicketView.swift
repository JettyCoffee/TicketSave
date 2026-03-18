import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Vision

struct AddTicketView: View {
    private enum AddTicketStep: Int, CaseIterable {
        case source
        case processing
        case review
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let ocrUseCase = TicketOCRUseCase()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var originalImage: UIImage?
    @State private var detectedTicketRect: CGRect?
    @State private var showCameraPicker = false

    @State private var currentStep: AddTicketStep = .source
    @State private var processingAnimating = false

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
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.98, green: 0.97, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch currentStep {
                    case .source:
                        sourceStepView
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .processing:
                        processingStepView
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .review:
                        reviewStepView
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.9), value: currentStep)
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
                    if currentStep == .review {
                        Button("保存") {
                            saveTicket()
                        }
                        .disabled(!canSave || isRecognizing)
                    }
                }
            }
            .alert("识别失败", isPresented: $showError) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraImagePicker { image in
                    Task {
                        await loadCapturedImage(image)
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadSelectedPhoto(item: newItem)
                }
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

    private var sourceStepView: some View {
        Form {
            Section("选择图片") {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                }

                Button {
                    showCameraPicker = true
                } label: {
                    Label("拍照上传", systemImage: "camera")
                }

                if let image = selectedImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自动纠正结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                    }
                } else {
                    ContentUnavailableView {
                        Label("尚未选择图片", systemImage: "photo")
                    } description: {
                        Text("先选择相册图片或直接拍照")
                    }
                }

                Button {
                    beginRecognition()
                } label: {
                    Label("开始识别", systemImage: "sparkles.rectangle.stack")
                }
                .disabled(selectedImage == nil || isRecognizing)
            }
        }
    }

    private var processingStepView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 10)
                    .frame(width: 88, height: 88)

                Circle()
                    .trim(from: 0.1, to: 0.8)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(processingAnimating ? 360 : 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: processingAnimating)

                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .padding(.top, 20)

            Text(progressMessage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("后端处理流程")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("状态")
                            Spacer()
                            Text(progressMessage)
                                .foregroundStyle(.secondary)
                        }

                        if !progressEvents.isEmpty {
                            ForEach(progressEvents.indices, id: \.self) { index in
                                let event = progressEvents[index]
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: icon(for: event.stage))
                                        .foregroundStyle(color(for: event.stage))
                                        .frame(width: 18)
                                    Text(event.message)
                                        .font(.footnote)
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        } else {
                            Text("正在提交并处理 OCR，请稍候...")
                                .foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .frame(maxHeight: 260)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            processingAnimating = true
        }
        .onDisappear {
            processingAnimating = false
        }
    }

    private var reviewStepView: some View {
        Form {
            Section("识别结果") {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("重新选择图片") {
                    withAnimation {
                        currentStep = .source
                    }
                }
            }
            basicSection
            timeSection
            seatSection
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
    }

    private var timeSection: some View {
        Section("时间") {
            DatePicker("出发时间", selection: $departureTime)
            DatePicker("到达时间", selection: $arrivalTime)
        }
    }

    private var seatSection: some View {
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

    private var canSave: Bool {
        !trainNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !departureStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !arrivalStation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedSeat: String {
        if seatClass == "无座" { return "无座" }
        return carriageNumber + "车" + seatNumber
    }

    private func beginRecognition() {
        guard selectedImage != nil else { return }
        withAnimation {
            currentStep = .processing
        }
        Task {
            await runOCR()
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                selectedImage = nil
                originalImage = nil
                detectedTicketRect = nil
                progressMessage = "等待上传图片"
            }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    errorMessage = "图片读取失败"
                    showError = true
                }
                return
            }

            await MainActor.run {
                originalImage = image
                progressMessage = "正在自动框选车票"
            }

            await autoDetectAndPrepareTicketImage(from: image)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func loadCapturedImage(_ image: UIImage?) async {
        guard let image else { return }

        await MainActor.run {
            selectedPhotoItem = nil
            originalImage = image
            progressMessage = "正在自动框选车票"
        }

        await autoDetectAndPrepareTicketImage(from: image)
    }

    private func autoDetectAndPrepareTicketImage(from image: UIImage) async {
        let rect = await detectTicketRect(in: image)
        await MainActor.run {
            detectedTicketRect = rect
            refreshSelectedImageFromCrop()
            if rect == nil {
                progressMessage = "未检测到车票边界，已使用整图（可直接识别）"
            } else {
                progressMessage = "已自动框选车票，可直接识别"
            }
            withAnimation {
                currentStep = .source
            }
        }
    }

    private func refreshSelectedImageFromCrop() {
        guard let base = originalImage else {
            selectedImage = nil
            return
        }

        let ticketRect = detectedTicketRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        if let cropped = crop(image: base, normalizedRect: ticketRect) {
            selectedImage = normalizeToLandscape(cropped)
        } else {
            selectedImage = normalizeToLandscape(base)
        }
    }

    private func detectTicketRect(in image: UIImage) async -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { req, _ in
                let observations = req.results as? [VNRectangleObservation] ?? []

                let best = observations
                    .filter { $0.boundingBox.width > 0.35 && $0.boundingBox.height > 0.12 }
                    .max { lhs, rhs in
                        (lhs.boundingBox.width * lhs.boundingBox.height)
                        < (rhs.boundingBox.width * rhs.boundingBox.height)
                    }

                continuation.resume(returning: best?.boundingBox)
            }

            request.maximumObservations = 6
            request.minimumConfidence = 0.3
            request.minimumSize = 0.15
            request.minimumAspectRatio = 1.2
            request.quadratureTolerance = 25

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func crop(image: UIImage, normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision boundingBox 原点在左下，CoreGraphics 裁剪原点在左上，需要翻转 Y。
        let x = normalizedRect.minX * width
        let y = (1.0 - normalizedRect.maxY) * height
        let w = normalizedRect.width * width
        let h = normalizedRect.height * height

        let pixelRect = CGRect(x: x, y: y, width: w, height: h).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }

        return UIImage(cgImage: cropped)
    }

    private func normalizeToLandscape(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedImage()
        guard normalized.size.height > normalized.size.width else {
            return normalized
        }
        return normalized.rotatedClockwise90()
    }

    private func runOCR() async {
        guard let image = selectedImage else {
            await MainActor.run {
                withAnimation {
                    currentStep = .source
                }
            }
            return
        }

        await MainActor.run {
            isRecognizing = true
            progressEvents.removeAll()
            progressMessage = "正在识别"
        }

        do {
            let result = try await ocrUseCase.recognizeTicket(from: image, modelContext: modelContext) { progress in
                Task { @MainActor in
                    withAnimation {
                        progressEvents.append(progress)
                    }
                    progressMessage = progress.message
                    applySnapshot(progress.snapshot)
                }
            }

            await MainActor.run {
                applySnapshot(result)
                isRecognizing = false
                withAnimation {
                    currentStep = .review
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                progressMessage = "识别失败"
                isRecognizing = false
                withAnimation {
                    currentStep = .source
                }
            }
        }
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
        guard let parsed = TicketSeatFormService.parseSeatNumber(value) else { return }
        seatRow = parsed.seatRow
        seatLetter = parsed.seatLetter
    }

    private func syncSeatNumber() {
        seatNumber = TicketSeatFormService.syncSeatNumber(
            seatClass: seatClass,
            seatRow: seatRow,
            seatLetter: seatLetter
        )
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

private extension UIImage {
    func normalizedImage() -> UIImage {
        if imageOrientation == .up { return self }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func rotatedClockwise90() -> UIImage {
        let targetSize = CGSize(width: size.height, height: size.width)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            cg.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    var onPicked: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onPicked: (UIImage?) -> Void

        init(onPicked: @escaping (UIImage?) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPicked(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onPicked(image)
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    AddTicketView()
        .modelContainer(for: [Ticket.self, TrainScheduleCache.self], inMemory: true)
}
