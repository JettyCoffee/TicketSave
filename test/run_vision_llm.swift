import Foundation
import Vision
import CoreImage
import AppKit

// --- LLMRouterService Mock/Copy ---
func parseTicketInfo(from text: String) async throws -> String {
    let prompt = """
    你是一个高铁火车票信息提取助手。请从下面这段 OCR 识别出的文字中提取火车票的核心信息。
    请严格返回合法的 JSON 对象，不要附加任何 Markdown 标记（例如 ```json），也不要加解释说明。
    注意：OCR 可能会把车厢号（例如 04车）识别成了“04年”，如果看到类似情况，请自动转成"04车"。
    
    提取的字段与类型：
    {
      "departureStation": "出发站名称字符串，例如 广州南站",
      "arrivalStation": "到达站名称字符串，例如 北京西站",
      "trainNumber": "车次号字符串，例如 G1234",
      "departureTime": "发车日期和时间的 ISO8601 字符串格式，如 2024-07-28T14:23:00Z",
      "carriageNumber": "车厢号字符串，包含车字，例如 04车",
      "seatNumber": "座位号字符串，例如 12A",
      "price": "票价浮点数",
      "idNumber": "身份证号后几位或全位，例如 323X",
      "passengerName": "乘客姓名字符串"
    }

    OCR 原文:
    \(text)
    """

    let apiKey = "sk-0eaa23e603d04282afd25cd37ba3af0a"
    var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
    request.httpMethod = "POST"
    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
        "model": "deepseek-chat",
        "messages": [
            ["role": "system", "content": "You are a helpful assistant."],
            ["role": "user", "content": prompt]
        ],
        "temperature": 0.1
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await URLSession.shared.data(for: request)
    guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = responseDict["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
        return String(data: data, encoding: .utf8) ?? "Failed to parse"
    }
    return content
}

// --- VisionTicketOCRService Logic ---
private struct OCRLine {
    let text: String
    let confidence: Float
    let box: CGRect
}

private let ciContext = CIContext(options: nil)

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
            continuation.resume(throwing: error)
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
        let key = String(line.text.filter { !$0.isWhitespace }.lowercased())
        if key.isEmpty { continue }
        if let old = best[key] {
            if line.confidence > old.confidence { best[key] = line }
        } else {
            best[key] = line
        }
    }
    return Array(best.values)
}

func process(imagePath: String) async {
    guard let nsImage = NSImage(contentsOfFile: imagePath),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Cannot load image \(imagePath)")
        return
    }

    print("\n\n==========================================")
    print(">>> 测试图片: \(imagePath)")
    print("==========================================")
    do {
        var merged = try await recognizeLines(in: cgImage)
        if let enhanced = enhancedImage(from: cgImage) {
            let enhancedLines = try await recognizeLines(in: enhanced)
            merged.append(contentsOf: enhancedLines)
        }

        let lines = deduplicate(lines: merged)
        
        // --- 核心逻辑：排序 ---
        let sortedLines = lines.sorted { line1, line2 in
            let yDiff = abs(line1.box.midY - line2.box.midY)
            let avgHeight = (line1.box.height + line2.box.height) / 2.0
            if yDiff < avgHeight * 0.6 {
                return line1.box.minX < line2.box.minX
            }
            return line1.box.midY > line2.box.midY
        }
        
        let rawTexts = sortedLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rawText = rawTexts.joined(separator: " ")
        
        // --- 提取核心本文送往LLM ---
        var cutoutText = rawText
        if let match = rawText.range(of: "(座|使用)", options: .regularExpression) {
            cutoutText = String(rawText[..<match.upperBound])
        }
        
        print("【发送给 LLM 的 OCR 文本】:\n\(cutoutText)\n")
        
        let jsonResponse = try await parseTicketInfo(from: cutoutText)
        print("【LLM 返回 JSON 结果】:")
        print(jsonResponse)
        
    } catch {
        print("Error: \(error)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("Provide image paths")
    exit(1)
}

Task {
    for path in args {
        await process(imagePath: path)
    }
    exit(0)
}

RunLoop.main.run()
