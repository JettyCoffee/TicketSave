import Foundation

enum TicketOCRMapper {
    static func fallbackArrivalTime(from departureTime: Date) -> Date {
        departureTime.addingTimeInterval(2 * 3600)
    }

    static func departureDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
