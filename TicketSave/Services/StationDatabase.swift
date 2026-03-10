import Foundation
import CoreLocation

struct StationInfo: Sendable {
    let name: String
    let code: String
    let coordinate: CLLocationCoordinate2D
    let city: String
    let province: String
}

/// 线程安全的站点数据库。
/// 使用内置种子数据保证首次可用，并在 StationLoader 下载 12306 最新数据后动态合并更新。
final class StationDatabase: @unchecked Sendable {
    nonisolated(unsafe) static let shared = StationDatabase()

    private nonisolated(unsafe) var byName: [String: StationInfo] = [:]
    private nonisolated(unsafe) var byCode: [String: StationInfo] = [:]
    private let lock = NSLock()

    private init() {
        // 先加载本地持久缓存，再用内置种子补全
        let cached = Self.loadCache()
        var merged: [String: StationInfo] = [:]
        for s in Self.stationData { merged[s.name] = s }
        for s in cached { merged[s.name] = s }
        byName = merged
        for info in byName.values { byCode[info.code] = info }
    }

    // MARK: - 公共同步接口（与旧 struct 完全兼容）
    nonisolated func lookup(_ name: String) -> StationInfo? {
        lock.withLock {
            let cleaned = name
                .replacingOccurrences(of: "站", with: "")
                .replacingOccurrences(of: " ", with: "")
            return byName[cleaned] ?? byName[name]
        }
    }

    nonisolated func lookupByCode(_ code: String) -> StationInfo? {
        lock.withLock { byCode[code.uppercased()] }
    }

    nonisolated func coordinate(for stationName: String) -> CLLocationCoordinate2D? {
        lookup(stationName)?.coordinate
    }

    nonisolated func city(for stationName: String) -> String? {
        lookup(stationName)?.city
    }

    /// 前缀 / 包含模糊搜索（供 OCR 站名校验使用）
    nonisolated func fuzzyLookup(_ prefix: String, maxResults: Int = 5) -> [StationInfo] {
        let cleaned = prefix
            .replacingOccurrences(of: "站", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 2 else { return [] }
        return lock.withLock {
            Array(byName.values
                .filter { $0.name.hasPrefix(cleaned) || $0.name.contains(cleaned) }
                .prefix(maxResults))
        }
    }

    // MARK: - 动态合并（由 StationLoader 调用）
    nonisolated func merge(_ stations: [StationInfo]) {
        lock.withLock {
            for s in stations {
                byName[s.name] = s
                byCode[s.code] = s
            }
        }
        Self.saveCache(stations)
    }

    // MARK: - 本地持久缓存
    private nonisolated static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("stations_cache_v1.json")
    }

    private nonisolated static func loadCache() -> [StationInfo] {
        guard let data = try? Data(contentsOf: cacheURL),
              let items = try? JSONDecoder().decode([CodableStation].self, from: data)
        else { return [] }
        return items.map(\.toStationInfo)
    }

    private nonisolated static func saveCache(_ stations: [StationInfo]) {
        guard let data = try? JSONEncoder().encode(stations.map(CodableStation.init))
        else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static let stationData: [StationInfo] = [
        // 直辖市
        StationInfo(name: "北京", code: "BJP", coordinate: .init(latitude: 39.9042, longitude: 116.4074), city: "北京", province: "北京"),
        StationInfo(name: "北京南", code: "VNP", coordinate: .init(latitude: 39.8652, longitude: 116.3786), city: "北京", province: "北京"),
        StationInfo(name: "北京西", code: "BXP", coordinate: .init(latitude: 39.8960, longitude: 116.3225), city: "北京", province: "北京"),
        StationInfo(name: "北京北", code: "VAP", coordinate: .init(latitude: 39.9447, longitude: 116.3537), city: "北京", province: "北京"),
        StationInfo(name: "北京朝阳", code: "IFP", coordinate: .init(latitude: 39.9720, longitude: 116.5960), city: "北京", province: "北京"),
        StationInfo(name: "北京丰台", code: "QJP", coordinate: .init(latitude: 39.8530, longitude: 116.2870), city: "北京", province: "北京"),
        StationInfo(name: "上海", code: "SHH", coordinate: .init(latitude: 31.2497, longitude: 121.4558), city: "上海", province: "上海"),
        StationInfo(name: "上海虹桥", code: "AOH", coordinate: .init(latitude: 31.1940, longitude: 121.3321), city: "上海", province: "上海"),
        StationInfo(name: "上海南", code: "SNH", coordinate: .init(latitude: 31.1548, longitude: 121.4312), city: "上海", province: "上海"),
        StationInfo(name: "天津", code: "TJP", coordinate: .init(latitude: 39.1422, longitude: 117.2103), city: "天津", province: "天津"),
        StationInfo(name: "天津西", code: "TXP", coordinate: .init(latitude: 39.1563, longitude: 117.1531), city: "天津", province: "天津"),
        StationInfo(name: "天津南", code: "TIP", coordinate: .init(latitude: 39.0233, longitude: 117.0638), city: "天津", province: "天津"),
        StationInfo(name: "重庆", code: "CQW", coordinate: .init(latitude: 29.5857, longitude: 106.5516), city: "重庆", province: "重庆"),
        StationInfo(name: "重庆北", code: "CUW", coordinate: .init(latitude: 29.6068, longitude: 106.5518), city: "重庆", province: "重庆"),
        StationInfo(name: "重庆西", code: "CRW", coordinate: .init(latitude: 29.5240, longitude: 106.4340), city: "重庆", province: "重庆"),
        StationInfo(name: "重庆北站北广场", code: "CUW", coordinate: .init(latitude: 29.6068, longitude: 106.5518), city: "重庆", province: "重庆"),
        // 广东
        StationInfo(name: "广州", code: "GZQ", coordinate: .init(latitude: 23.1479, longitude: 113.2544), city: "广州", province: "广东"),
        StationInfo(name: "广州南", code: "IZQ", coordinate: .init(latitude: 22.9889, longitude: 113.2693), city: "广州", province: "广东"),
        StationInfo(name: "广州东", code: "GGQ", coordinate: .init(latitude: 23.1534, longitude: 113.3257), city: "广州", province: "广东"),
        StationInfo(name: "深圳", code: "SZQ", coordinate: .init(latitude: 22.5326, longitude: 114.1179), city: "深圳", province: "广东"),
        StationInfo(name: "深圳北", code: "IOQ", coordinate: .init(latitude: 22.6097, longitude: 114.0297), city: "深圳", province: "广东"),
        StationInfo(name: "深圳西", code: "SXQ", coordinate: .init(latitude: 22.5250, longitude: 113.9060), city: "深圳", province: "广东"),
        StationInfo(name: "东莞", code: "DAQ", coordinate: .init(latitude: 23.0206, longitude: 113.7180), city: "东莞", province: "广东"),
        StationInfo(name: "虎门", code: "IUQ", coordinate: .init(latitude: 22.8198, longitude: 113.5816), city: "东莞", province: "广东"),
        StationInfo(name: "珠海", code: "ZHQ", coordinate: .init(latitude: 22.2710, longitude: 113.5767), city: "珠海", province: "广东"),
        StationInfo(name: "佛山西", code: "FOQ", coordinate: .init(latitude: 23.0219, longitude: 112.9355), city: "佛山", province: "广东"),
        StationInfo(name: "惠州", code: "HCQ", coordinate: .init(latitude: 23.0892, longitude: 114.3997), city: "惠州", province: "广东"),
        StationInfo(name: "惠州南", code: "KBQ", coordinate: .init(latitude: 22.8920, longitude: 114.5150), city: "惠州", province: "广东"),
        StationInfo(name: "潮汕", code: "CBQ", coordinate: .init(latitude: 23.3500, longitude: 116.7300), city: "潮州", province: "广东"),
        // 江苏
        StationInfo(name: "南京", code: "NJH", coordinate: .init(latitude: 32.0895, longitude: 118.7969), city: "南京", province: "江苏"),
        StationInfo(name: "南京南", code: "NKH", coordinate: .init(latitude: 31.9732, longitude: 118.8016), city: "南京", province: "江苏"),
        StationInfo(name: "苏州", code: "SZH", coordinate: .init(latitude: 31.3379, longitude: 120.6174), city: "苏州", province: "江苏"),
        StationInfo(name: "苏州北", code: "OHH", coordinate: .init(latitude: 31.4200, longitude: 120.6500), city: "苏州", province: "江苏"),
        StationInfo(name: "无锡", code: "WXH", coordinate: .init(latitude: 31.5836, longitude: 120.2993), city: "无锡", province: "江苏"),
        StationInfo(name: "无锡东", code: "WGH", coordinate: .init(latitude: 31.5600, longitude: 120.4000), city: "无锡", province: "江苏"),
        StationInfo(name: "常州", code: "CZH", coordinate: .init(latitude: 31.7832, longitude: 119.9736), city: "常州", province: "江苏"),
        StationInfo(name: "徐州", code: "XCH", coordinate: .init(latitude: 34.2812, longitude: 117.1851), city: "徐州", province: "江苏"),
        StationInfo(name: "徐州东", code: "UUH", coordinate: .init(latitude: 34.2600, longitude: 117.3200), city: "徐州", province: "江苏"),
        StationInfo(name: "镇江", code: "ZJH", coordinate: .init(latitude: 32.2044, longitude: 119.4550), city: "镇江", province: "江苏"),
        StationInfo(name: "昆山南", code: "KNH", coordinate: .init(latitude: 31.3200, longitude: 120.9800), city: "昆山", province: "江苏"),
        // 浙江
        StationInfo(name: "杭州", code: "HZH", coordinate: .init(latitude: 30.2458, longitude: 120.1833), city: "杭州", province: "浙江"),
        StationInfo(name: "杭州东", code: "HGH", coordinate: .init(latitude: 30.2912, longitude: 120.2139), city: "杭州", province: "浙江"),
        StationInfo(name: "杭州西", code: "HCU", coordinate: .init(latitude: 30.3080, longitude: 120.0350), city: "杭州", province: "浙江"),
        StationInfo(name: "杭州南", code: "XHH", coordinate: .init(latitude: 30.1970, longitude: 120.2420), city: "杭州", province: "浙江"),
        StationInfo(name: "宁波", code: "NGH", coordinate: .init(latitude: 29.8683, longitude: 121.5440), city: "宁波", province: "浙江"),
        StationInfo(name: "温州南", code: "VRH", coordinate: .init(latitude: 27.9060, longitude: 120.6380), city: "温州", province: "浙江"),
        StationInfo(name: "嘉兴南", code: "EPH", coordinate: .init(latitude: 30.7300, longitude: 120.7700), city: "嘉兴", province: "浙江"),
        StationInfo(name: "金华", code: "JBH", coordinate: .init(latitude: 29.0806, longitude: 119.6395), city: "金华", province: "浙江"),
        StationInfo(name: "义乌", code: "YWH", coordinate: .init(latitude: 29.3062, longitude: 120.0750), city: "义乌", province: "浙江"),
        StationInfo(name: "绍兴", code: "SOH", coordinate: .init(latitude: 30.0306, longitude: 120.5750), city: "绍兴", province: "浙江"),
        // 湖北
        StationInfo(name: "武汉", code: "WHN", coordinate: .init(latitude: 30.6014, longitude: 114.2510), city: "武汉", province: "湖北"),
        StationInfo(name: "汉口", code: "HKN", coordinate: .init(latitude: 30.6180, longitude: 114.2530), city: "武汉", province: "湖北"),
        StationInfo(name: "武昌", code: "WCN", coordinate: .init(latitude: 30.5294, longitude: 114.3152), city: "武汉", province: "湖北"),
        StationInfo(name: "宜昌东", code: "HAN", coordinate: .init(latitude: 30.7134, longitude: 111.2856), city: "宜昌", province: "湖北"),
        StationInfo(name: "襄阳东", code: "QFN", coordinate: .init(latitude: 32.0100, longitude: 112.1700), city: "襄阳", province: "湖北"),
        // 湖南
        StationInfo(name: "长沙", code: "CSQ", coordinate: .init(latitude: 28.1942, longitude: 112.9750), city: "长沙", province: "湖南"),
        StationInfo(name: "长沙南", code: "CWQ", coordinate: .init(latitude: 28.1545, longitude: 113.0701), city: "长沙", province: "湖南"),
        StationInfo(name: "衡阳东", code: "HVQ", coordinate: .init(latitude: 26.8950, longitude: 112.5900), city: "衡阳", province: "湖南"),
        StationInfo(name: "岳阳东", code: "YIQ", coordinate: .init(latitude: 29.3750, longitude: 113.1300), city: "岳阳", province: "湖南"),
        // 四川
        StationInfo(name: "成都", code: "CDW", coordinate: .init(latitude: 30.6151, longitude: 104.0186), city: "成都", province: "四川"),
        StationInfo(name: "成都东", code: "ICW", coordinate: .init(latitude: 30.6319, longitude: 104.1397), city: "成都", province: "四川"),
        StationInfo(name: "成都南", code: "CNW", coordinate: .init(latitude: 30.5861, longitude: 104.0712), city: "成都", province: "四川"),
        StationInfo(name: "成都西", code: "CMW", coordinate: .init(latitude: 30.6500, longitude: 103.9600), city: "成都", province: "四川"),
        StationInfo(name: "绵阳", code: "MYW", coordinate: .init(latitude: 31.4617, longitude: 104.7571), city: "绵阳", province: "四川"),
        // 河南
        StationInfo(name: "郑州", code: "ZZF", coordinate: .init(latitude: 34.7564, longitude: 113.6655), city: "郑州", province: "河南"),
        StationInfo(name: "郑州东", code: "ZAF", coordinate: .init(latitude: 34.7562, longitude: 113.7738), city: "郑州", province: "河南"),
        StationInfo(name: "洛阳龙门", code: "LLF", coordinate: .init(latitude: 34.6197, longitude: 112.4487), city: "洛阳", province: "河南"),
        StationInfo(name: "开封北", code: "KBF", coordinate: .init(latitude: 34.8300, longitude: 114.3500), city: "开封", province: "河南"),
        // 河北
        StationInfo(name: "石家庄", code: "SJP", coordinate: .init(latitude: 38.0489, longitude: 114.4944), city: "石家庄", province: "河北"),
        StationInfo(name: "保定东", code: "BMP", coordinate: .init(latitude: 38.8680, longitude: 115.5560), city: "保定", province: "河北"),
        StationInfo(name: "秦皇岛", code: "QTP", coordinate: .init(latitude: 39.9393, longitude: 119.5969), city: "秦皇岛", province: "河北"),
        StationInfo(name: "唐山", code: "TSP", coordinate: .init(latitude: 39.6317, longitude: 118.1809), city: "唐山", province: "河北"),
        // 山东
        StationInfo(name: "济南", code: "JNK", coordinate: .init(latitude: 36.6702, longitude: 116.9855), city: "济南", province: "山东"),
        StationInfo(name: "济南西", code: "JGK", coordinate: .init(latitude: 36.6602, longitude: 116.8575), city: "济南", province: "山东"),
        StationInfo(name: "济南东", code: "JDK", coordinate: .init(latitude: 36.6720, longitude: 117.1200), city: "济南", province: "山东"),
        StationInfo(name: "青岛", code: "QDK", coordinate: .init(latitude: 36.0759, longitude: 120.3144), city: "青岛", province: "山东"),
        StationInfo(name: "青岛北", code: "QHK", coordinate: .init(latitude: 36.1831, longitude: 120.3663), city: "青岛", province: "山东"),
        StationInfo(name: "烟台", code: "YAK", coordinate: .init(latitude: 37.4656, longitude: 121.3800), city: "烟台", province: "山东"),
        StationInfo(name: "威海", code: "WKK", coordinate: .init(latitude: 37.5135, longitude: 122.1205), city: "威海", province: "山东"),
        StationInfo(name: "潍坊", code: "WFK", coordinate: .init(latitude: 36.7061, longitude: 119.1068), city: "潍坊", province: "山东"),
        StationInfo(name: "泰安", code: "TMK", coordinate: .init(latitude: 36.1850, longitude: 117.1490), city: "泰安", province: "山东"),
        StationInfo(name: "曲阜东", code: "QFK", coordinate: .init(latitude: 35.6320, longitude: 116.9970), city: "济宁", province: "山东"),
        // 福建
        StationInfo(name: "福州", code: "FZS", coordinate: .init(latitude: 26.0481, longitude: 119.3073), city: "福州", province: "福建"),
        StationInfo(name: "福州南", code: "FYS", coordinate: .init(latitude: 25.9760, longitude: 119.2610), city: "福州", province: "福建"),
        StationInfo(name: "厦门", code: "XMS", coordinate: .init(latitude: 24.4798, longitude: 118.0587), city: "厦门", province: "福建"),
        StationInfo(name: "厦门北", code: "XKS", coordinate: .init(latitude: 24.6550, longitude: 118.0510), city: "厦门", province: "福建"),
        StationInfo(name: "泉州", code: "QYS", coordinate: .init(latitude: 24.9023, longitude: 118.6767), city: "泉州", province: "福建"),
        // 安徽
        StationInfo(name: "合肥", code: "HFH", coordinate: .init(latitude: 31.8818, longitude: 117.3084), city: "合肥", province: "安徽"),
        StationInfo(name: "合肥南", code: "ENH", coordinate: .init(latitude: 31.8052, longitude: 117.3088), city: "合肥", province: "安徽"),
        StationInfo(name: "蚌埠南", code: "BIH", coordinate: .init(latitude: 32.9350, longitude: 117.3750), city: "蚌埠", province: "安徽"),
        StationInfo(name: "黄山北", code: "NYH", coordinate: .init(latitude: 29.7770, longitude: 118.3060), city: "黄山", province: "安徽"),
        // 江西
        StationInfo(name: "南昌", code: "NCG", coordinate: .init(latitude: 28.6925, longitude: 115.9059), city: "南昌", province: "江西"),
        StationInfo(name: "南昌西", code: "NXG", coordinate: .init(latitude: 28.6873, longitude: 115.8390), city: "南昌", province: "江西"),
        StationInfo(name: "九江", code: "JJG", coordinate: .init(latitude: 29.7257, longitude: 116.0013), city: "九江", province: "江西"),
        // 辽宁
        StationInfo(name: "沈阳", code: "SYT", coordinate: .init(latitude: 41.8052, longitude: 123.4325), city: "沈阳", province: "辽宁"),
        StationInfo(name: "沈阳北", code: "SBT", coordinate: .init(latitude: 41.8259, longitude: 123.4270), city: "沈阳", province: "辽宁"),
        StationInfo(name: "沈阳南", code: "SOT", coordinate: .init(latitude: 41.7000, longitude: 123.4600), city: "沈阳", province: "辽宁"),
        StationInfo(name: "大连", code: "DLT", coordinate: .init(latitude: 38.8993, longitude: 121.6422), city: "大连", province: "辽宁"),
        StationInfo(name: "大连北", code: "DFT", coordinate: .init(latitude: 38.9790, longitude: 121.5950), city: "大连", province: "辽宁"),
        // 吉林
        StationInfo(name: "长春", code: "CCT", coordinate: .init(latitude: 43.8630, longitude: 125.3500), city: "长春", province: "吉林"),
        StationInfo(name: "长春西", code: "CRT", coordinate: .init(latitude: 43.8620, longitude: 125.2830), city: "长春", province: "吉林"),
        StationInfo(name: "吉林", code: "JLT", coordinate: .init(latitude: 43.8634, longitude: 126.5639), city: "吉林", province: "吉林"),
        // 黑龙江
        StationInfo(name: "哈尔滨", code: "HBB", coordinate: .init(latitude: 45.7553, longitude: 126.6587), city: "哈尔滨", province: "黑龙江"),
        StationInfo(name: "哈尔滨西", code: "VAB", coordinate: .init(latitude: 45.7380, longitude: 126.5820), city: "哈尔滨", province: "黑龙江"),
        // 陕西
        StationInfo(name: "西安", code: "XAY", coordinate: .init(latitude: 34.2726, longitude: 108.9398), city: "西安", province: "陕西"),
        StationInfo(name: "西安北", code: "EAY", coordinate: .init(latitude: 34.3747, longitude: 108.9396), city: "西安", province: "陕西"),
        // 山西
        StationInfo(name: "太原", code: "TYV", coordinate: .init(latitude: 37.8673, longitude: 112.5506), city: "太原", province: "山西"),
        StationInfo(name: "太原南", code: "TNV", coordinate: .init(latitude: 37.8100, longitude: 112.5600), city: "太原", province: "山西"),
        StationInfo(name: "大同", code: "DTV", coordinate: .init(latitude: 40.0757, longitude: 113.2988), city: "大同", province: "山西"),
        // 甘肃
        StationInfo(name: "兰州", code: "LZJ", coordinate: .init(latitude: 36.0506, longitude: 103.8412), city: "兰州", province: "甘肃"),
        StationInfo(name: "兰州西", code: "LAJ", coordinate: .init(latitude: 36.0872, longitude: 103.7349), city: "兰州", province: "甘肃"),
        // 云南
        StationInfo(name: "昆明", code: "KMM", coordinate: .init(latitude: 25.0194, longitude: 102.7183), city: "昆明", province: "云南"),
        StationInfo(name: "昆明南", code: "KOM", coordinate: .init(latitude: 24.9100, longitude: 102.8200), city: "昆明", province: "云南"),
        // 贵州
        StationInfo(name: "贵阳", code: "GIW", coordinate: .init(latitude: 26.6526, longitude: 106.7137), city: "贵阳", province: "贵州"),
        StationInfo(name: "贵阳北", code: "KQW", coordinate: .init(latitude: 26.6740, longitude: 106.7160), city: "贵阳", province: "贵州"),
        StationInfo(name: "贵阳东", code: "KEW", coordinate: .init(latitude: 26.6400, longitude: 106.8100), city: "贵阳", province: "贵州"),
        // 广西
        StationInfo(name: "南宁", code: "NNZ", coordinate: .init(latitude: 22.8217, longitude: 108.3550), city: "南宁", province: "广西"),
        StationInfo(name: "南宁东", code: "NFZ", coordinate: .init(latitude: 22.8110, longitude: 108.4340), city: "南宁", province: "广西"),
        StationInfo(name: "桂林", code: "GLZ", coordinate: .init(latitude: 25.2820, longitude: 110.2894), city: "桂林", province: "广西"),
        StationInfo(name: "桂林北", code: "GBZ", coordinate: .init(latitude: 25.3310, longitude: 110.2830), city: "桂林", province: "广西"),
        // 海南
        StationInfo(name: "海口", code: "VUQ", coordinate: .init(latitude: 20.0100, longitude: 110.3540), city: "海口", province: "海南"),
        StationInfo(name: "海口东", code: "HMQ", coordinate: .init(latitude: 20.0250, longitude: 110.3900), city: "海口", province: "海南"),
        StationInfo(name: "三亚", code: "SEQ", coordinate: .init(latitude: 18.2484, longitude: 109.5030), city: "三亚", province: "海南"),
        // 内蒙古
        StationInfo(name: "呼和浩特", code: "HHC", coordinate: .init(latitude: 40.8426, longitude: 111.7473), city: "呼和浩特", province: "内蒙古"),
        StationInfo(name: "呼和浩特东", code: "NDC", coordinate: .init(latitude: 40.8430, longitude: 111.8200), city: "呼和浩特", province: "内蒙古"),
        StationInfo(name: "包头", code: "BTC", coordinate: .init(latitude: 40.6569, longitude: 109.8284), city: "包头", province: "内蒙古"),
        // 新疆
        StationInfo(name: "乌鲁木齐", code: "WAR", coordinate: .init(latitude: 43.7960, longitude: 87.5831), city: "乌鲁木齐", province: "新疆"),
        StationInfo(name: "乌鲁木齐南", code: "WMR", coordinate: .init(latitude: 43.7840, longitude: 87.5700), city: "乌鲁木齐", province: "新疆"),
        // 宁夏
        StationInfo(name: "银川", code: "YIJ", coordinate: .init(latitude: 38.4899, longitude: 106.2328), city: "银川", province: "宁夏"),
        // 青海
        StationInfo(name: "西宁", code: "XNO", coordinate: .init(latitude: 36.6177, longitude: 101.7867), city: "西宁", province: "青海"),
        // 西藏
        StationInfo(name: "拉萨", code: "LSO", coordinate: .init(latitude: 29.6525, longitude: 91.0890), city: "拉萨", province: "西藏"),
        // 香港
        StationInfo(name: "香港西九龙", code: "XJA", coordinate: .init(latitude: 22.3048, longitude: 114.1617), city: "香港", province: "香港"),
    ]
}

// MARK: - JSON 序列化辅助
private struct CodableStation: Codable, Sendable {
    let name, code, city, province: String
    let lat, lon: Double

    nonisolated init(_ s: StationInfo) {
        name = s.name; code = s.code; city = s.city; province = s.province
        lat = s.coordinate.latitude; lon = s.coordinate.longitude
    }

    nonisolated var toStationInfo: StationInfo {
        StationInfo(name: name, code: code,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    city: city, province: province)
    }
}
