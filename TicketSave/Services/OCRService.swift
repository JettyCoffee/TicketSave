import Vision
import UIKit

struct OCRService: Sendable {
    static func recognizeTicket(from image: UIImage) async throws -> TicketInfo {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let recognizedText = try await performOCR(on: cgImage)
        return parseTicketInfo(from: recognizedText)
    }

    private static func performOCR(on image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let texts = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                continuation.resume(returning: texts)
            }
            request.recognitionLanguages = ["zh-Hans", "en"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func parseTicketInfo(from texts: [String]) -> TicketInfo {
        var info = TicketInfo()
        let joined = texts.joined(separator: " ")

        // 车次号: G/D/C/Z/T/K + 数字
        if let trainMatch = joined.range(of: #"[GDCZTK]\d{1,4}"#, options: .regularExpression) {
            info.trainNumber = String(joined[trainMatch])
        }

        // 座位号: 数车厢+座位 e.g. "05车06A号" or "5车6A"
        if let seatMatch = joined.range(of: #"\d{1,2}车\d{1,3}[A-F]号?"#, options: .regularExpression) {
            info.seatNumber = String(joined[seatMatch]).replacingOccurrences(of: "号", with: "")
        }

        // 价格: ¥xxx.x or xxx.0元
        if let priceMatch = joined.range(of: #"[¥￥]?\d+\.\d{1,2}元?"#, options: .regularExpression) {
            let priceStr = String(joined[priceMatch])
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "￥", with: "")
                .replacingOccurrences(of: "元", with: "")
            info.price = Double(priceStr) ?? 0
        }

        // 坐席类型
        let seatTypes = ["商务座", "一等座", "二等座", "特等座", "硬卧", "软卧", "硬座", "软座", "无座", "高级软卧"]
        for seatType in seatTypes {
            if joined.contains(seatType) {
                info.seatClass = seatType
                break
            }
        }

        // 检票口
        if let gateMatch = joined.range(of: #"[检验]票口?\s*[:：]?\s*[A-Z]?\d{1,3}[A-Z]?"#, options: .regularExpression) {
            let gateStr = String(joined[gateMatch])
            if let numMatch = gateStr.range(of: #"[A-Z]?\d{1,3}[A-Z]?"#, options: .regularExpression) {
                info.checkGate = String(gateStr[numMatch])
            }
        }

        // 订单号 / 序号: E+数字
        if let orderMatch = joined.range(of: #"E\d{8,}"#, options: .regularExpression) {
            info.orderNumber = String(joined[orderMatch])
        }

        // 站名提取: 寻找 "X站—Y站" 或 "X—Y" 模式
        if let routeMatch = joined.range(of: #"[\u4e00-\u9fa5]{2,6}(?:站)?\s*[-—→~]\s*[\u4e00-\u9fa5]{2,6}(?:站)?"#, options: .regularExpression) {
            let route = String(joined[routeMatch])
            let parts = route.components(separatedBy: CharacterSet(charactersIn: "-—→~"))
            if parts.count >= 2 {
                info.departureStation = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "站", with: "")
                info.arrivalStation = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "站", with: "")
            }
        }

        // 日期时间: 2024年01月01日 08:00
        if let dateMatch = joined.range(of: #"\d{4}年\d{1,2}月\d{1,2}日\s*\d{1,2}[：:]\d{2}"#, options: .regularExpression) {
            let dateStr = String(joined[dateMatch])
                .replacingOccurrences(of: "：", with: ":")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            if let date = formatter.date(from: dateStr) {
                info.departureTime = date
            }
        }

        // 姓名
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 && trimmed.count <= 4 {
                let isAllChinese = trimmed.unicodeScalars.allSatisfy { scalar in
                    (0x4E00...0x9FFF).contains(scalar.value)
                }
                if isAllChinese && !seatTypes.contains(trimmed) &&
                    !trimmed.contains("车") && !trimmed.contains("站") &&
                    StationDatabase.shared.lookup(trimmed) == nil {
                    info.passengerName = trimmed
                    break
                }
            }
        }

        return info
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法处理该图片"
        case .recognitionFailed: return "文字识别失败"
        }
    }
}
