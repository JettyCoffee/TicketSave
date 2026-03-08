import SwiftUI
import PhotosUI
import SwiftData

struct AddTicketView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var trainNumber = ""
    @State private var orderNumber = ""
    @State private var departureStation = ""
    @State private var arrivalStation = ""
    @State private var departureTime = Date()
    @State private var arrivalTime = Date().addingTimeInterval(3600)
    @State private var seatNumber = ""
    @State private var seatClass = "二等座"
    @State private var price: Double = 0
    @State private var checkGate = ""
    @State private var passengerName = ""
    @State private var notes = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isProcessingOCR = false
    @State private var ocrError: String?
    @State private var showCamera = false
    @State private var showOCRResult = false

    let seatClasses = ["商务座", "一等座", "二等座", "特等座", "硬卧", "软卧", "硬座", "软座", "无座"]

    var body: some View {
        NavigationStack {
            Form {
                // 扫描/导入区域
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 28))
                                Text("从相册选择")
                                    .font(.system(size: 12))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showCamera = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28))
                                Text("拍照识别")
                                    .font(.system(size: 12))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    if isProcessingOCR {
                        HStack {
                            ProgressView()
                            Text("正在识别车票信息...")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = ocrError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } header: {
                    Text("智能识别")
                } footer: {
                    Text("拍照或从相册选择车票图片，自动识别车票信息")
                }

                // 车次信息
                Section("车次信息") {
                    TextField("车次号 (如 G1234)", text: $trainNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("订单号", text: $orderNumber)
                }

                // 行程
                Section("行程") {
                    TextField("出发站", text: $departureStation)
                    TextField("到达站", text: $arrivalStation)
                    DatePicker("出发时间", selection: $departureTime)
                    DatePicker("到达时间", selection: $arrivalTime)
                }

                // 座位
                Section("座位信息") {
                    TextField("座位号 (如 05车12A)", text: $seatNumber)
                    Picker("坐席类型", selection: $seatClass) {
                        ForEach(seatClasses, id: \.self) { Text($0) }
                    }
                    TextField("检票口", text: $checkGate)
                }

                // 其他
                Section("其他信息") {
                    TextField("乘客姓名", text: $passengerName)
                    HStack {
                        Text("¥")
                        TextField("票价", value: $price, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // 预览
                if !trainNumber.isEmpty && !departureStation.isEmpty {
                    Section("预览") {
                        TicketCardView(ticket: previewTicket, compact: true)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
            }
            .navigationTitle("添加车票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveTicket() }
                        .disabled(trainNumber.isEmpty || departureStation.isEmpty || arrivalStation.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    selectedImage = image
                    Task { await processOCR(image: image) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var previewTicket: Ticket {
        Ticket(
            orderNumber: orderNumber,
            trainNumber: trainNumber,
            departureStation: departureStation,
            arrivalStation: arrivalStation,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            seatNumber: seatNumber,
            seatClass: seatClass,
            price: price,
            checkGate: checkGate,
            passengerName: passengerName,
            notes: notes
        )
    }

    private func saveTicket() {
        let ticket = Ticket(
            orderNumber: orderNumber,
            trainNumber: trainNumber,
            departureStation: departureStation,
            arrivalStation: arrivalStation,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            seatNumber: seatNumber,
            seatClass: seatClass,
            price: price,
            checkGate: checkGate,
            passengerName: passengerName,
            notes: notes
        )
        if let image = selectedImage, let data = image.jpegData(compressionQuality: 0.7) {
            ticket.ticketImageData = data
        }
        modelContext.insert(ticket)
        dismiss()
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        selectedImage = image
        await processOCR(image: image)
    }

    private func processOCR(image: UIImage) async {
        isProcessingOCR = true
        ocrError = nil
        do {
            let info = try await OCRService.recognizeTicket(from: image)
            applyOCRResult(info)
            showOCRResult = true
        } catch {
            ocrError = "识别失败: \(error.localizedDescription)"
        }
        isProcessingOCR = false
    }

    private func applyOCRResult(_ info: TicketInfo) {
        if !info.trainNumber.isEmpty { trainNumber = info.trainNumber }
        if !info.departureStation.isEmpty { departureStation = info.departureStation }
        if !info.arrivalStation.isEmpty { arrivalStation = info.arrivalStation }
        if !info.seatNumber.isEmpty { seatNumber = info.seatNumber }
        if !info.seatClass.isEmpty { seatClass = info.seatClass }
        if info.price > 0 { price = info.price }
        if !info.checkGate.isEmpty { checkGate = info.checkGate }
        if !info.passengerName.isEmpty { passengerName = info.passengerName }
        if !info.orderNumber.isEmpty { orderNumber = info.orderNumber }
        if info.departureTime != Date.distantPast {
            departureTime = info.departureTime
            arrivalTime = info.departureTime.addingTimeInterval(3600)
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
