import Foundation
import UIKit
import Vision
import CoreImage

enum VisionTicketOCRError: LocalizedError {
    case invalidImage
    case visionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法读取"
        case .visionFailed: return "OCR 识别失败"
        }
    }
}

final class VisionTicketOCRService {
    private let ciContext = CIContext(options: nil)

    func recognize(from image: UIImage) async throws -> OCRTicketExtraction {
        guard let baseCG = image.cgImage else { throw VisionTicketOCRError.invalidImage }

        var merged = try await recognizeLines(in: baseCG)
        if let enhanced = enhancedImage(from: baseCG) {
            let enhancedLines = try await recognizeLines(in: enhanced)
            merged.append(contentsOf: enhancedLines)
        }

        let lines = deduplicate(lines: merged)
        let rawTexts = lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = OCRTicketExtraction()
        result.rawLines = rawTexts

        let parsedRoute = parseTrainAndStations(from: rawTexts)
        result.trainNumber = parsedRoute.train
        result.departureStation = parsedRoute.departure
        result.arrivalStation = parsedRoute.arrival
        result.departureTime = parseDepartureTime(from: rawTexts)

        let seat = parseCarriageAndSeat(from: rawTexts)
        result.carriageAndSeat = seat.display
        result.carriageNumber = seat.carriage
        result.seatNumber = seat.seat
        result.price = parsePrice(from: rawTexts)
        result.ticketType = parseTicketType(from: rawTexts)
        result.seatClass = parseSeatClass(from: rawTexts)

        return result
    }

    private struct OCRLine {
        let text: String
        let confidence: Float
        let box: CGRect
    }

    private func recognizeLines(in cgImage: CGImage) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines: [OCRLine] = observations.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return OCRLine(text: top.string, confidence: top.confidence, box: obs.boundingBox)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.015

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionTicketOCRError.visionFailed)
            }
        }
    }

    private func enhancedImage(from cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(ciImage, forKey: kCIInputImageKey)
        controls.setValue(1.35, forKey: kCIInputContrastKey)
        controls.setValue(0.02, forKey: kCIInputBrightnessKey)
        controls.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let controlled = controls.outputImage,
              let sharpen = CIFilter(name: "CISharpenLuminance") else {
            return nil
        }

        sharpen.setValue(controlled, forKey: kCIInputImageKey)
        sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)

        guard let output = sharpen.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    private func deduplicate(lines: [OCRLine]) -> [OCRLine] {
        var best: [String: OCRLine] = [:]

        for line in lines {
            let key = normalized(line.text)
            if key.isEmpty { continue }
            if let old = best[key] {
                if line.confidence > old.confidence {
                    best[key] = line
                }
            } else {
                best[key] = line
            }
        }

        return best.values.sorted { lhs, rhs in
            let dy = abs(lhs.box.midY - rhs.box.midY)
            if dy < 0.02 {
                return lhs.box.minX < rhs.box.minX
            }
            return lhs.box.midY > rhs.box.midY
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    private func firstMatch(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else { return nil }
        return ns.substring(with: match.range)
    }

    private func parseDepartureTime(from lines: [String]) -> Date {
        let pattern = #"(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .distantPast }

        for line in lines {
            let text = normalized(line)
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }

            let y = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let m = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let d = Int(ns.substring(with: match.range(at: 3))) ?? 0
            let hh = Int(ns.substring(with: match.range(at: 4))) ?? 0
            let mm = Int(ns.substring(with: match.range(at: 5))) ?? 0

            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = hh
            comps.minute = mm
            comps.second = 0
            comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return Calendar(identifier: .gregorian).date(from: comps) ?? .distantPast
        }

        return .distantPast
    }

    private func stationInText(_ value: String, preferLast: Bool) -> String {
        let pattern = #"[\u4e00-\u9fa5]{2,10}站"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: value, options: [], range: range)
        if matches.isEmpty { return "" }
        let idx = preferLast ? matches.count - 1 : 0
        return ns.substring(with: matches[idx].range)
    }

    private func parseTrainAndStations(from lines: [String]) -> (train: String, departure: String, arrival: String) {
        let trainPattern = #"[GDCZTKYLSP]\s*\d{1,4}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: trainPattern, options: [.caseInsensitive]) else {
            return ("", "", "")
        }

        for (idx, line) in lines.enumerated() {
            let text = normalized(line)
                .replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "I", with: "")
                .replacingOccurrences(of: "i", with: "")
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }

            let train = ns.substring(with: match.range).uppercased().replacingOccurrences(of: " ", with: "")
            let left = ns.substring(with: NSRange(location: 0, length: match.range.location))
            let rightStart = match.range.location + match.range.length
            let right = rightStart < ns.length ? ns.substring(from: rightStart) : ""

            var departure = stationInText(left, preferLast: true)
            var arrival = stationInText(right, preferLast: false)

            if departure.isEmpty, idx > 0 {
                for i in stride(from: idx - 1, through: 0, by: -1) {
                    let candidate = stationInText(normalized(lines[i]), preferLast: true)
                    if !candidate.isEmpty {
                        departure = candidate
                        break
                    }
                }
            }

            if arrival.isEmpty, idx + 1 < lines.count {
                for i in (idx + 1)..<lines.count {
                    let candidate = stationInText(normalized(lines[i]), preferLast: false)
                    if !candidate.isEmpty {
                        arrival = candidate
                        break
                    }
                }
            }

            if !train.isEmpty {
                return (train, departure, arrival)
            }
        }

        return ("", "", "")
    }

    private func parseCarriageAndSeat(from lines: [String]) -> (display: String, carriage: String, seat: String) {
        let pattern = #"(\d{1,2})[车年](\d{1,3}[A-Za-z上下中])号?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ("", "", "") }

        for line in lines {
            let text = normalized(line)
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }

            let carriage = ns.substring(with: match.range(at: 1))
            let seat = ns.substring(with: match.range(at: 2)).uppercased()
            let display = String(format: "%02d", Int(carriage) ?? 0) + "车" + seat + "号"
            return (display, String(format: "%02d", Int(carriage) ?? 0), seat)
        }

        return ("", "", "")
    }

    private func parsePrice(from lines: [String]) -> Double {
        for line in lines {
            let text = normalized(line)
            if let value = firstMatch(#"[¥￥]?\d+(?:\.\d{1,2})"#, in: text) {
                let cleaned = value
                    .replacingOccurrences(of: "¥", with: "")
                    .replacingOccurrences(of: "￥", with: "")
                if let amount = Double(cleaned), amount > 0 {
                    return amount
                }
            }
        }
        return 0
    }

    private func parseSeatClass(from lines: [String]) -> String {
        let classes = ["商务座", "特等座", "一等座", "二等座", "无座", "高级软卧", "软卧", "硬卧", "软座", "硬座"]
        let normalizedLines = lines.map(normalized)
        for cls in classes where normalizedLines.contains(where: { $0.contains(cls) }) {
            return cls
        }
        return ""
    }

    private func parseTicketType(from lines: [String]) -> String {
        let normalizedLines = lines.map(normalized)
        if normalizedLines.contains(where: { $0.contains("学惠") || $0.contains("学生") }) {
            return "学生票"
        }
        if normalizedLines.contains(where: { $0.contains("仅供报销使用") }) {
            return "报销票"
        }
        return ""
    }
}
