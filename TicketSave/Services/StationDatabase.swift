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

    private init() {
        records = Self.loadRecords()
    }

    func lookup(_ station: String) -> StationRecord? {
        if let exact = records[station] { return exact }
        let trimmed = station.replacingOccurrences(of: " ", with: "")
        return records.first(where: { $0.key.replacingOccurrences(of: " ", with: "") == trimmed })?.value
    }

    func city(for station: String) -> String? {
        lookup(station)?.city
    }

    func coordinate(for station: String) -> CLLocationCoordinate2D? {
        guard let coord = lookup(station)?.coordinate else { return nil }
        if coord.latitude == 0 && coord.longitude == 0 {
            return nil
        }
        return coord
    }

    private static func loadRecords() -> [String: StationRecord] {
        guard let raw = loadStationDataString() else {
            return [:]
        }

        let body = raw
            .replacingOccurrences(of: "var station_names =", with: "")
            .replacingOccurrences(of: "var station_names='", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "';\""))

        let chunks = body.split(separator: "@")
        var result: [String: StationRecord] = [:]
        result.reserveCapacity(chunks.count)

        for chunk in chunks {
            let fields = chunk.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 8 else { continue }

            let stationName = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if stationName.isEmpty { continue }

            let city = String(fields[7]).trimmingCharacters(in: .whitespacesAndNewlines)
            let province = city.isEmpty ? "未知" : city

            result[stationName] = StationRecord(
                name: stationName,
                city: city.isEmpty ? stationName : city,
                province: province,
                // station_name.js 不含经纬度，先用 (0,0) 占位，地图层会在查不到有效坐标时自动隐藏。
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)
            )
        }

        return result
    }

    private static func loadStationDataString() -> String? {
        if let path = Bundle.main.path(forResource: "station_name", ofType: "js") {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }

        if let url = Bundle.main.url(forResource: "station_name", withExtension: "js", subdirectory: "data") {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        return nil
    }
}
