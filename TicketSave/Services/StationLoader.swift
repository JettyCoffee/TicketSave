import Foundation
import CoreLocation

/// 从 App Bundle 内的 station_name.js 加载完整站点列表，合并进 StationDatabase。
/// 文件格式（来自 12306，由用户放入 data/ 目录）：
///   @pinyin|中文名|TELECODE|pinyin_full|abbr|序号|id|城市|||
actor StationLoader {
    static let shared = StationLoader()

    private var isLoaded = false
    private let loadedKey = "StationLoader.bundledLoaded"

    // MARK: - 公共接口

    /// App 启动时调用一次；若已加载则秒返回
    func loadBundledIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        loadFromBundle()
    }

    /// 强制重新解析 bundle 文件（升级后覆盖旧缓存）
    func reloadBundle() {
        loadFromBundle()
    }

    // MARK: - 解析

    private func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "station_name", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let stations = parseJS(text)
        guard !stations.isEmpty else { return }
        StationDatabase.shared.merge(stations)
    }

    /// 解析 `@pinyin|中文名|TELECODE|pinyin_full|abbr|序号|id|城市|||` 格式
    private func parseJS(_ text: String) -> [StationInfo] {
        // 提取 @ 到下一个 @ 之间的内容
        var stations: [StationInfo] = []

        var startIdx = text.startIndex
        while true {
            guard let atIdx = text.range(of: "@", range: startIdx..<text.endIndex)?.lowerBound else { break }
            let entryStart = text.index(after: atIdx)
            let nextAt = text.range(of: "@", range: entryStart..<text.endIndex)?.lowerBound ?? text.endIndex
            let entry = String(text[entryStart..<nextAt])
            startIdx = nextAt

            let parts = entry.components(separatedBy: "|")
            // 至少需要: [0]abbr [1]中文名 [2]TELECODE ... [7]城市
            guard parts.count >= 3 else { continue }
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let code = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, code.count >= 3 else { continue }

            let city: String
            if parts.count >= 8 {
                city = parts[7].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                city = deriveCityName(from: name)
            }

            // 优先保留种子数据里的坐标；新站点用 (0,0) 占位（地图功能降级）
            let existing = StationDatabase.shared.lookupByCode(code)
            let coord = existing?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let province = existing?.province ?? ""

            stations.append(StationInfo(
                name: name,
                code: code,
                coordinate: coord,
                city: city.isEmpty ? deriveCityName(from: name) : city,
                province: province
            ))
        }
        return stations
    }

    /// 取站名前2字作为城市名 fallback（e.g. "杭州东" → "杭州"）
    private func deriveCityName(from name: String) -> String {
        String(name.prefix(2))
    }
}
