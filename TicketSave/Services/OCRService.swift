import Vision
import UIKit

// MARK: - OCR 识别结果（带候选文本和位置信息）
struct RecognizedBlock: Sendable {
    let text: String
    let normalizedRect: CGRect   // Vision 坐标 (0,0) = 左下角
    var topY: CGFloat { 1 - normalizedRect.maxY }   // 转为从上到下的 y
}

struct OCRService: Sendable {

    /// 主入口：识别图片 → 解析 TicketInfo（不包含到站时间，需后续通过 TrainAPIService 补全）
    static func recognizeTicket(from image: UIImage) async throws -> TicketInfo {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        let blocks = try await performOCR(on: cgImage)
        return parseTicketInfo(from: blocks)
    }

    // MARK: - Vision OCR（保留位置信息）
    private static func performOCR(on image: CGImage) async throws -> [RecognizedBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let blocks: [RecognizedBlock] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return RecognizedBlock(text: candidate.string, normalizedRect: obs.boundingBox)
                }
                // 按从上到下排序
                continuation.resume(returning: blocks.sorted { $0.topY < $1.topY })
            }
            request.recognitionLanguages = ["zh-Hans", "en"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // 关闭自动纠错，避免站名被修改
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - 解析逻辑
    // 票面结构（从上到下）：
    // [订单号/序号]  （红色小字，e.g. Z13C017467 或 Exxxxxxxx）
    // [出发站名] [车次] [到达站名]   <- 最大字号行
    // [英文站名]         [英文站名]
    // [yyyy年mm月dd日 HH:MM开]    [车厢座位号]
    // [¥价格元]   [坐席类型]
    // ...
    // [身份证号+姓名]
    private static func parseTicketInfo(from blocks: [RecognizedBlock]) -> TicketInfo {
        var info = TicketInfo()
        let texts = blocks.map(\.text)
        let joined = texts.joined(separator: " ")

        // ── 1. 订单/序号：票面左上角红色编号
        //    格式 1: Z/E/D/F + 字母数字，长度 ≥ 8
        //    格式 2: 32位数字串（条形码下方）
        let orderPatterns = [
            #"[ZEDF][A-Z0-9]{7,}"#,           // e.g. Z13C017467 / E123456789
            #"\b[0-9]{18,}\b"#,               // 长数字序号（部分车票）
        ]
        for pattern in orderPatterns {
            if let m = joined.range(of: pattern, options: .regularExpression) {
                let candidate = String(joined[m])
                // 排除身份证号（纯数字18位且含X）
                if !candidate.hasSuffix("X") && !candidate.hasSuffix("x") {
                    info.orderNumber = candidate
                    break
                }
            }
        }

        // ── 2. 车次号：G/D/C/Z/T/K/S + 1~4位数字
        //    12306 网站车次格式严格，优先全词匹配
        let trainPatterns = [
            #"\b([GDCZTKS]\d{1,4})\b"#,
            #"([GDCZTKS]\d{1,4})"#,
        ]
        for pattern in trainPatterns {
            if let m = joined.range(of: pattern, options: .regularExpression) {
                let raw = String(joined[m])
                // 过滤掉明显是订单号一部分的情况
                if raw.count <= 6 {
                    info.trainNumber = raw
                    break
                }
            }
        }

        // ── 3. 出发站 / 到达站
        //    策略A：直接检测 "XX站" 紧跟 "XX站"（同行）
        //    策略B：在车次号两侧查找中文站名块
        //    策略C：找含 "站" 字的独立块
        extractStations(from: blocks, trainNumber: info.trainNumber, into: &info)

        // ── 4. 出发时间：yyyy年m月d日 HH:MM开
        let datePatterns = [
            #"(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日\s*(\d{1,2})[：:·](\d{2})\s*开?"#,
            #"(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})"#,
        ]
        for pattern in datePatterns {
            let nsJoined = joined as NSString
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
               match.numberOfRanges >= 6 {
                let year   = nsJoined.substring(with: match.range(at: 1))
                let month  = nsJoined.substring(with: match.range(at: 2))
                let day    = nsJoined.substring(with: match.range(at: 3))
                let hour   = nsJoined.substring(with: match.range(at: 4))
                let minute = nsJoined.substring(with: match.range(at: 5))
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-M-d HH:mm"
                fmt.locale = Locale(identifier: "zh_CN")
                if let date = fmt.date(from: "\(year)-\(month)-\(day) \(hour):\(minute)") {
                    info.departureTime = date
                    // 到站时间由 TrainAPIService 补全，先默认 +2h
                    info.arrivalTime = date.addingTimeInterval(7200)
                    break
                }
            }
        }

        // ── 5. 座位号：票面格式 "06车12F号" 或 "05车06A号"
        //    注意：座位字母包含 A-F，偶有 L（连续坐席）
        let seatPatterns = [
            #"(\d{1,2})车(\d{1,3}[A-FL])号?"#,       // 06车12F号
            #"(\d{1,2})-(\d{1,3})([A-FL])"#,          // 06-12F
        ]
        for pattern in seatPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
               match.numberOfRanges >= 3,
               let carRange = Range(match.range(at: 1), in: joined),
               let seatRange = Range(match.range(at: 2), in: joined) {
                let car = String(joined[carRange])
                let seat = String(joined[seatRange])
                // 可能还有字母分组范围3
                var seatLetter = ""
                if match.numberOfRanges >= 4, let letterRange = Range(match.range(at: 3), in: joined) {
                    seatLetter = String(joined[letterRange])
                }
                info.carriageNumber = String(format: "%02d", Int(car) ?? 1)
                info.seatNumber = "\(seat)\(seatLetter)"
                break
            }
        }
        // 若上面未匹配，尝试独立字段如 "12F号"
        if info.seatNumber.isEmpty {
            if let m = joined.range(of: #"\d{1,3}[A-FL]号?"#, options: .regularExpression) {
                info.seatNumber = String(joined[m]).replacingOccurrences(of: "号", with: "")
            }
        }

        // ── 6. 价格：¥65.0元 / ¥65.00 / 65.0元
        let pricePatterns = [
            #"[¥￥]\s*(\d+(?:\.\d{1,2})?)元?"#,
            #"(\d+\.\d{1,2})元"#,
        ]
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
               match.numberOfRanges >= 2,
               let priceRange = Range(match.range(at: 1), in: joined) {
                if let price = Double(String(joined[priceRange])) {
                    info.price = price
                    break
                }
            }
        }

        // ── 7. 坐席类型（按票面覆盖度排序）
        let seatClasses = ["高级软卧", "软卧", "硬卧", "商务座", "特等座", "一等座", "二等座", "硬座", "软座", "无座", "动卧"]
        for cls in seatClasses {
            if joined.contains(cls) {
                info.seatClass = cls
                break
            }
        }

        // ── 8. 检票口：候补检票口格式 "X检票口" / "检票口X"
        let gatePatterns = [
            #"([A-Z]\d{1,2})\s*(?:检票口|候车|检票)"#,
            #"(?:检票口|候车室)\s*:?\s*([A-Z]\d{0,2}|\d{1,2})"#,
        ]
        for pattern in gatePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
               match.numberOfRanges >= 2,
               let gateRange = Range(match.range(at: 1), in: joined) {
                info.checkGate = String(joined[gateRange])
                break
            }
        }

        // ── 9. 乘客姓名：位于身份证号之后，纯中文2-4字
        //    票面格式：450103200****0019 陈子谦（身份证 + 空格 + 姓名）
        extractPassengerName(from: texts, seatClasses: seatClasses, into: &info)

        return info
    }

    // MARK: - 站名提取（多策略）
    private static func extractStations(from blocks: [RecognizedBlock], trainNumber: String, into info: inout TicketInfo) {
        let texts = blocks.map(\.text)
        let joined = texts.joined(separator: " ")

        // 策略A：找出所有包含 "站" 的块，e.g. "杭州东站" "上海南站"
        var stationBlocks = blocks.filter {
            $0.text.hasSuffix("站") && $0.text.count >= 3 && $0.text != "车站"
        }

        // 如果找到2个以上带"站"的块，按水平位置确定出发/到达
        if stationBlocks.count >= 2 {
            // 按 x 中心排序
            stationBlocks.sort { $0.normalizedRect.midX < $1.normalizedRect.midX }
            let depRaw = stationBlocks[0].text.replacingOccurrences(of: "站", with: "")
            let arrRaw = stationBlocks[1].text.replacingOccurrences(of: "站", with: "")
            info.departureStation = normalizeStationName(depRaw)
            info.arrivalStation = normalizeStationName(arrRaw)
            return
        }

        // 策略B：不带"站"的站名，查数据库
        if stationBlocks.isEmpty {
            var candidates: [RecognizedBlock] = []
            for block in blocks {
                let clean = block.text.replacingOccurrences(of: "站", with: "")
                if clean.count >= 2 && clean.count <= 6 {
                    let allChinese = clean.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
                    if allChinese {
                        candidates.append(block)
                    }
                }
            }
            if candidates.count >= 2 {
                candidates.sort { $0.normalizedRect.midX < $1.normalizedRect.midX }
                info.departureStation = normalizeStationName(candidates[0].text)
                info.arrivalStation = normalizeStationName(candidates[1].text)
                return
            }
        }

        // 策略C：正则匹配 "XX站 车次 XX站" 模式或 "XX→XX"
        let routePatterns = [
            #"([\u4e00-\u9fa5]{2,6}站)\s+[GDCZTKS]\d{1,4}\s+([\u4e00-\u9fa5]{2,6}站)"#,
            #"([\u4e00-\u9fa5]{2,6})\s*[-—→]\s*([\u4e00-\u9fa5]{2,6})"#,
        ]
        for pattern in routePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
               match.numberOfRanges >= 3,
               let depRange = Range(match.range(at: 1), in: joined),
               let arrRange = Range(match.range(at: 2), in: joined) {
                info.departureStation = normalizeStationName(String(joined[depRange]))
                info.arrivalStation = normalizeStationName(String(joined[arrRange]))
                return
            }
        }
    }

    // MARK: - 乘客姓名提取
    private static func extractPassengerName(from texts: [String], seatClasses: [String], into info: inout TicketInfo) {
        // 策略A：身份证号后跟着的中文名字
        // 身份证格式：6位地区+8位出生+4位序列，中间可能有 * 遮挡
        let idPattern = #"\d{6}(?:\d{8}|\d{4}\*{4})\*{0,4}\d{0,4}[Xx]?\s+([\u4e00-\u9fa5]{2,4})"#
        let joined = texts.joined(separator: " ")
        if let regex = try? NSRegularExpression(pattern: idPattern),
           let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
           match.numberOfRanges >= 2,
           let nameRange = Range(match.range(at: 1), in: joined) {
            info.passengerName = String(joined[nameRange])
            return
        }

        // 策略B：找独立的2-4字纯中文词，排除已知关键词
        let excludeKeywords: Set<String> = Set(seatClasses + ["仅供", "报销", "使用", "遗失", "不补", "改签", "退票", "车站", "乘客"])
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if (2...4).contains(trimmed.count) {
                let allChinese = trimmed.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
                if allChinese && !excludeKeywords.contains(trimmed) {
                    info.passengerName = trimmed
                    return
                }
            }
        }
    }
    // MARK: - 站名规范化：通过本地数据库模糊比对，剪除 OCR 噪声（如“车站”字样）
    private static func normalizeStationName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "站", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 2 else { return raw }
        // 精确匹配
        if StationDatabase.shared.lookup(stripped) != nil { return stripped }
        // 前缀模糊匹配
        let matches = StationDatabase.shared.fuzzyLookup(stripped, maxResults: 1)
        return matches.first?.name ?? stripped
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
