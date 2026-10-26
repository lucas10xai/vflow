import Foundation

/// Cài đặt người dùng (`GET/PUT /v1/settings`, contract/engine-api.md mục "Cài đặt người dùng").
/// Không bao giờ chứa khoá 9Router — chỉ bốn trường này.
public struct AppSettings: Equatable, Sendable {
    public var cloudLlm: Bool
    /// `nil` = chưa đặt model — Gọn/Thư/Command Mode sẽ không chạy được.
    public var llmModel: String?
    public var llmTimeoutMs: Int
    public var actionsEnabled: Bool

    public init(cloudLlm: Bool, llmModel: String?, llmTimeoutMs: Int, actionsEnabled: Bool) {
        self.cloudLlm = cloudLlm
        self.llmModel = llmModel
        self.llmTimeoutMs = llmTimeoutMs
        self.actionsEnabled = actionsEnabled
    }
}

/// Tập con các trường muốn đổi — chỉ gửi những gì người dùng thật sự sửa.
public struct SettingsPatch: Sendable {
    public var cloudLlm: Bool?
    public var llmModel: String??  // Optional-of-Optional: nil = không đổi; .some(nil) = đặt về trống.
    public var llmTimeoutMs: Int?
    public var actionsEnabled: Bool?

    public init(cloudLlm: Bool? = nil, llmModel: String?? = nil, llmTimeoutMs: Int? = nil, actionsEnabled: Bool? = nil) {
        self.cloudLlm = cloudLlm
        self.llmModel = llmModel
        self.llmTimeoutMs = llmTimeoutMs
        self.actionsEnabled = actionsEnabled
    }

    public var jsonObject: [String: Any] {
        var obj: [String: Any] = [:]
        if let v = cloudLlm { obj["cloud_llm"] = v }
        if let v = llmModel { obj["llm_model"] = v ?? NSNull() }
        if let v = llmTimeoutMs { obj["llm_timeout_ms"] = v }
        if let v = actionsEnabled { obj["actions_enabled"] = v }
        return obj
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
