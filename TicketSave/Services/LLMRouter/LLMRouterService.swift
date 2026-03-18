import Foundation

enum LLMRouterError: LocalizedError {
    case invalidResponse
    case networkError(Error)
    case decodeError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "LLM 返回了无效的响应"
        case .networkError(let error): return "网络请求失败: \(error.localizedDescription)"
        case .decodeError(let error): return "解析响应失败: \(error.localizedDescription)"
        }
    }
}

protocol LLMRouterProtocol: Sendable {
    func parseTicketInfo(from text: String) async throws -> OCRTicketExtraction
}

final class LLMRouterService: LLMRouterProtocol {
    // 后面可以配置真实的 apiKey 和 baseURL
    private let apiKey = "sk-0eaa23e603d04282afd25cd37ba3af0a"
    private let baseURL = "https://api.deepseek.com/chat/completions"
    
    func parseTicketInfo(from text: String) async throws -> OCRTicketExtraction {
        let prompt = """
        你是一个专门提取车票信息的助手。你需要从以下带空格的 OCR 识别文本中提取出所有指定的字段，并返回一段纯 JSON。
        
        如果文本中缺失某个字段，请尝试推断，不然就提供空字符串。
        座位号通常是类似 "05车 06F号"，如果不确定可以提取相关的数字和字母。注意：由于OCR识别的误差，"车厢"的"车"字经常被错识别为"年"（例如"04年08F号"实为"04车08F号"），请自行纠正。出站时间需要解析为 ISO8601 格式或者标准时间字符串。
        不要返回任何 Markdown 标记（例如 ```json），直接返回一个符合以下 Swift 等效结构的 JSON。
        返回字段必须精确包含：
        {
            "departureStation": "始发站",
            "trainNumber": "车次(如 G123)",
            "arrivalStation": "终点站",
            "departureTime": "发车时间的ISO8601字符串(例如 2026-03-18T14:30:00Z)",
            "carriageNumber": "车厢号(例如 05)",
            "seatNumber": "座位号(例如 06F)",
            "price": 票价(数字如 123.5),
            "ticketType": "票种(如 成人票)",
            "seatClass": "座位等级(如 二等座)"
        }
        
        文本：
        \(text)
        """
        
        // 此处是标准的调用代码，如果报错可尝试调整模型。
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)"
        ]
        
        let parameters: [String: Any] = [
            "model": "deepseek-chat", // Use your preferred model here
            "messages": [
                [
                    "role": "system",
                    "content": "你是一个只输出 JSON 数据的解析助手。不要有多余的聊天。只输出 JSON 对象。"
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.0
        ]
        
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
        } catch {
            throw error
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            // print(String(data: data, encoding: .utf8))
            throw LLMRouterError.invalidResponse
        }
        
        do {
            let jsonObj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            guard let choices = jsonObj?["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw LLMRouterError.invalidResponse
            }
            
            // Clean up possible markdown wrappers
            let cleanJson = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
            
            guard let jsonData = cleanJson.data(using: .utf8) else {
                throw LLMRouterError.invalidResponse
            }

            return try parseExtraction(from: jsonData)
            
        } catch {
            throw LLMRouterError.decodeError(error)
        }
    }

    private func parseExtraction(from jsonData: Data) throws -> OCRTicketExtraction {
        guard let dict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw LLMRouterError.invalidResponse
        }

        var extraction = OCRTicketExtraction()
        extraction.departureStation = (dict["departureStation"] as? String) ?? ""
        extraction.trainNumber = (dict["trainNumber"] as? String) ?? ""
        extraction.arrivalStation = (dict["arrivalStation"] as? String) ?? ""
        extraction.departureTime = parseDate(dict["departureTime"])
        extraction.carriageNumber = (dict["carriageNumber"] as? String) ?? ""
        extraction.seatNumber = (dict["seatNumber"] as? String) ?? ""
        extraction.price = parsePrice(dict["price"])
        extraction.ticketType = (dict["ticketType"] as? String) ?? ""
        extraction.seatClass = (dict["seatClass"] as? String) ?? ""
        return extraction
    }

    private func parseDate(_ value: Any?) -> Date {
        guard let raw = value as? String else { return .distantPast }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .distantPast }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }

        let fallbackISO = ISO8601DateFormatter()
        if let date = fallbackISO.date(from: text) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: text) { return date }

        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: text) { return date }

        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text) ?? .distantPast
    }

    private func parsePrice(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            let cleaned = trimmed
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "￥", with: "")
                .replacingOccurrences(of: ",", with: "")
            return Double(cleaned) ?? 0
        }
        return 0
    }
}
