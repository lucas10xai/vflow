import Foundation

/// V4: dịch lại một câu đã có. Chỉ gửi văn bản khi người dùng chọn Dịch.
public struct TranslationResult: Equatable, Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

public extension EngineAPI {
    static func translateRequest(port: Int, token: String, text: String, target: String, formality: Tone) -> URLRequest {
        var request = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/translate"),
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "target": target, "formality": formality.rawValue])
        return request
    }

    static func parseTranslate(status: Int, data: Data) -> Result<TranslationResult, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.badResponse(status: status, detail: "thiếu trường text bản dịch"))
        }
        return .success(TranslationResult(text: text))
    }
}
