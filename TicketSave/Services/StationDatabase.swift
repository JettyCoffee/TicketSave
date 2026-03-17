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
        let seed: [StationRecord] = [
            .init(name: "杭州东站", city: "杭州", province: "浙江", coordinate: .init(latitude: 30.2949, longitude: 120.2120)),
            .init(name: "上海南站", city: "上海", province: "上海", coordinate: .init(latitude: 31.1547, longitude: 121.4295)),
            .init(name: "上海虹桥站", city: "上海", province: "上海", coordinate: .init(latitude: 31.1947, longitude: 121.3270)),
            .init(name: "柳州站", city: "柳州", province: "广西", coordinate: .init(latitude: 24.3146, longitude: 109.3893)),
            .init(name: "长沙南站", city: "长沙", province: "湖南", coordinate: .init(latitude: 28.1462, longitude: 113.0661)),
            .init(name: "南宁东站", city: "南宁", province: "广西", coordinate: .init(latitude: 22.8425, longitude: 108.3974))
        ]
        self.records = Dictionary(uniqueKeysWithValues: seed.map { ($0.name, $0) })
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
        lookup(station)?.coordinate
    }
}
