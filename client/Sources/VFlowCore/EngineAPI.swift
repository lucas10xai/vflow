import Foundation

public enum DictationMode: String, CaseIterable, Sendable {
    case auto, normal, clean, email, tidy, dev, translate

    public var title: String {
        switch self {
        case .auto: "Tự động (theo ứng dụng)"
        case .normal: "Thường"
        case .clean: "Làm sạch"
        case .email: "Thư (viết lại)"
        case .tidy: "Gọn"
        case .dev: "Lập trình"
        case .translate: "Dịch"
        }
    }

    /// `true` ⇒ chế độ này gửi CHỮ (không phải âm thanh) ra 9Router; hiện ở tab Tổng quan/Cài đặt.
    public var sendsTextToCloud: Bool {
        switch self {
        case .tidy, .email, .translate: true
        case .auto, .normal, .clean, .dev: false
        }
    }

    /// Mô tả ngắn dưới mỗi chế độ (chọn chế độ ở Tổng quan/Cài đặt).
    public var subtitle: String {
        switch self {
        case .auto: "Tự chọn theo ứng dụng: Lập trình trong terminal/IDE, Làm sạch trong thư/chat, Thường ở nơi khác. Muốn dùng Gọn hoặc Thư hãy chọn thủ công."
        case .normal: "Trong máy — chỉ nhận dạng giọng nói + từ điển"
        case .clean: "Trong máy — bỏ từ đệm, sửa dấu câu cơ bản"
        case .email: "Gửi chữ qua 9Router — viết lại thành thư chuyên nghiệp"
        case .tidy: "Gửi chữ qua 9Router — thêm dấu câu, bỏ từ đệm, tự sửa giữa câu"
        case .dev: "Trong máy — đọc kiểu lập trình (gạch dưới, snake_case…)"
        case .translate: "Gửi chữ qua máy chủ của bạn để dịch sang ngôn ngữ đã chọn"
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
    /// Kiểm hợp lệ phía client (snippets) thất bại trước khi gửi engine.
    case snippetInvalid(String)
    /// Không gửi được ⌘V/Return tổng hợp (thiếu quyền Trợ năng) khi gửi phím Enter sau khi dán.
    case enterKeystrokeFailed
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
            case "rewrite_unavailable": return message.isEmpty ? "Dịch vụ viết lại không khả dụng" : message
            case "cloud_disabled": return message.isEmpty ? "Chế độ đám mây đang tắt" : message
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
        case let .snippetInvalid(d): return d
        case .enterKeystrokeFailed: return "Không gửi được phím Enter (thiếu quyền Trợ năng)"
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
    /// `post.actions` — hiện chỉ có `"enter"` (xem `EnterAction`).
    public var actions: [String] = []
    /// `post.degraded`/`post.degraded_reason` (contract mục "Chế độ", item 7): `true` kèm một trong
    /// `"llm_timeout"|"llm_error"|"guard"|"cloud_disabled"` khi kết quả là bản dự phòng cục bộ thay
    /// cho đám mây đã định — xem `DegradedText`.
    public var degraded: Bool = false
    public var degradedReason: String?
    /// `audio_id` (V3): có mặt CHỈ khi "Lưu âm thanh để nghe lại" đang bật ở engine lúc xử lý yêu
    /// cầu này và việc ghi thành công — dùng để `GET/DELETE /v1/audio/<id>` (xem `HistoryEntry.audioId`).
    public var audioId: String?
}

public struct ModelStatus: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var loaded: Bool
    public var reason: String?
    /// Khả năng CỦA RIÊNG model này, như engine báo trong từng mục `models[]` ở `/healthz`
    /// (contract mục Cấu hình: "từng model") — KHÔNG phải một trường chung ở gốc JSON.
    public var languages: [String]? = nil
    public var autoDetect: Bool? = nil
}

public struct Health: Equatable, Sendable {
    public var version: String
    public var models: [ModelStatus]
    /// `max_audio_seconds` ở `/healthz` nếu engine có báo (chưa có trong contract hiện tại ⇒ thường
    /// `nil` — xem `RecordingLimit.resolve`, KHÔNG suy đoán khi vắng mặt).
    public var maxAudioSeconds: Int?
    /// Khả năng model hiện tại; thiếu/null từ engine cũ là không xác định.
    public var languages: [String]?
    public var autoDetect: Bool?

    public init(version: String, models: [ModelStatus], maxAudioSeconds: Int? = nil,
                languages: [String]? = nil, autoDetect: Bool? = nil) {
        self.version = version
        self.models = models
        self.maxAudioSeconds = maxAudioSeconds
        self.languages = languages
        self.autoDetect = autoDetect
    }
}

public enum EngineAPI {
    public static let host = "127.0.0.1"

    public static func baseURL(port: Int) -> URL {
        URL(string: "http://\(host):\(port)")!
    }

    public static func transcribeRequest(port: Int, token: String, pcm: Data, mode: DictationMode,
                                         app: String?, model: String? = nil, timeout: TimeInterval = 150) -> URLRequest {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        c.path = "/v1/transcribe"
        var q = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let app, !app.isEmpty { q.append(URLQueryItem(name: "app", value: app)) }
        // Model đang dùng (lựa chọn của người dùng ở Cài đặt › Nâng cao) — vắng mặt ⇒ engine tự lấy
        // `default_model` từ cấu hình (hành vi cũ, không đổi khi chưa ai chọn model nào).
        if let model, !model.isEmpty { q.append(URLQueryItem(name: "model", value: model)) }
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
            audioMs: obj["audio_ms"] as? Int,
            actions: (post?["actions"] as? [String]) ?? [],
            degraded: post?["degraded"] as? Bool ?? false,
            degradedReason: post?["degraded_reason"] as? String,
            audioId: obj["audio_id"] as? String))
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

    // MARK: snippets

    public static func snippetsGetRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/snippets"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    public static func snippetsPutRequest(port: Int, token: String, entries: [SnippetEntry]) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/snippets"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "PUT"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["entries": entries.map(encodeSnippet)])
        return r
    }

    static func encodeSnippet(_ e: SnippetEntry) -> [String: Any] {
        var obj: [String: Any] = ["trigger": e.trigger, "text": e.text, "uses": e.uses]
        if let l = e.lastUsed { obj["last_used"] = l }
        return obj
    }

    static func decodeSnippet(_ obj: [String: Any]) -> SnippetEntry? {
        guard let trigger = obj["trigger"] as? String, let text = obj["text"] as? String else { return nil }
        return SnippetEntry(trigger: trigger, text: text, uses: obj["uses"] as? Int ?? 0, lastUsed: obj["last_used"] as? String)
    }

    public static func parseSnippetList(status: Int, data: Data) -> Result<[SnippetEntry], ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawEntries = obj["entries"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường entries"))
        }
        return .success(rawEntries.compactMap(decodeSnippet))
    }

    // MARK: cài đặt

    public static func settingsGetRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/settings"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    public static func settingsPutRequest(port: Int, token: String, patch: SettingsPatch) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/settings"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "PUT"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: patch.jsonObject)
        return r
    }

    public static func parseSettings(status: Int, data: Data) -> Result<AppSettings, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = appSettings(from: obj) else {
            return .failure(.badResponse(status: status, detail: "thiếu trường cài đặt"))
        }
        return .success(settings)
    }

    /// Dùng chung cho `GET /v1/settings`, `GET /v1/diagnostics.settings`, `GET /v1/export.settings` —
    /// MỘT nơi quyết định mặc định khi khoá vắng mặt (engine cũ). `nil` nếu thiếu 3 trường bắt buộc
    /// (cloud_llm/llm_timeout_ms/actions_enabled — luôn có mặt theo hợp đồng).
    static func appSettings(from obj: [String: Any]) -> AppSettings? {
        guard let cloudLlm = obj["cloud_llm"] as? Bool,
              let llmTimeoutMs = obj["llm_timeout_ms"] as? Int,
              let actionsEnabled = obj["actions_enabled"] as? Bool else { return nil }
        let llmModel = obj["llm_model"] as? String
        // Khoá chưa tồn tại (engine cũ chưa có các trường item 2–7) ⇒ dùng mặc định hiện hành
        // (KHÔNG lỗi — engine cũ vẫn phải dùng được, xem contract/engine-api.md mục Cài đặt).
        let silenceStopSeconds = obj["silence_stop_seconds"] as? Int ?? 0
        let statsEnabled = obj["stats_enabled"] as? Bool ?? true
        let rawAppRules = obj["app_rules"] as? [String: String] ?? [:]
        let appRules = rawAppRules.compactMap { key, value -> AppRule? in
            guard let mode = AppRuleMode(rawValue: value) else { return nil }
            return AppRule(bundleId: key, mode: mode)
        }.sorted { $0.bundleId < $1.bundleId }
        let voicePunctuation = obj["voice_punctuation"] as? Bool ?? true
        let tone = Tone(rawValue: obj["tone"] as? String ?? "") ?? .neutral
        let whisperMode = obj["whisper_mode"] as? Bool ?? false
        let learnFromEdits = obj["learn_from_edits"] as? Bool ?? true
        let livePreview = obj["live_preview"] as? Bool ?? true
        let contextSymbols = obj["context_symbols"] as? Bool ?? true
        let audioHistory = obj["audio_history"] as? Bool ?? false
        let audioHistoryMb = obj["audio_history_mb"] as? Int ?? 200
        let audioHistoryDays = obj["audio_history_days"] as? Int ?? 7
        let sttLanguage = SpeechLanguage(rawValue: obj["stt_language"] as? String ?? "") ?? .vietnamese
        let translateTarget = obj["translate_target"] as? String ?? "en"
        let translateFormality = Tone(rawValue: obj["translate_formality"] as? String ?? "") ?? .neutral
        return AppSettings(cloudLlm: cloudLlm, llmModel: llmModel, llmTimeoutMs: llmTimeoutMs,
                           actionsEnabled: actionsEnabled, silenceStopSeconds: silenceStopSeconds,
                           statsEnabled: statsEnabled, appRules: appRules, voicePunctuation: voicePunctuation,
                           tone: tone, whisperMode: whisperMode, learnFromEdits: learnFromEdits,
                           livePreview: livePreview, contextSymbols: contextSymbols,
                           audioHistory: audioHistory, audioHistoryMb: audioHistoryMb, audioHistoryDays: audioHistoryDays,
                           sttLanguage: sttLanguage, translateTarget: translateTarget, translateFormality: translateFormality)
    }

    // MARK: Command Mode

    public static func commandRequest(port: Int, token: String, instruction: String, selection: String,
                                      context: String, app: String?, timeout: TimeInterval = 30) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/command"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["instruction": instruction, "selection": selection, "context": context]
        if let app { body["app"] = app }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    public static func parseCommand(status: Int, data: Data) -> Result<CommandResult, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String, let kind = obj["kind"] as? String else {
            return .failure(.badResponse(status: status, detail: "thiếu trường text/kind"))
        }
        return .success(CommandResult(text: text, kind: kind))
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

    /// Giải mã MỘT mục trong `models[]` (dùng chung cho `/healthz` và `GET /v1/models` — cùng hình
    /// dạng từng mục theo contract/engine-api.md). `nil` nếu thiếu `id`.
    static func decodeModelStatus(_ m: [String: Any]) -> ModelStatus? {
        guard let id = m["id"] as? String else { return nil }
        return ModelStatus(id: id, kind: m["kind"] as? String ?? "?",
                           loaded: m["loaded"] as? Bool ?? false, reason: m["reason"] as? String,
                           languages: m["languages"] as? [String],
                           autoDetect: m["auto_detect"] is NSNull ? nil : m["auto_detect"] as? Bool)
    }

    /// `GET /v1/models` (cần token) — màn hình chọn model (Cài đặt › Nâng cao).
    public static func modelsRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/models"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    public static func parseModelList(status: Int, data: Data) -> Result<[ModelStatus], ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường models"))
        }
        return .success(models.compactMap(decodeModelStatus))
    }

    /// `nil` ⇒ có gì đó nghe cổng nhưng không phải engine vflow.
    public static func parseHealth(status: Int, data: Data) -> Health? {
        guard status == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true,
              let version = obj["version"] as? String,
              let models = obj["models"] as? [[String: Any]] else { return nil }
        let modelStatus = models.compactMap(decodeModelStatus)
        // Khả năng ngôn ngữ nằm TỪNG model (contract), không có trường chung ở gốc JSON — lấy theo
        // model ĐANG TẢI XONG (thật sự dùng được); chưa model nào tải xong ⇒ không xác định (`nil`),
        // KHÔNG đoán để UI coi là "chỉ tiếng Việt" một cách an toàn (xem `languageEnabled`).
        let active = modelStatus.first { $0.loaded }
        return Health(version: version, models: modelStatus,
                      maxAudioSeconds: obj["max_audio_seconds"] as? Int,
                      languages: active?.languages, autoDetect: active?.autoDetect)
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
