import SwiftUI
import SwiftData

@Model
final class Ticket {
    var id: UUID = UUID()
    var orderNumber: String = ""
    var trainNumber: String = ""
    var departureStation: String = ""
    var arrivalStation: String = ""
    var departureTime: Date = Date()
    var arrivalTime: Date = Date()
    var seatNumber: String = ""
    var carriageNumber: String = ""
    var seatClass: String = "二等座"
    var price: Double = 0.0
    var checkGate: String = ""
    var passengerName: String = ""
    @Attribute(.externalStorage) var ticketImageData: Data?
    var createdAt: Date = Date()
    var notes: String = ""

    var trainType: String {
        let prefix = trainNumber.prefix(1).uppercased()
        switch prefix {
        case "G": return "高铁"
        case "D": return "动车"
        case "C": return "城际"
        case "Z": return "直达"
        case "T": return "特快"
        case "K": return "快速"
        default: return "普通"
        }
    }

    var trainTypeColor: Color {
        let prefix = trainNumber.prefix(1).uppercased()
        switch prefix {
        case "G": return Color(red: 0.0, green: 0.45, blue: 0.85)
        case "D": return Color(red: 0.0, green: 0.65, blue: 0.55)
        case "C": return Color(red: 0.2, green: 0.6, blue: 0.8)
        case "Z": return Color(red: 0.8, green: 0.2, blue: 0.2)
        case "T": return Color(red: 0.85, green: 0.5, blue: 0.1)
        case "K": return Color(red: 0.6, green: 0.4, blue: 0.2)
        default: return .gray
        }
    }

    var seatClassColor: Color {
        switch seatClass {
        case "商务座": return Color(red: 0.8, green: 0.6, blue: 0.2)
        case "一等座": return Color(red: 0.55, green: 0.3, blue: 0.7)
        case "二等座": return Color(red: 0.0, green: 0.45, blue: 0.85)
        case "硬卧", "软卧": return Color(red: 0.3, green: 0.6, blue: 0.5)
        case "硬座": return Color(red: 0.5, green: 0.5, blue: 0.5)
        case "无座": return .secondary
        default: return .blue
        }
    }

    var formattedSeat: String {
        if carriageNumber.isEmpty && seatNumber.isEmpty { return "" }
        if carriageNumber.isEmpty { return seatNumber }
        if seatNumber.isEmpty { return "\(carriageNumber)车" }
        return "\(carriageNumber)车\(seatNumber)"
    }

    var duration: TimeInterval {
        arrivalTime.timeIntervalSince(departureTime)
    }

    var durationText: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))min"
        }
        return "\(minutes)min"
    }

    init(
        orderNumber: String = "",
        trainNumber: String = "",
        departureStation: String = "",
        arrivalStation: String = "",
        departureTime: Date = Date(),
        arrivalTime: Date = Date(),
        seatNumber: String = "",
        carriageNumber: String = "",
        seatClass: String = "二等座",
        price: Double = 0.0,
        checkGate: String = "",
        passengerName: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.orderNumber = orderNumber
        self.trainNumber = trainNumber
        self.departureStation = departureStation
        self.arrivalStation = arrivalStation
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.seatNumber = seatNumber
        self.carriageNumber = carriageNumber
        self.seatClass = seatClass
        self.price = price
        self.checkGate = checkGate
        self.passengerName = passengerName
        self.createdAt = Date()
        self.notes = notes
    }
}

struct TicketInfo: Sendable {
    var orderNumber: String = ""
    var trainNumber: String = ""
    var departureStation: String = ""
    var arrivalStation: String = ""
    var departureTime: Date = Date()
    var arrivalTime: Date = Date()
    var seatNumber: String = ""
    var carriageNumber: String = ""
    var seatClass: String = "二等座"
    var price: Double = 0.0
    var checkGate: String = ""
    var passengerName: String = ""
}
