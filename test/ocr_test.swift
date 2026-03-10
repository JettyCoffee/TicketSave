#!/usr/bin/env swift
// 运行方式：swift test/ocr_test.swift
// 输出：Vision OCR 识别到的所有文本块，按从上到下排序，带 (x, y, w, h) 坐标

import Vision
import AppKit
import CoreGraphics

guard let image = NSImage(contentsOfFile: "test/test1.jpeg"),
      let cgRef = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("❌ 无法加载图片 test/test1.jpeg")
    exit(1)
}

let sema = DispatchSemaphore(value: 0)

let request = VNRecognizeTextRequest { req, error in
    defer { sema.signal() }
    if let error {
        print("❌ OCR 错误: \(error)")
        return
    }
    guard let obs = req.results as? [VNRecognizedTextObservation] else { return }

    // Vision 坐标系：(0,0) 在左下角，转换为从上到下
    let blocks = obs.compactMap { o -> (text: String, topY: Float, x: Float, w: Float, h: Float)? in
        guard let c = o.topCandidates(1).first else { return nil }
        let r = o.boundingBox
        return (c.string, Float(1 - r.maxY), Float(r.minX), Float(r.width), Float(r.height))
    }.sorted { $0.topY < $1.topY }

    print("── Vision OCR 输出（共 \(blocks.count) 块）──────────────────────────")
    print("#    topY     x        w        h        text")
    print(String(repeating: "-", count: 72))
    for (i, b) in blocks.enumerated() {
        let topY  = String(b.topY).prefix(6)
        let x     = String(b.x).prefix(6)
        let w     = String(b.w).prefix(6)
        let h     = String(b.h).prefix(6)
        print("\(i)\t\(topY)\t\(x)\t\(w)\t\(h)\t\(b.text)")
    }
}

request.recognitionLanguages = ["zh-Hans", "en"]
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.minimumTextHeight = 0.01

let handler = VNImageRequestHandler(cgImage: cgRef, options: [:])
try! handler.perform([request])
sema.wait()
