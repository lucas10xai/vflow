import Foundation
import Testing
@testable import VFlowCore

/// Engine có thể (và hiện còn) trả khoá mà client không biết — vd. `vocab_boost` đã gỡ khỏi client
/// nhưng engine còn giữ. Client không được lỗi, không đổi giá trị các khoá khác, và không bao giờ gửi
/// lại khoá lạ khi `PUT /v1/settings`.
@Suite struct SettingsUnknownKeyTests {
    private let base: [String: Any] = [
        "cloud_llm": true, "llm_timeout_ms": 3500, "actions_enabled": true,
        "voice_punctuation": false, "tone": "formal", "audio_history": true, "audio_history_mb": 300,
    ]

    private func decode(_ extra: [String: Any]) -> Result<AppSettings, ClientError> {
        let data = try! JSONSerialization.data(withJSONObject: base.merging(extra) { $1 })
        return EngineAPI.parseSettings(status: 200, data: data)
    }

    @Test func unknownKeysAreIgnoredAndKnownOnesStillDecode() throws {
        let withUnknown = try decode(["vocab_boost": true, "khoa_la_hoan_toan": ["a": 1], "another": NSNull()]).get()
        let without = try decode([:]).get()
        #expect(withUnknown == without, "khoá lạ không được đổi bất kỳ giá trị nào")
        #expect(withUnknown.voicePunctuation == false)
        #expect(withUnknown.tone == .formal)
        #expect(withUnknown.audioHistory && withUnknown.audioHistoryMb == 300)
    }

    @Test func unknownKeyOfAnyTypeDoesNotBreakDecoding() {
        for v: Any in [true, 0, "yes", [1, 2], ["x": "y"], NSNull()] {
            if case .failure(let e) = decode(["vocab_boost": v]) { Issue.record("khoá lạ kiểu \(type(of: v)) làm hỏng giải mã: \(e)") }
        }
    }

    @Test func requiredKeysStillRequired() {
        let data = try! JSONSerialization.data(withJSONObject: ["vocab_boost": true, "tone": "formal"])
        guard case .failure(.badResponse) = EngineAPI.parseSettings(status: 200, data: data) else {
            Issue.record("thiếu khoá bắt buộc vẫn phải là lỗi"); return
        }
    }

    /// Một bản vá điền ĐỦ mọi trường chỉ được sinh ra các khoá engine hiểu — không có `vocab_boost`.
    @Test func fullyPopulatedPatchSendsOnlyKnownKeys() {
        let patch = SettingsPatch(cloudLlm: false, llmModel: .some("m"), llmTimeoutMs: 5000, actionsEnabled: false,
                                  silenceStopSeconds: 3, statsEnabled: false, appRules: [], voicePunctuation: false,
                                  tone: .casual, whisperMode: true, learnFromEdits: false, livePreview: false,
                                  contextSymbols: false, audioHistory: true, audioHistoryMb: 100, audioHistoryDays: 3)
        let keys = Set(patch.jsonObject.keys)
        #expect(keys == ["cloud_llm", "llm_model", "llm_timeout_ms", "actions_enabled", "silence_stop_seconds", "stats_enabled",
                         "app_rules", "voice_punctuation", "tone", "whisper_mode", "learn_from_edits", "live_preview",
                         "context_symbols", "audio_history", "audio_history_mb", "audio_history_days"])
        #expect(!keys.contains("vocab_boost"))
    }
}
