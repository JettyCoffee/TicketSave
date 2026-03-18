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
    private let llmRouter: LLMRouterProtocol = LLMRouterService()

    func recognize(from image: UIImage) async throws -> OCRTicketExtraction {
        guard let baseCG = image.cgImage else { throw VisionTicketOCRError.invalidImage }

        var merged = try await recognizeLines(in: baseCG)
        if let enhanced = enhancedImage(from: baseCG) {
            let enhancedLines = try await recognizeLines(in: enhanced)
            merged.append(contentsOf: enhancedLines)
        }

        let lines = deduplicate(lines: merged)
        let orderedLines = orderByReadingDirection(lines)
        let rawTexts = orderedLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rawText = rawTexts.joined(separator: " ")
        
        var cutoutText = rawText
        if let match = rawText.range(of: "(座|使用)", options: .regularExpression) {
            let endIndex = match.upperBound
            cutoutText = String(rawText[..<endIndex])
        }
        
        var extraction = try await llmRouter.parseTicketInfo(from: cutoutText)
        extraction.rawLines = rawTexts
        
        return extraction
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
            let key = String(line.text.filter { !$0.isWhitespace }.lowercased())
            if key.isEmpty { continue }
            if let old = best[key] {
                if line.confidence > old.confidence {
                    best[key] = line
                }
            } else {
                best[key] = line
            }
        }
        return Array(best.values)
    }

    private func orderByReadingDirection(_ lines: [OCRLine]) -> [OCRLine] {
        guard !lines.isEmpty else { return [] }

        struct OCRRow {
            var referenceY: CGFloat
            var height: CGFloat
            var lines: [OCRLine]
        }

        // Vision 的 normalized 坐标原点在左下，Y 越大越靠上。
        let ySorted = lines.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) < 0.0001 {
                return lhs.box.minX < rhs.box.minX
            }
            return lhs.box.midY > rhs.box.midY
        }

        var rows: [OCRRow] = []
        for line in ySorted {
            if let last = rows.last {
                let yDelta = abs(last.referenceY - line.box.midY)
                let tolerance = max(0.015, max(last.height, line.box.height) * 0.7)
                if yDelta <= tolerance {
                    var merged = last
                    merged.lines.append(line)
                    let count = CGFloat(merged.lines.count)
                    merged.referenceY = ((last.referenceY * (count - 1.0)) + line.box.midY) / count
                    merged.height = max(last.height, line.box.height)
                    rows[rows.count - 1] = merged
                    continue
                }
            }

            rows.append(OCRRow(referenceY: line.box.midY, height: line.box.height, lines: [line]))
        }

        return rows
            .sorted { $0.referenceY > $1.referenceY }
            .flatMap { row in
                row.lines.sorted { lhs, rhs in
                    if abs(lhs.box.minX - rhs.box.minX) < 0.0001 {
                        return lhs.box.midY > rhs.box.midY
                    }
                    return lhs.box.minX < rhs.box.minX
                }
            }
    }
}