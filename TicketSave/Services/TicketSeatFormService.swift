import Foundation

struct TicketSeatFormState {
    var carriageNumber: String
    var seatRow: String
    var seatLetter: String
    var seatNumber: String
}

enum TicketSeatFormService {
    static let seatClassOptions: [String] = ["商务座", "一等座", "二等座", "特等座", "硬卧", "软卧", "硬座", "软座", "无座"]

    static func normalizeAfterSeatClassChange(
        seatClass: String,
        carriageNumber: String,
        seatRow: String,
        seatLetter: String
    ) -> TicketSeatFormState {
        guard seatClass != "无座" else {
            return TicketSeatFormState(carriageNumber: "", seatRow: "01", seatLetter: "A", seatNumber: "")
        }

        let normalizedCarriage = carriageNumber.isEmpty ? "01" : carriageNumber
        let rows = rowOptions(for: seatClass)
        let letters = letterOptions(for: seatClass)

        let normalizedRow = rows.contains(seatRow) ? seatRow : (rows.first ?? "01")
        let normalizedLetter = letters.contains(seatLetter) ? seatLetter : (letters.first ?? "A")

        return TicketSeatFormState(
            carriageNumber: normalizedCarriage,
            seatRow: normalizedRow,
            seatLetter: normalizedLetter,
            seatNumber: normalizedRow + normalizedLetter
        )
    }

    static func syncSeatNumber(seatClass: String, seatRow: String, seatLetter: String) -> String {
        guard seatClass != "无座" else { return "" }
        return seatRow + seatLetter
    }

    static func parseSeatNumber(_ value: String) -> (seatRow: String, seatLetter: String)? {
        let marker = Set(["A", "B", "C", "D", "F", "上", "中", "下"])
        guard let last = value.last else { return nil }

        let letter = String(last)
        guard marker.contains(letter) else { return nil }

        let rowPart = String(value.dropLast())
        let row = String(format: "%02d", Int(rowPart) ?? 1)
        return (seatRow: row, seatLetter: letter)
    }

    static func rowOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return (1...9).map { String(format: "%02d", $0) }
        case "一等座": return (1...18).map { String(format: "%02d", $0) }
        case "硬卧", "软卧", "动卧": return (1...12).map { String(format: "%02d", $0) }
        default: return (1...20).map { String(format: "%02d", $0) }
        }
    }

    static func letterOptions(for seatClass: String) -> [String] {
        switch seatClass {
        case "商务座", "特等座": return ["A", "C", "F"]
        case "一等座": return ["A", "C", "D", "F"]
        case "二等卧", "硬卧": return ["上", "中", "下"]
        case "软卧", "动卧": return ["上", "下"]
        default: return ["A", "B", "C", "D", "F"]
        }
    }

    static func isSleeper(_ seatClass: String) -> Bool {
        ["硬卧", "软卧", "动卧"].contains(seatClass)
    }
}
