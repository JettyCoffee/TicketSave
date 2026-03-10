import Foundation
import SwiftData

// MARK: - 对外结果类型

struct TrainStopResult: Sendable {
    let departureTime: Date?
    let arrivalTime: Date?
    let durationMinutes: Int?
    /// 完整经停列表（可在详情页展示）
    let stops: [StopInfo]
}

// MARK: - 错误类型

enum TrainAPIError: Error, LocalizedError {
    case trainNotFound(String)
    case networkError(Error)
    case parseError(String)
    case noMatchingStops

    var errorDescription: String? {
        switch self {
        case .trainNotFound(let t): return "未找到车次 \(t)"
        case .networkError(let e): return "网络请求失败：\(e.localizedDescription)"
        case .parseError(let msg): return "数据解析失败：\(msg)"
        case .noMatchingStops: return "时刻表中未找到指定站点"
        }
    }
}

// MARK: - 服务

/// 按需查询 12306 列车时刻表，结果持久化至 SwiftData（TrainScheduleCache）。
/// 同一车次同一日期只查询一次，之后直接读本地缓存。
///
/// 调用流程（参考 RailRhythm12306/main.py）：
///   Step 1: GET search.12306.cn/search/v1/train/search?keyword=G2176&date=20250913
///           → 获取内部 train_no（例如 "240000G21760G"）
///   Step 2: GET kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=...&leftTicketDTO.train_date=2025-09-13&rand_code=
///           → 获取完整经停站及各站时刻
actor TrainAPIService {
    static let shared = TrainAPIService()

    // 两个 API 端点（来源：github.com/wj0575/RailRhythm12306 main.py）
    private let searchURL   = "https://search.12306.cn/search/v1/train/search"
    private let scheduleURL = "https://kyfw.12306.cn/otn/queryTrainInfo/query"

    private let session: URLSession
    /// 内存缓存：trainCode_date → TrainScheduleCache（避免短时内重复 DB 查询）
    private var memCache: [String: TrainScheduleCache] = [:]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
    }

    // MARK: - 主要公共接口

    /// 查询车次在某日从 fromStation → toStation 的发车/到站时间。
    /// 若 SwiftData 中已有缓存，直接读取；否则请求 12306。
    func fetchStopTimes(
        trainNumber: String,
        date: Date,
        fromStation: String,
        toStation: String,
        modelContext: ModelContext
    ) async throws -> TrainStopResult {

        let dateStr = dateFmt.string(from: date)
        let schedule = try await fetchSchedule(trainNumber: trainNumber,
                                               date: date,
                                               dateStr: dateStr,
                                               modelContext: modelContext)

        let stops = schedule.stops
        let dep = stops.first { $0.stationName.contains(fromStation) || fromStation.contains($0.stationName) }
        let arr = stops.first { $0.stationName.contains(toStation)   || toStation.contains($0.stationName) }

        // 构造 Date
        let depDate = parseTime(dep?.startTime, date: date, dayDiff: 0)
        let arrDate = parseTime(arr?.arriveTime, date: date, dayDiff: arr?.arriveDayDiff ?? 0)

        let duration: Int? = {
            guard let d = depDate, let a = arrDate else { return nil }
            return Int(a.timeIntervalSince(d) / 60)
        }()

        return TrainStopResult(departureTime: depDate, arrivalTime: arrDate,
                               durationMinutes: duration, stops: stops)
    }

    // MARK: - 时刻表获取（带缓存）

    func fetchSchedule(
        trainNumber: String,
        date: Date,
        dateStr: String? = nil,
        modelContext: ModelContext
    ) async throws -> TrainScheduleCache {
        let dateString = dateStr ?? dateFmt.string(from: date)
        let cacheKey = "\(trainNumber)_\(dateString)"

        // 1. 内存缓存
        if let cached = memCache[cacheKey] { return cached }

        // 2. SwiftData 持久缓存
        let descriptor = FetchDescriptor<TrainScheduleCache>(
            predicate: #Predicate { $0.trainCode == trainNumber && $0.trainDate == dateString }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            memCache[cacheKey] = cached
            return cached
        }

        // 3. 网络查询
        let result = try await fetchFromNetwork(trainNumber: trainNumber, dateString: dateString)
        memCache[cacheKey] = result

        // 写入 SwiftData（在 MainActor 上执行）
        await persistToSwiftData(result, modelContext: modelContext)
        return result
    }

    // MARK: - 网络查询实现

    private func fetchFromNetwork(trainNumber: String, dateString: String) async throws -> TrainScheduleCache {
        // Step 1: 获取 train_no（12306 内部编号）
        let trainNo = try await getTrainNo(trainNumber: trainNumber,
                                           date: dateString.replacingOccurrences(of: "-", with: ""))

        // Step 2: 获取完整时刻表
        return try await getTrainInfo(trainNo: trainNo,
                                      trainCode: trainNumber,
                                      trainDate: dateString)
    }

    /// Step 1: search.12306.cn/search/v1/train/search
    private func getTrainNo(trainNumber: String, date: String) async throws -> String {
        var comps = URLComponents(string: searchURL)!
        comps.queryItems = [
            .init(name: "keyword", value: trainNumber),
            .init(name: "date", value: date)
        ]
        var req = URLRequest(url: comps.url!)
        setCommonHeaders(for: &req, host: "search.12306.cn")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TrainAPIError.parseError("search接口状态码异常")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first(where: { ($0["station_train_code"] as? String) == trainNumber }),
              let trainNo = first["train_no"] as? String else {
            throw TrainAPIError.trainNotFound(trainNumber)
        }
        return trainNo
    }

    /// Step 2: kyfw.12306.cn/otn/queryTrainInfo/query
    private func getTrainInfo(trainNo: String, trainCode: String, trainDate: String) async throws -> TrainScheduleCache {
        var comps = URLComponents(string: scheduleURL)!
        comps.queryItems = [
            .init(name: "leftTicketDTO.train_no", value: trainNo),
            .init(name: "leftTicketDTO.train_date", value: trainDate),
            .init(name: "rand_code", value: "")
        ]
        var req = URLRequest(url: comps.url!)
        setCommonHeaders(for: &req, host: "kyfw.12306.cn")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TrainAPIError.parseError("queryTrainInfo状态码异常")
        }
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = json["data"] as? [String: Any],
              let rawList  = dataNode["data"] as? [[String: Any]] else {
            throw TrainAPIError.parseError("queryTrainInfo响应格式异常")
        }

        var stops: [StopInfo] = []
        for item in rawList {
            let name       = (item["station_name"]    as? String ?? "").trimmingCharacters(in: .whitespaces)
            let no         = item["station_no"]        as? String ?? ""
            let arr        = item["arrive_time"]       as? String
            let dep        = item["start_time"]        as? String
            let dayDiff    = Int(item["arrive_day_diff"] as? String ?? "0") ?? 0
            let isStart    = item["is_start"] != nil
            let stopMins: Int
            if isStart {
                stopMins = 0
            } else if let a = arr, let d = dep,
                      a != "----", d != "----",
                      a.count >= 5, d.count >= 5 {
                let aMin = Int(a.prefix(2))! * 60 + Int(a.suffix(2))!
                let dMin = Int(d.prefix(2))! * 60 + Int(d.suffix(2))!
                stopMins = dMin >= aMin ? dMin - aMin : 0
            } else {
                stopMins = 0
            }
            stops.append(StopInfo(
                stationNo:    no,
                stationName:  name,
                arriveTime:   (arr == "----" || arr?.isEmpty == true) ? nil : arr,
                startTime:    (dep == "----" || dep?.isEmpty == true) ? nil : dep,
                stopMinutes:  stopMins,
                arriveDayDiff: dayDiff
            ))
        }
        guard !stops.isEmpty else { throw TrainAPIError.parseError("经停站列表为空") }

        let startStation = stops.first?.stationName ?? ""
        let endStation   = stops.last?.stationName ?? ""
        let stopsJSON    = TrainScheduleCache.encodeStops(stops)
        return TrainScheduleCache(trainCode: trainCode, trainNo: trainNo,
                                  trainDate: trainDate,
                                  startStation: startStation, endStation: endStation,
                                  stopsJSON: stopsJSON)
    }

    // MARK: - 持久化

    @MainActor
    private func persistToSwiftData(_ cache: TrainScheduleCache, modelContext: ModelContext) {
        modelContext.insert(cache)
        try? modelContext.save()
    }

    // MARK: - 工具

    private lazy var dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private func parseTime(_ timeStr: String?, date: Date, dayDiff: Int) -> Date? {
        guard let t = timeStr, t.count == 5 else { return nil }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour   = Int(t.prefix(2))
        comps.minute = Int(t.suffix(2))
        comps.second = 0
        guard var result = cal.date(from: comps) else { return nil }
        if dayDiff > 0 { result = cal.date(byAdding: .day, value: dayDiff, to: result) ?? result }
        return result
    }

    private func setCommonHeaders(for request: inout URLRequest, host: String) {
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("https://kyfw.12306.cn/", forHTTPHeaderField: "Referer")
        request.setValue("https://kyfw.12306.cn", forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("same-site", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue(host, forHTTPHeaderField: "Host")
    }
}

