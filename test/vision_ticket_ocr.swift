#!/usr/bin/env swift

import Foundation
import Vision
import AppKit
import CoreImage

struct OCRLine {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

struct TicketFields: Codable {
    var image: String
    var departureStation: String?
    var trainNumber: String?
    var arrivalStation: String?
    var departureTime: String?
    var carriageAndSeat: String?
    var price: String?
    var ticketType: String?
    var seatClass: String?
    var rawLines: [String]
}

enum OCRTicketError: Error {
    case loadImageFailed(String)
    case cgImageConversionFailed(String)
}

func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: "\t", with: "")
}

func cgImage(from path: String) -> CGImage? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

func enhancedImage(from cgImage: CGImage) -> CGImage? {
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

    guard let out = sharpen.outputImage else { return nil }
    let context = CIContext(options: nil)
    return context.createCGImage(out, from: out.extent)
}

func runVisionOCR(cgImage: CGImage) throws -> [OCRLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.015

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    let observations = request.results ?? []
    var lines: [OCRLine] = []
    lines.reserveCapacity(observations.count)

    for obs in observations {
        guard let top = obs.topCandidates(1).first else { continue }
        lines.append(OCRLine(text: top.string, confidence: top.confidence, boundingBox: obs.boundingBox))
    }

    return lines
}

func deduplicate(lines: [OCRLine]) -> [OCRLine] {
    var bestByText: [String: OCRLine] = [:]
    for line in lines {
        let key = normalize(line.text)
        if key.isEmpty { continue }
        if let old = bestByText[key] {
            if line.confidence > old.confidence {
                bestByText[key] = line
            }
        } else {
            bestByText[key] = line
        }
    }

    return bestByText.values.sorted {
        let dy = abs($0.boundingBox.midY - $1.boundingBox.midY)
        if dy < 0.02 {
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        return $0.boundingBox.midY > $1.boundingBox.midY
    }
}

func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return nil
    }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let m = regex.firstMatch(in: text, options: [], range: range) else {
        return nil
    }
    return ns.substring(with: m.range)
}

func parseDepartureTime(from lines: [String]) -> String? {
    let pattern = #"(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日\s*(\d{1,2}):(\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    for line in lines {
        let text = normalize(line)
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, options: [], range: range) else { continue }
        let y = ns.substring(with: m.range(at: 1))
        let mo = String(format: "%02d", Int(ns.substring(with: m.range(at: 2))) ?? 0)
        let d = String(format: "%02d", Int(ns.substring(with: m.range(at: 3))) ?? 0)
        let h = String(format: "%02d", Int(ns.substring(with: m.range(at: 4))) ?? 0)
        let mi = ns.substring(with: m.range(at: 5))
        return "\(y)-\(mo)-\(d) \(h):\(mi)"
    }

    return nil
}

func stationInText(_ text: String, preferLast: Bool) -> String? {
    let pattern = #"[\u4e00-\u9fa5]{2,10}站"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    let matches = regex.matches(in: text, options: [], range: range)
    if matches.isEmpty { return nil }
    let idx = preferLast ? matches.count - 1 : 0
    return ns.substring(with: matches[idx].range)
}

func parseTrainAndStations(from lines: [String]) -> (String?, String?, String?) {
    let trainPattern = #"[GDCZTKYLSP]\s*\d{1,4}(?!\d)"#
    guard let trainRegex = try? NSRegularExpression(pattern: trainPattern, options: [.caseInsensitive]) else {
        return (nil, nil, nil)
    }

    for (idx, line) in lines.enumerated() {
        let raw = line
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "I", with: "")
            .replacingOccurrences(of: "i", with: "")
        let text = normalize(raw)
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = trainRegex.firstMatch(in: text, options: [], range: range) else { continue }

        let train = ns.substring(with: m.range).uppercased().replacingOccurrences(of: " ", with: "")
        let left = ns.substring(with: NSRange(location: 0, length: m.range.location))
        let rightStart = m.range.location + m.range.length
        let right = rightStart < ns.length ? ns.substring(from: rightStart) : ""

        var dep = stationInText(left, preferLast: true)
        var arr = stationInText(right, preferLast: false)

        if dep == nil, idx > 0 {
            for i in stride(from: idx - 1, through: 0, by: -1) {
                if let s = stationInText(normalize(lines[i]), preferLast: true) {
                    dep = s
                    break
                }
            }
        }

        if arr == nil, idx + 1 < lines.count {
            for i in (idx + 1)..<lines.count {
                if let s = stationInText(normalize(lines[i]), preferLast: false) {
                    arr = s
                    break
                }
            }
        }

        if dep != nil || arr != nil {
            return (train, dep, arr)
        }
    }

    return (nil, nil, nil)
}

func parseCarriageAndSeat(from lines: [String]) -> String? {
    for line in lines {
        let text = normalize(line)
        if let m = firstMatch(#"(\d{1,2})[车年](\d{1,3}[A-Za-z])号"#, in: text) {
            guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})[车年](\d{1,3}[A-Za-z])号"#) else {
                return m
            }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let mm = regex.firstMatch(in: text, options: [], range: range) {
                let car = ns.substring(with: mm.range(at: 1))
                let seat = ns.substring(with: mm.range(at: 2)).uppercased()
                return "\(car)车\(seat)号"
            }
            return m.replacingOccurrences(of: "年", with: "车")
        }
        if let m = firstMatch(#"\d{1,2}车\d{1,3}[A-Za-z]座"#, in: text) {
            return m.replacingOccurrences(of: "座", with: "号")
        }
    }
    return nil
}

func parsePrice(from lines: [String]) -> String? {
    for line in lines {
        let text = normalize(line)
        if let m = firstMatch(#"[¥￥]\s*\d+(?:\.\d{1,2})?"#, in: text) {
            return m.replacingOccurrences(of: "￥", with: "¥")
                .replacingOccurrences(of: " ", with: "")
        }
    }
    return nil
}

func parseSeatClass(from lines: [String]) -> String? {
    let classes = ["商务座", "特等座", "一等座", "二等座", "无座", "高级软卧", "软卧", "硬卧", "软座", "硬座"]
    let normalized = lines.map(normalize)
    for cls in classes {
        if normalized.contains(where: { $0.contains(cls) }) {
            return cls
        }
    }
    return nil
}

func parseTicketType(from lines: [String]) -> String? {
    let normalized = lines.map(normalize)
    if normalized.contains(where: { $0.contains("仅供报销使用") }) {
        return "报销票"
    }
    if normalized.contains(where: { $0.contains("电子客票") }) {
        return "电子客票"
    }
    return nil
}

func recognizeTicket(at imagePath: String) throws -> TicketFields {
    guard let baseImage = cgImage(from: imagePath) else {
        throw OCRTicketError.loadImageFailed(imagePath)
    }

    var merged: [OCRLine] = []
    merged.append(contentsOf: try runVisionOCR(cgImage: baseImage))

    if let enhanced = enhancedImage(from: baseImage) {
        merged.append(contentsOf: try runVisionOCR(cgImage: enhanced))
    }

    let lines = deduplicate(lines: merged)
    let texts = lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    let (train, dep, arr) = parseTrainAndStations(from: texts)

    return TicketFields(
        image: URL(fileURLWithPath: imagePath).lastPathComponent,
        departureStation: dep,
        trainNumber: train,
        arrivalStation: arr,
        departureTime: parseDepartureTime(from: texts),
        carriageAndSeat: parseCarriageAndSeat(from: texts),
        price: parsePrice(from: texts),
        ticketType: parseTicketType(from: texts),
        seatClass: parseSeatClass(from: texts),
        rawLines: texts
    )
}

func listImagesFromArgsOrDefault() -> [String] {
    let args = Array(CommandLine.arguments.dropFirst())
    if !args.isEmpty {
        return args
    }

    let cwd = FileManager.default.currentDirectoryPath
    let testDir = cwd.hasSuffix("/test") ? cwd : cwd + "/test"
    let names = (try? FileManager.default.contentsOfDirectory(atPath: testDir)) ?? []
    let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    return names
        .filter { exts.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        .sorted()
        .map { testDir + "/" + $0 }
}

let images = listImagesFromArgsOrDefault()
if images.isEmpty {
    fputs("No images found. Put images under test/ or pass paths as arguments.\n", stderr)
    exit(1)
}

var results: [TicketFields] = []
for imagePath in images {
    do {
        let r = try recognizeTicket(at: imagePath)
        results.append(r)
    } catch {
        fputs("Failed to parse \(imagePath): \(error)\n", stderr)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
if let data = try? encoder.encode(results), let json = String(data: data, encoding: .utf8) {
    print(json)
} else {
    fputs("Encode result failed\n", stderr)
    exit(1)
}
