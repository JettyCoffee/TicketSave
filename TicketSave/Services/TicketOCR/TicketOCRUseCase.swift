import Foundation
import UIKit
import SwiftData

final class TicketOCRUseCase {
    private let ocrService = VisionTicketOCRService()
    private let scheduleRepository = TrainScheduleRepository()

    func recognizeTicket(from image: UIImage, modelContext: ModelContext) async throws -> AddTicketOCRResult {
        let extraction = try await ocrService.recognize(from: image)

        var result = AddTicketOCRResult()
        result.departureStation = extraction.departureStation
        result.trainNumber = extraction.trainNumber
        result.arrivalStation = extraction.arrivalStation
        result.departureTime = extraction.departureTime
        result.carriageNumber = extraction.carriageNumber
        result.seatNumber = extraction.seatNumber
        result.price = extraction.price
        result.ticketType = extraction.ticketType
        result.seatClass = extraction.seatClass
        result.rawLines = extraction.rawLines

        if extraction.departureTime != .distantPast {
            result.arrivalTime = TicketOCRMapper.fallbackArrivalTime(from: extraction.departureTime)
        }

        guard !extraction.trainNumber.isEmpty,
              extraction.departureTime != .distantPast else {
            return result
        }

        do {
            let cache = try await scheduleRepository.getOrFetch(
                trainCode: extraction.trainNumber,
                trainDate: extraction.departureTime,
                modelContext: modelContext
            )

            result.schedule = TicketScheduleSnapshot(
                trainDate: cache.trainDate,
                sourceURL: "https://shike.gaotie.cn/checi.asp?checi=\(extraction.trainNumber)",
                stops: cache.stops
            )

            if let inferred = scheduleRepository.inferArrivalTime(
                schedule: cache,
                departureStation: extraction.departureStation,
                arrivalStation: extraction.arrivalStation,
                departureDateTime: extraction.departureTime
            ) {
                result.arrivalTime = inferred
            }
        } catch {
            // 时刻表抓取失败不影响主流程，保留 OCR 字段和默认到达时间。
        }

        return result
    }
}
