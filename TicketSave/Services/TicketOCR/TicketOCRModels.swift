import Foundation

struct OCRTicketExtraction: Sendable, Codable {
    var departureStation: String = ""
    var trainNumber: String = ""
    var arrivalStation: String = ""
    var departureTime: Date = .distantPast
    var carriageNumber: String = ""
    var seatNumber: String = ""
    var price: Double = 0
    var ticketType: String = ""
    var seatClass: String = ""
    var rawLines: [String] = []
}

struct TicketScheduleSnapshot: Sendable {
    var trainDate: String = ""
    var sourceURL: String = ""
    var stops: [StopInfo] = []
}

struct AddTicketOCRResult: Sendable {
    var departureStation: String = ""
    var trainNumber: String = ""
    var arrivalStation: String = ""
    var departureTime: Date = .distantPast
    var arrivalTime: Date = .distantPast
    var carriageNumber: String = ""
    var seatNumber: String = ""
    var price: Double = 0
    var ticketType: String = ""
    var seatClass: String = ""
    var schedule: TicketScheduleSnapshot = .init()
    var rawLines: [String] = []
}

enum AddTicketOCRStage: Sendable {
    case preparing
    case ocrCompleted
    case scheduleCompleted
    case finished
}

struct AddTicketOCRProgress: Sendable {
    var stage: AddTicketOCRStage
    var message: String
    var snapshot: AddTicketOCRResult
}
