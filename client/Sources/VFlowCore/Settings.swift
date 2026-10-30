import Foundation

/// `tone` (contract mục "Giọng điệu và nói nhỏ"): CHỈ áp dụng cho `tidy`/`email` và CẦN `cloud_llm`
/// bật — không đổi guard, không đổi nghĩa/thêm thông tin.
public enum Tone: String, CaseIterable, Sendable {
    case neutral, formal, casual

    public var title: String {
        switch self {
        case .neutral: "Trung lập"
        case .formal: "Trang trọng"
        case .casual: "Thân mật"
        }
    }
}

public enum SpeechLanguage: String, CaseIterable, Sendable {
    case vietnamese = "vi", english = "en", automatic = "auto"
    public var title: String { switch self { case .vietnamese: "Tiếng Việt"; case .english: "Tiếng Anh"; case .automatic: "Tự nhận biết" } }
}

/// Ngôn ngữ khi nói nào CHỌN ĐƯỢC cho model hiện tại — nguồn DUY NHẤT dùng ở Cài đặt › Giọng nói
/// (`SettingsViewV2.languageEnabled`), tách khỏi SwiftUI để test được. `supportedLanguages`/
/// `autoDetect` lấy từ `Health.languages`/`Health.autoDetect` (từng model ở `/healthz`, KHÔNG xác
/// định khi `nil` — model cũ chưa báo, hoặc chưa model nào tải xong) — KHÔNG đoán hỗ trợ thêm tiếng
/// khi không xác định: `nil` ⇒ coi như model CHỈ tiếng Việt (an toàn — không hứa thứ chưa chắc có).
public enum SpeechLanguageAvailability {
    /// `nil` ⇒ chọn được bình thường; chuỗi ⇒ lý do vô hiệu hoá (hiện cạnh Picker).
    public static func disabledReason(_ language: SpeechLanguage, supportedLanguages: [String]?, autoDetect: Bool?) -> String? {
        let reason = "Model hiện tại chỉ nhận tiếng Việt — đổi model ở Cài đặt › Nâng cao"
        switch language {
        case .vietnamese:
            // "vi" luôn coi là khả dụng khi KHÔNG xác định (mặc định an toàn) hoặc khi engine liệt
            // kê đúng "vi"; mảng rỗng/thiếu "vi" (model lạ không nói tiếng Việt) mới chặn.
            return (supportedLanguages ?? ["vi"]).contains("vi") ? nil : reason
        case .english:
            return (supportedLanguages?.contains("en") ?? false) ? nil : reason
        case .automatic:
            return (autoDetect == true) ? nil : reason
        }
    }

    public static func isEnabled(_ language: SpeechLanguage, supportedLanguages: [String]?, autoDetect: Bool?) -> Bool {
        disabledReason(language, supportedLanguages: supportedLanguages, autoDetect: autoDetect) == nil
    }
}

public enum TranslationTarget: String, CaseIterable, Sendable {
    case english = "en", japanese = "ja", korean = "ko", chinese = "zh", french = "fr", german = "de", spanish = "es", thai = "th"
    public var title: String { switch self { case .english: "Tiếng Anh"; case .japanese: "Tiếng Nhật"; case .korean: "Tiếng Hàn"; case .chinese: "Tiếng Trung"; case .french: "Tiếng Pháp"; case .german: "Tiếng Đức"; case .spanish: "Tiếng Tây Ban Nha"; case .thai: "Tiếng Thái" } }
    public static func title(for code: String) -> String { Self(rawValue: code.lowercased())?.title ?? code.uppercased() }
}

public enum TranslationValidation {
    /// Đúng mã engine chấp nhận (`engine/post/settings.js`, `/^[a-z]{2,3}$/i` cho `translate_target`
    /// VÀ cho `target` của `POST /v1/translate`) — CHỈ 2–3 chữ cái thường/hoa, KHÔNG có tiểu thẻ
    /// vùng (`en-US`…): phiên bản cũ của hàm này lỏng hơn engine (nhận cả `xx-YY`), khiến ô "Khác…"
    /// coi là hợp lệ rồi gửi lên bị engine trả `400 bad_request` — SAI pha, đã sửa để khớp.
    public static func isValidISOCode(_ value: String) -> Bool { value.range(of: "^[a-zA-Z]{2,3}$", options: [.regularExpression]) != nil }
}

/// Luật `app_rules` (contract mục "Cài đặt người dùng"): bundle id → chế độ, KHÔNG gồm `auto`
/// (tránh đệ quy) — bảng được engine tra TRƯỚC `auto.apps` (cấu hình cứng) khi người dùng chọn `auto`.
public enum AppRuleMode: String, CaseIterable, Sendable {
    case normal, clean, dev, tidy, email

    public var dictationMode: DictationMode { DictationMode(rawValue: rawValue) ?? .normal }

    /// `true` ⇒ luật này gửi CHỮ qua 9Router (Gọn/Thư) — hiện cảnh báo khi `cloud_llm` đang tắt.
    public var sendsTextToCloud: Bool { dictationMode.sendsTextToCloud }
}

/// Một luật trong `app_rules`: ứng dụng (bundle id) → chế độ ghi đè `auto`.
public struct AppRule: Equatable, Sendable, Identifiable {
    public var bundleId: String
    public var mode: AppRuleMode
    public var id: String { bundleId }

    public init(bundleId: String, mode: AppRuleMode) {
        self.bundleId = bundleId
        self.mode = mode
    }
}

/// Kiểm hợp lệ `app_rules` phía client, khớp luật engine (`engine/post/settings.js`): bundle id
/// dạng reverse-DNS, tối đa 100 mục, chế độ nằm trong `AppRuleMode` (không có `auto`).
public enum AppRuleValidation {
    public static let bundleIdPattern = #"^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$"#
    public static let maxRules = 100

    public static func isValidBundleId(_ s: String) -> Bool {
        s.range(of: bundleIdPattern, options: .regularExpression) != nil
    }

    /// `nil` ⇒ hợp lệ; thêm/sửa `bundleId` (không phải `excludingBundleId`, dùng khi sửa một luật) dẫn
    /// tới vượt `maxRules` hoặc bundle id sai dạng thì báo lỗi tiếng Việt, không gửi lên engine.
    public static func error(bundleId: String, currentCount: Int, excludingBundleId: String? = nil) -> String? {
        let trimmed = bundleId.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Chưa chọn ứng dụng" }
        guard isValidBundleId(trimmed) else { return "Bundle id không hợp lệ: \"\(trimmed)\"" }
        let isNew = excludingBundleId != trimmed
        if isNew, currentCount >= maxRules { return "Tối đa \(maxRules) luật ứng dụng" }
        return nil
    }
}

/// Cài đặt người dùng (`GET/PUT /v1/settings`, contract/engine-api.md mục "Cài đặt người dùng").
/// Không bao giờ chứa khoá 9Router — chỉ các trường theo đúng hợp đồng.
public struct AppSettings: Equatable, Sendable {
    public var cloudLlm: Bool
    /// `nil` = chưa đặt model — Gọn/Thư/Command Mode sẽ không chạy được.
    public var llmModel: String?
    public var llmTimeoutMs: Int
    public var actionsEnabled: Bool
    /// Tự dừng ghi khi im lặng ở chế độ hands-free (0 = tắt, 1–60 giây); khoá chưa tồn tại ở engine
    /// cũ ⇒ coi là 0 (xem `EngineAPI.parseSettings`).
    public var silenceStopSeconds: Int
    public var statsEnabled: Bool
    public var appRules: [AppRule]
    public var voicePunctuation: Bool
    public var tone: Tone
    public var whisperMode: Bool
    public var learnFromEdits: Bool
    /// Xem chữ chạy trực tiếp (`POST /v1/partial`) — mặc định MỚI `true` (đo thật p95 111 ms, xem
    /// contract/engine-api.md).
    public var livePreview: Bool
    /// Ký hiệu theo ngữ cảnh ("gạch chéo", "a còng"… chỉ có hiệu lực trong app code/terminal/AI/
    /// Slack/Discord/Teams) — mặc định `true`, luôn có mặt theo hợp đồng.
    public var contextSymbols: Bool
    /// "Lưu âm thanh để nghe lại" (V3, Cài đặt › Dữ liệu) — mặc định TẮT; bật ⇒ engine lưu WAV ở
    /// `~/.vflow/audio`. Đây là công tắc phía engine; client chỉ đọc/đổi qua `PUT /v1/settings`
    /// (khi nghe lại, client chỉ giữ một tệp tạm 0600 trong thời gian phát rồi xoá — xem `AudioPlaybackController`).
    public var audioHistory: Bool
    public var audioHistoryMb: Int
    public var audioHistoryDays: Int
    public var sttLanguage: SpeechLanguage
    public var translateTarget: String
    public var translateFormality: Tone

    public init(cloudLlm: Bool, llmModel: String?, llmTimeoutMs: Int, actionsEnabled: Bool, silenceStopSeconds: Int = 0,
                statsEnabled: Bool = true, appRules: [AppRule] = [], voicePunctuation: Bool = true, tone: Tone = .neutral,
                whisperMode: Bool = false, learnFromEdits: Bool = true, livePreview: Bool = true,
                contextSymbols: Bool = true, audioHistory: Bool = false, audioHistoryMb: Int = 200, audioHistoryDays: Int = 7,
                sttLanguage: SpeechLanguage = .vietnamese, translateTarget: String = "en", translateFormality: Tone = .neutral) {
        self.cloudLlm = cloudLlm
        self.llmModel = llmModel
        self.llmTimeoutMs = llmTimeoutMs
        self.actionsEnabled = actionsEnabled
        self.silenceStopSeconds = silenceStopSeconds
        self.statsEnabled = statsEnabled
        self.appRules = appRules
        self.voicePunctuation = voicePunctuation
        self.tone = tone
        self.whisperMode = whisperMode
        self.learnFromEdits = learnFromEdits
        self.audioHistory = audioHistory
        self.audioHistoryMb = audioHistoryMb
        self.audioHistoryDays = audioHistoryDays
        self.livePreview = livePreview
        self.contextSymbols = contextSymbols
        self.sttLanguage = sttLanguage
        self.translateTarget = translateTarget
        self.translateFormality = translateFormality
    }
}

/// Tập con các trường muốn đổi — chỉ gửi những gì người dùng thật sự sửa.
public struct SettingsPatch: Sendable {
    public var cloudLlm: Bool?
    public var llmModel: String??  // Optional-of-Optional: nil = không đổi; .some(nil) = đặt về trống.
    public var llmTimeoutMs: Int?
    public var actionsEnabled: Bool?
    public var silenceStopSeconds: Int?
    public var statsEnabled: Bool?
    public var appRules: [AppRule]?
    public var voicePunctuation: Bool?
    public var tone: Tone?
    public var whisperMode: Bool?
    public var learnFromEdits: Bool?
    public var livePreview: Bool?
    public var contextSymbols: Bool?
    public var audioHistory: Bool?
    public var audioHistoryMb: Int?
    public var audioHistoryDays: Int?
    public var sttLanguage: SpeechLanguage?
    public var translateTarget: String?
    public var translateFormality: Tone?

    public init(cloudLlm: Bool? = nil, llmModel: String?? = nil, llmTimeoutMs: Int? = nil, actionsEnabled: Bool? = nil,
                silenceStopSeconds: Int? = nil, statsEnabled: Bool? = nil, appRules: [AppRule]? = nil,
                voicePunctuation: Bool? = nil, tone: Tone? = nil, whisperMode: Bool? = nil, learnFromEdits: Bool? = nil,
                livePreview: Bool? = nil, contextSymbols: Bool? = nil,
                audioHistory: Bool? = nil, audioHistoryMb: Int? = nil, audioHistoryDays: Int? = nil,
                sttLanguage: SpeechLanguage? = nil, translateTarget: String? = nil, translateFormality: Tone? = nil) {
        self.cloudLlm = cloudLlm
        self.llmModel = llmModel
        self.llmTimeoutMs = llmTimeoutMs
        self.actionsEnabled = actionsEnabled
        self.silenceStopSeconds = silenceStopSeconds
        self.statsEnabled = statsEnabled
        self.appRules = appRules
        self.voicePunctuation = voicePunctuation
        self.tone = tone
        self.whisperMode = whisperMode
        self.learnFromEdits = learnFromEdits
        self.livePreview = livePreview
        self.contextSymbols = contextSymbols
        self.audioHistory = audioHistory
        self.audioHistoryMb = audioHistoryMb
        self.audioHistoryDays = audioHistoryDays
        self.sttLanguage = sttLanguage
        self.translateTarget = translateTarget
        self.translateFormality = translateFormality
    }

    public var jsonObject: [String: Any] {
        var obj: [String: Any] = [:]
        if let v = cloudLlm { obj["cloud_llm"] = v }
        if let v = llmModel { obj["llm_model"] = v ?? NSNull() }
        if let v = llmTimeoutMs { obj["llm_timeout_ms"] = v }
        if let v = actionsEnabled { obj["actions_enabled"] = v }
        if let v = silenceStopSeconds { obj["silence_stop_seconds"] = v }
        if let v = statsEnabled { obj["stats_enabled"] = v }
        if let v = appRules { obj["app_rules"] = Dictionary(uniqueKeysWithValues: v.map { ($0.bundleId, $0.mode.rawValue) }) }
        if let v = voicePunctuation { obj["voice_punctuation"] = v }
        if let v = tone { obj["tone"] = v.rawValue }
        if let v = whisperMode { obj["whisper_mode"] = v }
        if let v = learnFromEdits { obj["learn_from_edits"] = v }
        if let v = livePreview { obj["live_preview"] = v }
        if let v = contextSymbols { obj["context_symbols"] = v }
        if let v = audioHistory { obj["audio_history"] = v }
        if let v = audioHistoryMb { obj["audio_history_mb"] = v }
        if let v = audioHistoryDays { obj["audio_history_days"] = v }
        if let v = sttLanguage { obj["stt_language"] = v.rawValue }
        if let v = translateTarget { obj["translate_target"] = v }
        if let v = translateFormality { obj["translate_formality"] = v.rawValue }
        return obj
    }
}

/// Kiểm hợp lệ phía client cho khu "Lưu âm thanh để nghe lại" (Cài đặt › Dữ liệu, V3), khớp hợp
/// đồng engine: `audio_history_mb` 50–2000, `audio_history_days` 1–90.
public enum AudioHistoryValidation {
    public static let minMb = 50
    public static let maxMb = 2000
    public static let minDays = 1
    public static let maxDays = 90

    public static func validateMb(_ mb: Int) -> Result<Void, SettingsValidationError> {
        guard mb >= minMb, mb <= maxMb else {
            return .failure(.init("Giới hạn dung lượng phải từ \(minMb)–\(maxMb) MB"))
        }
        return .success(())
    }

    public static func validateDays(_ days: Int) -> Result<Void, SettingsValidationError> {
        guard days >= minDays, days <= maxDays else {
            return .failure(.init("Số ngày giữ phải từ \(minDays)–\(maxDays) ngày"))
        }
        return .success(())
    }
}

/// Kiểm hợp lệ phía client, khớp luật engine (`engine/post/settings.js`): `llm_timeout_ms`
/// 1000–30000 (giây hiện ở UI, đổi đơn vị khi hiện); `llm_model` ≤200 ký tự hoặc trống/null.
public enum SettingsValidation {
    public static let minTimeoutMs = 1000
    public static let maxTimeoutMs = 30000
    public static let maxModelLen = 200

    public static func validateTimeoutMs(_ ms: Int) -> Result<Void, SettingsValidationError> {
        guard ms >= minTimeoutMs, ms <= maxTimeoutMs else {
            return .failure(.init("Thời gian chờ phải từ \(minTimeoutMs / 1000)–\(maxTimeoutMs / 1000) giây"))
        }
        return .success(())
    }

    public static func validateModel(_ model: String?) -> Result<Void, SettingsValidationError> {
        guard let model, model.count > maxModelLen else { return .success(()) }
        return .failure(.init("Tên model tối đa \(maxModelLen) ký tự"))
    }

    /// `0` = tắt tự dừng khi im lặng; `1–60` = số giây (khớp luật engine `engine/post/settings.js`).
    public static func validateSilenceStopSeconds(_ seconds: Int) -> Result<Void, SettingsValidationError> {
        guard seconds >= 0, seconds <= 60 else {
            return .failure(.init("Thời gian im lặng để tự dừng phải từ 0 (tắt) đến 60 giây"))
        }
        return .success(())
    }
}

public struct SettingsValidationError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public struct CommandResult: Equatable, Sendable {
    public var text: String
    /// "edit" (có đoạn chọn, chỉ trả đoạn thay thế) hoặc "draft" (soạn mới).
    public var kind: String
}

/// Quyết định có gửi phím Enter sau khi dán hay không — thuần, dùng chung cho AppController test.
public enum EnterAction {
    public static func shouldSend(actions: [String], actionsEnabled: Bool) -> Bool {
        actionsEnabled && actions.contains("enter")
    }
}
