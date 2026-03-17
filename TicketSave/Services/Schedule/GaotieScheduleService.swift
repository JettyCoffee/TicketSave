import Foundation

enum GaotieScheduleError: LocalizedError {
    case badURL
    case networkFailed
    case decodeFailed
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "无效的车次查询地址"
        case .networkFailed: return "时刻表请求失败"
        case .decodeFailed: return "时刻表页面解码失败"
        case .parseFailed: return "时刻表解析失败"
        }
    }
}

struct GaotieSchedule: Sendable {
    var trainCode: String
    var sourceURL: String
    var startStation: String
    var endStation: String
    var stops: [StopInfo]
}

final class GaotieScheduleService {
    func fetchSchedule(trainCode: String) async throws -> GaotieSchedule {
        let normalizedTrain = trainCode.uppercased()
        guard let url = URL(string: "https://shike.gaotie.cn/checi.asp?checi=\(normalizedTrain)") else {
            throw GaotieScheduleError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let result = try await URLSession.shared.data(for: request)
            data = result.0
        } catch {
            throw GaotieScheduleError.networkFailed
        }

        guard let html = decodeHTML(data) else {
            throw GaotieScheduleError.decodeFailed
        }

        let tokens = tokenize(html: html)
        let rows = extractRows(from: tokens)
        guard !rows.isEmpty else { throw GaotieScheduleError.parseFailed }

        let startStation = rows.first?.stationName ?? ""
        let endStation = rows.last?.stationName ?? ""
        return GaotieSchedule(
            trainCode: normalizedTrain,
            sourceURL: url.absoluteString,
            startStation: startStation,
            endStation: endStation,
            stops: rows
        )
    }

    private func decodeHTML(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }

        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let gb = String(data: data, encoding: String.Encoding(rawValue: gb18030)), !gb.isEmpty {
            return gb
        }

        let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gbk))
    }

    private func tokenize(html: String) -> [String] {
        let withoutScript = html.replacingOccurrences(
            of: "(?is)<script[^>]*>.*?</script>",
            with: " ",
            options: .regularExpression
        )
        let withoutStyle = withoutScript.replacingOccurrences(
            of: "(?is)<style[^>]*>.*?</style>",
            with: " ",
            options: .regularExpression
        )
        let withBreaks = withoutStyle.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)

        return withBreaks
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractRows(from tokens: [String]) -> [StopInfo] {
        var candidates: [StopInfo] = []

        for i in 0..<(tokens.count - 5) {
            guard let no = Int(tokens[i]), no > 0, no < 100 else { continue }
            let station = tokens[i + 1]
            if !station.contains("站") { continue }

            let arrive = tokens[i + 2]
            let stop = tokens[i + 3]
            let start = tokens[i + 4]
            let day = tokens[i + 5]

            if !isArriveToken(arrive) || !isStartToken(start) { continue }
            guard let dayValue = Int(day), dayValue > 0, dayValue < 10 else { continue }

            let stopMinutes = parseStopMinutes(stop)
            let info = StopInfo(
                stationNo: String(format: "%02d", no),
                stationName: normalizeStation(station),
                arriveTime: parseTimeToken(arrive, terminalKeyword: "始发站"),
                startTime: parseTimeToken(start, terminalKeyword: "终点站"),
                stopMinutes: stopMinutes,
                arriveDayDiff: max(dayValue - 1, 0)
            )
            candidates.append(info)
        }

        if candidates.isEmpty { return [] }
        return pickBestSequence(candidates)
    }

    private func pickBestSequence(_ rows: [StopInfo]) -> [StopInfo] {
        var best: [StopInfo] = []
        var current: [StopInfo] = []

        for row in rows {
            let no = Int(row.stationNo) ?? 0

            if no == 1 {
                if current.count > best.count {
                    best = current
                }
                current = [row]
                continue
            }

            guard let lastNo = Int(current.last?.stationNo ?? "") else { continue }
            if no == lastNo + 1 {
                current.append(row)
            }
        }

        if current.count > best.count {
            best = current
        }

        return best.count >= 2 ? best : rows
    }

    private func isTime(_ token: String) -> Bool {
        token.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private func isArriveToken(_ token: String) -> Bool {
        token == "始发站" || token == "-" || isTime(token)
    }

    private func isStartToken(_ token: String) -> Bool {
        token == "终点站" || token == "-" || isTime(token)
    }

    private func parseTimeToken(_ token: String, terminalKeyword: String) -> String? {
        if token == terminalKeyword || token == "-" { return nil }
        return isTime(token) ? token : nil
    }

    private func parseStopMinutes(_ token: String) -> Int {
        let digits = token.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return Int(digits) ?? 0
    }

    private func normalizeStation(_ station: String) -> String {
        station.replacingOccurrences(of: " ", with: "")
    }
}
