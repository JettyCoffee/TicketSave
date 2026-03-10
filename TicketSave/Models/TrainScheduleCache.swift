import Foundation
import SwiftData

/// 单个经停站信息（JSON 序列化后存入 SwiftData）
struct StopInfo: Codable, Sendable {
    let stationNo: String       // "01", "02" ...
    let stationName: String     // "北京南"
    let arriveTime: String?     // "08:00" or nil（始发站）
    let startTime: String?      // "08:00" or nil（终到站）
    let stopMinutes: Int        // 停站分钟
    let arriveDayDiff: Int      // 到达日期偏移（0=当天, 1=次日...）
}

/// 列车时刻表本地缓存，用 SwiftData 持久化。
/// 按 trainCode + trainDate 唯一标识；查到后永久保留，OCR 识别到同车次同日期时直接读本地。
@Model
final class TrainScheduleCache {
    /// 车次号，如 "G2176"
    var trainCode: String
    /// 12306 内部 train_no，如 "240000G21760G"
    var trainNo: String
    /// 查询日期，"yyyy-MM-dd"
    var trainDate: String
    /// 始发站
    var startStation: String
    /// 终到站
    var endStation: String
    /// JSON 编码的 [StopInfo]
    var stopsJSON: String
    /// 缓存写入时间
    var cachedAt: Date

    init(trainCode: String, trainNo: String, trainDate: String,
         startStation: String, endStation: String,
         stopsJSON: String, cachedAt: Date = .now) {
        self.trainCode = trainCode
        self.trainNo = trainNo
        self.trainDate = trainDate
        self.startStation = startStation
        self.endStation = endStation
        self.stopsJSON = stopsJSON
        self.cachedAt = cachedAt
    }

    var stops: [StopInfo] {
        guard let data = stopsJSON.data(using: .utf8),
              let result = try? JSONDecoder().decode([StopInfo].self, from: data)
        else { return [] }
        return result
    }

    static func encodeStops(_ stops: [StopInfo]) -> String {
        guard let data = try? JSONEncoder().encode(stops),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }
}
