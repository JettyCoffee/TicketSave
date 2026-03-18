import Foundation
import CoreLocation

struct StationRecord {
    let name: String
    let city: String
    let province: String
    let coordinate: CLLocationCoordinate2D
}

final class StationDatabase {
    static let shared = StationDatabase()

    private let records: [String: StationRecord]

    func lookup(_ station: String) -> StationRecord? {
        if let exact = records[station] { return exact }
        let trimmed = station.replacingOccurrences(of: " ", with: "")
        return records.first(where: { $0.key.replacingOccurrences(of: " ", with: "") == trimmed })?.value
    }

    func city(for station: String) -> String? {
        lookup(station)?.city
    }

    func coordinate(for station: String) -> CLLocationCoordinate2D? {
        lookup(station)?.coordinate
    }
}
