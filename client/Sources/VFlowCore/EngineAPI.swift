import Foundation

public enum DictationMode: String, CaseIterable, Sendable {
    case auto, normal, clean, email

    public var title: String {
        switch self {
        case .auto: "Tự động (theo ứng dụng)"
        case .normal: "Thường"
        case .clean: "Làm sạch"
        case .email: "Thư (viết lại)"
        }
    }
}

/// Lỗi phía client, luôn hiện được thành thông điệp tiếng Việt (không nuốt lỗi).
public enum ClientError: Error, Equatable, Sendable {
    /// Engine trả lỗi theo hợp đồng `{error:{code,message}}`.
    case engine(status: Int, code: String, message: String)
    /// Phản hồi không theo hợp đồng.
    case badResponse(status: Int, detail: String)
    case engineNotRunning
    case network(String)
    case tokenMissing(path: String)
    case tokenInvalid(path: String)
    case micDenied
    case micUnavailable(String)
    case accessibilityDenied
    case inputMonitoringDenied
    case engineGaveUp(String)
    case configInvalid(String)
    /// Kiểm hợp lệ phía client (từ điển) thất bại trước khi gửi engine — không phải lỗi engine.
    case dictionaryInvalid(String)
}

public enum ErrorText {
    /// Thông điệp ngắn cho thanh trạng thái và menu.
    public static func message(_ error: ClientError) -> String {
        switch error {
        case let .engine(status, code, message):
            switch code {
            case "unauthorized":
                return status == 403 ? "Engine từ chối yêu cầu (Host/Origin)" : "Sai token engine (~/.vflow/token)"
            case "bad_audio": return "Âm thanh không hợp lệ"
            case "bad_request": return "Yêu cầu không hợp lệ: \(message)"
            case "model_unavailable":
                if let reason = reason(in: message) { return "Model chưa sẵn sàng (\(reason))" }
                return "Model chưa sẵn sàng: \(message)"
            case "timeout": return "Engine xử lý quá thời gian"
            case "payload_too_large": return "Đoạn ghi quá dài (tối đa 120 giây)"
            case "internal": return "Lỗi nội bộ engine"
            default: return "Lỗi engine (\(code)): \(message)"
            }
        case let .badResponse(status, detail): return "Engine trả phản hồi lạ (HTTP \(status)): \(detail)"
        case .engineNotRunning: return "Engine không chạy"
        case let .network(d): return "Không kết nối được engine: \(d)"
        case let .tokenMissing(path): return "Thiếu tệp token \(path)"
        case let .tokenInvalid(path): return "Tệp token hỏng \(path)"
        case .micDenied: return "Chưa cấp quyền Micro"
        case let .micUnavailable(d): return "Micro không dùng được: \(d)"
        case .accessibilityDenied: return "Thiếu quyền Trợ năng (Accessibility) để dán"
        case .inputMonitoringDenied: return "Thiếu quyền Theo dõi đầu vào (Input Monitoring)"
        case let .engineGaveUp(d): return "Engine chết liên tục, đã ngừng khởi động lại: \(d)"
        case let .configInvalid(d): return "Cấu hình client lỗi: \(d)"
        case let .dictionaryInvalid(d): return d
        }
    }

    /// Engine nối lý do dạng “… (lý do: tunnel_down)”.
    static func reason(in message: String) -> String? {
        guard let r = message.range(of: "(lý do: ") else { return nil }
        let rest = message[r.upperBound...]
        guard let end = rest.firstIndex(of: ")") else { return nil }
        let s = String(rest[..<end])
        return s.isEmpty ? nil : s
    }
}

public struct TranscribeResult: Equatable, Sendable {
    public var text: String
    public var silence: Bool
    public var mode: String
    public var model: String
    /// `post.rewrite.error` khi chế độ email viết lại hỏng (text vẫn dùng được).
    public var rewriteError: String?
    public var totalMs: Int?
    /// Chữ gốc do STT trả (chưa qua từ điển/viết lại) — dùng cho Lịch sử, không hiện ở thanh trạng thái.
    public var textRaw: String = ""
    public var audioMs: Int?
}

public struct ModelStatus: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var loaded: Bool
    public var reason: String?
}

public struct Health: Equatable, Sendable {
    public var version: String
    public var models: [ModelStatus]
}

public enum EngineAPI {
    public static let host = "127.0.0.1"

    public static func baseURL(port: Int) -> URL {
        URL(string: "http://\(host):\(port)")!
    }

    public static func transcribeRequest(port: Int, token: String, pcm: Data, mode: DictationMode,
                                         app: String?, timeout: TimeInterval = 150) -> URLRequest {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        c.path = "/v1/transcribe"
        var q = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let app, !app.isEmpty { q.append(URLQueryItem(name: "app", value: app)) }
        c.queryItems = q
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("audio/L16; rate=16000; channels=1", forHTTPHeaderField: "Content-Type")
        r.httpBody = pcm
        return r
    }

    public static func healthRequest(port: Int) -> URLRequest {
        URLRequest(url: baseURL(port: port).appendingPathComponent("healthz"),
                   cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2)
    }

    /// Lỗi hợp đồng `{error:{code,message}}` hoặc `badResponse`.
    static func errorFrom(status: Int, data: Data) -> ClientError {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any], let code = err["code"] as? String {
            return .engine(status: status, code: code, message: err["message"] as? String ?? "")
        }
        return .badResponse(status: status, detail: snippet(data))
    }

    public static func parseTranscribe(status: Int, data: Data) -> Result<TranscribeResult, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.badResponse(status: status, detail: "không phải JSON"))
        }
        guard let text = obj["text"] as? String else {
            return .failure(.badResponse(status: status, detail: "thiếu trường text"))
        }
        let post = obj["post"] as? [String: Any]
        let rewrite = post?["rewrite"] as? [String: Any]
        let timings = obj["timings_ms"] as? [String: Any]
        return .success(TranscribeResult(
            text: text,
            silence: obj["silence"] as? Bool ?? false,
            mode: obj["mode"] as? String ?? "",
            model: obj["model"] as? String ?? "",
            rewriteError: rewrite?["error"] as? String,
            totalMs: timings?["total"] as? Int,
            textRaw: obj["text_raw"] as? String ?? "",
            audioMs: obj["audio_ms"] as? Int))
    }

    // MARK: từ điển + gợi ý sửa

    public static func dictionaryGetRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/dictionary"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    public static func dictionaryPutRequest(port: Int, token: String, entries: [DictionaryEntry]) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/dictionary"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "PUT"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["entries": entries.map(encodeEntry)])
        return r
    }

    public static func correctionsRequest(port: Int, token: String, before: String, after: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/corrections"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["before": before, "after": after])
        return r
    }

    static func encodeEntry(_ e: DictionaryEntry) -> [String: Any] {
        var obj: [String: Any] = ["term": e.term, "spoken": e.spoken, "kind": e.kind, "uses": e.uses]
        if e.caseExact { obj["case"] = "exact" }
        if let l = e.lastUsed { obj["last_used"] = l }
        return obj
    }

    static func decodeEntry(_ obj: [String: Any]) -> DictionaryEntry? {
        guard let term = obj["term"] as? String, let spoken = obj["spoken"] as? [String] else { return nil }
        return DictionaryEntry(term: term, spoken: spoken, kind: obj["kind"] as? String ?? "term",
                               caseExact: (obj["case"] as? String) == "exact", uses: obj["uses"] as? Int ?? 0,
                               lastUsed: obj["last_used"] as? String)
    }

    public static func parseDictionaryList(status: Int, data: Data) -> Result<[DictionaryEntry], ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawEntries = obj["entries"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường entries"))
        }
        return .success(rawEntries.compactMap(decodeEntry))
    }

    public static func parseCorrections(status: Int, data: Data) -> Result<[CorrectionSuggestion], ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSuggestions = obj["suggestions"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường suggestions"))
        }
        return .success(rawSuggestions.compactMap { s in
            guard let term = s["term"] as? String, let spoken = s["spoken"] as? [String] else { return nil }
            return CorrectionSuggestion(term: term, spoken: spoken)
        })
    }

    /// `nil` ⇒ có gì đó nghe cổng nhưng không phải engine vflow.
    public static func parseHealth(status: Int, data: Data) -> Health? {
        guard status == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true,
              let version = obj["version"] as? String,
              let models = obj["models"] as? [[String: Any]] else { return nil }
        return Health(version: version, models: models.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return ModelStatus(id: id, kind: m["kind"] as? String ?? "?",
                               loaded: m["loaded"] as? Bool ?? false, reason: m["reason"] as? String)
        })
    }

    /// Dòng hiển thị trong menu cho một model.
    public static func menuLine(_ m: ModelStatus) -> String {
        if m.loaded { return "\(m.id) (\(m.kind)): sẵn sàng" }
        return "\(m.id) (\(m.kind)): chưa tải — \(m.reason ?? "không rõ lý do")"
    }

    static func snippet(_ data: Data) -> String {
        let s = String(decoding: data.prefix(120), as: UTF8.self)
        return s.isEmpty ? "thân rỗng" : s
    }

    /// Đọc token (64 hex) từ nội dung tệp.
    public static func parseToken(_ contents: String) -> String? {
        let t = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 64, t.allSatisfy({ $0.isHexDigit && ($0.isNumber || $0.isLowercase) }) else { return nil }
        return t
    }
}
