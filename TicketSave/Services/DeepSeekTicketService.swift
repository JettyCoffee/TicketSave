import Foundation
import UIKit

struct DeepSeekTicketService: Sendable {
    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    static func recognizeTicket(from image: UIImage) async throws -> TicketInfo {
        guard let apiKey = AppSecretsStore.loadDeepSeekAPIKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekTicketError.missingAPIKey
        }
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw DeepSeekTicketError.invalidImage
        }

        let base64Image = imageData.base64EncodedString()
        let prompt = """
        你是中国火车票识别助手。请完成两件事：
        1) 从图片中提取车票核心字段。
        2) 根据识别出的车次、日期、出发站、到达站，联网查询该车次当天对应区间的时刻表并给出发到时间。

        你必须只返回一个 JSON 对象，不要返回 markdown，不要返回额外说明。
        JSON 字段如下：
        {
          "orderNumber": "",
          "trainNumber": "",
          "departureStation": "",
          "arrivalStation": "",
          "departureTime": "yyyy-MM-dd HH:mm",
          "arrivalTime": "yyyy-MM-dd HH:mm",
          "carriageNumber": "",
          "seatNumber": "",
          "seatClass": "",
          "price": 0,
          "passengerName": "",
          "scheduleChecked": true,
          "scheduleSource": ""
        }

        规则：
        - 无法确认时填空字符串，price 无法确认填 0。
        - departureTime / arrivalTime 要尽量使用联网查询后的准确时刻，不要用估算值。
        - 站名输出中文标准站名，不带“站”后缀。
        - 车厢号输出两位数字，如 06。

        下面是车票图片的 base64（JPEG）：
        \(base64Image)
        """

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0.1,
            "messages": [
                [
                    "role": "system",
                    "content": "你是严谨的信息抽取与事实核验助手。"
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekTicketError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekTicketError.httpError(statusCode: http.statusCode, body: serverMessage)
        }

        let decoded = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekTicketError.emptyModelOutput
        }

        let jsonString = extractJSONObject(from: content)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw DeepSeekTicketError.invalidModelJSON
        }
        let output = try JSONDecoder().decode(DeepSeekTicketOutput.self, from: jsonData)

        var info = TicketInfo()
        info.orderNumber = output.orderNumber?.trimmed ?? ""
        info.trainNumber = output.trainNumber?.trimmed.uppercased() ?? ""
        info.departureStation = normalizeStationName(output.departureStation)
        info.arrivalStation = normalizeStationName(output.arrivalStation)
        info.carriageNumber = normalizeCarriage(output.carriageNumber)
        info.seatNumber = output.seatNumber?.trimmed ?? ""
        info.seatClass = output.seatClass?.trimmed.isEmpty == false ? output.seatClass!.trimmed : "二等座"
        info.price = output.price ?? 0
        info.passengerName = output.passengerName?.trimmed ?? ""

        if let departure = parseDate(output.departureTime) {
            info.departureTime = departure
        }
        if let arrival = parseDate(output.arrivalTime) {
            info.arrivalTime = arrival
        }

        return info
    }

    private static func normalizeStationName(_ value: String?) -> String {
        guard let value else { return "" }
        return value.trimmed.replacingOccurrences(of: "站", with: "")
    }

    private static func normalizeCarriage(_ value: String?) -> String {
        guard let value else { return "" }
        let digits = value.filter { $0.isNumber }
        guard let intVal = Int(digits) else { return "" }
        return String(format: "%02d", intVal)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmed.isEmpty else { return nil }
        let candidates = [
            "yyyy-MM-dd HH:mm",
            "yyyy/M/d HH:mm",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]
        for format in candidates {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw.trimmed) {
                return date
            }
        }
        return nil
    }

    private static func extractJSONObject(from content: String) -> String {
        if let start = content.firstIndex(of: "{"),
           let end = content.lastIndex(of: "}") {
            return String(content[start...end])
        }
        return content
    }
}

private struct DeepSeekChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}

private struct DeepSeekTicketOutput: Decodable {
    let orderNumber: String?
    let trainNumber: String?
    let departureStation: String?
    let arrivalStation: String?
    let departureTime: String?
    let arrivalTime: String?
    let carriageNumber: String?
    let seatNumber: String?
    let seatClass: String?
    let price: Double?
    let passengerName: String?
}

enum DeepSeekTicketError: Error, LocalizedError {
    case missingAPIKey
    case invalidImage
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case emptyModelOutput
    case invalidModelJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 DeepSeek API Key，请先到设置页填写。"
        case .invalidImage:
            return "无法处理图片数据"
        case .invalidResponse:
            return "服务返回无效响应"
        case .httpError(let statusCode, let body):
            return "DeepSeek 请求失败 (\(statusCode)): \(body)"
        case .emptyModelOutput:
            return "DeepSeek 未返回可用结果"
        case .invalidModelJSON:
            return "DeepSeek 返回格式不是有效 JSON"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
