import Foundation
import Testing
@testable import VFlowCore

/// V5: test còn thiếu cho tính năng Dịch (V4) — mỗi nhóm có bằng chứng đỏ khi phá nhánh tương ứng
/// (xem báo cáo). KHÔNG test lại những gì `DesignSystemTests`/`EngineAPITests` đã phủ (nhãn
/// riêng tư theo contract cho MỌI chế độ — đã có `modeCloudLabelMatchesContractForEachMode`/
/// `sendsTextToCloudMatchesContractList`).
@Suite struct TranslateFeatureTests {
    // MARK: (b) cloud_llm tắt ⇒ Dịch vô hiệu hoá kèm lý do, không im lặng

    @Test func translateDisabledWithReasonWhenCloudOff() {
        let reason = ModeAvailability.disabledReason(.translate, cloudLlm: false)
        #expect(reason != nil, "Dịch phải bị vô hiệu hoá kèm lý do khi cloud_llm tắt")
        #expect(reason?.isEmpty == false, "lý do không được rỗng (không vô hiệu hoá im lặng)")
        #expect(ModeAvailability.isDisabled(.translate, cloudLlm: false))
    }

    @Test func translateEnabledWhenCloudOn() {
        #expect(ModeAvailability.disabledReason(.translate, cloudLlm: true) == nil)
        #expect(!ModeAvailability.isDisabled(.translate, cloudLlm: true))
    }

    /// Bất biến: CHỈ Dịch bị cloud_llm chặn ở UI (tidy/email vẫn chọn được, chỉ rơi về bản cục bộ —
    /// xem contract mục Chế độ) — phá nhánh: nếu ai lỡ đổi `ModeAvailability` để chặn luôn email,
    /// test này đỏ.
    @Test func onlyTranslateIsGatedByCloudLlmAmongAllModes() {
        for m in DictationMode.allCases where m != .translate {
            #expect(!ModeAvailability.isDisabled(m, cloudLlm: false), "\(m) không được bị cloud_llm chặn ở UI")
        }
    }

    // MARK: (c) giải mã languages/auto_detect ở /healthz — thiếu/null/rỗng/lạ ⇒ không crash, suy ra đúng "chỉ tiếng Việt"

    private func healthJSON(models: String) -> Data {
        Data(#"{"ok":true,"version":"0.1.0","models":[\#(models)]}"#.utf8)
    }

    @Test func healthWithNoLoadedModelHasUnknownLanguages() {
        // Model cũ KHÔNG báo languages/auto_detect — đã biết trạng thái loaded:true nhưng nếu
        // KHÔNG model nào loaded thì Health.languages/autoDetect phải là nil (không đoán).
        let data = healthJSON(models: #"{"id":"m1","kind":"local","loaded":false,"reason":"not_downloaded"}"#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == nil)
        #expect(h.autoDetect == nil)
        #expect(h.models.first?.languages == nil)
    }

    @Test func healthPicksLanguagesFromTheLoadedModelNotTopLevel() {
        // Bằng chứng đỏ: trước khi sửa, parseHealth đọc obj["languages"] Ở GỐC JSON — engine THẬT
        // (đã kiểm bằng /healthz thật qua engine tạm cổng 27650) không BAO GIỜ gửi trường đó ở gốc,
        // CHỈ gửi "từng model" (contract) — nên trường gốc luôn vắng và languages luôn ra nil dù
        // model đã tải xong và engine có báo đúng. Test này tái hiện hình dạng JSON THẬT đó.
        let data = healthJSON(models: #"{"id":"whisper-tiny-multilingual","kind":"local","loaded":true,"languages":["vi","en","ja"],"auto_detect":true}"#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == ["vi", "en", "ja"])
        #expect(h.autoDetect == true)
    }

    @Test func healthIgnoresUnloadedModelsWhenPickingLanguages() {
        // Hai model: một chưa tải (đa ngôn ngữ) một đã tải (chỉ vi) — phải lấy theo model THẬT SỰ
        // dùng được, không lấy bừa model đầu tiên trong danh sách.
        let data = healthJSON(models: #"""
            {"id":"whisper-tiny-multilingual","kind":"local","loaded":false,"reason":"not_downloaded","languages":["vi","en","ja"],"auto_detect":true},
            {"id":"zipformer-vi-30m","kind":"local","loaded":true,"languages":["vi"],"auto_detect":false}
            """#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == ["vi"])
        #expect(h.autoDetect == false)
    }

    @Test func healthToleratesNullAndMissingLanguageFields() {
        let data = healthJSON(models: #"{"id":"m1","kind":"local","loaded":true,"languages":null,"auto_detect":null}"#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == nil)
        #expect(h.autoDetect == nil)
    }

    @Test func healthToleratesEmptyLanguagesArray() {
        let data = healthJSON(models: #"{"id":"m1","kind":"local","loaded":true,"languages":[],"auto_detect":false}"#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == [])
        #expect(h.autoDetect == false)
        // Mảng rỗng (không "vi" trong đó) ⇒ languageEnabled(.vietnamese) phải vẫn coi vi hợp lệ?
        // KHÔNG: engine đã trả lời chắc chắn ("đây là toàn bộ") nên rỗng nghĩa là model lạ không
        // nói tiếng Việt — khác với "không xác định" (nil). Kiểm ở SpeechLanguageAvailabilityTests.
    }

    @Test func healthToleratesWeirdLanguageValuesWithoutCrashing() {
        // "languages" là số/chuỗi thay vì mảng chuỗi — không crash, coi như không có field đó.
        let data = healthJSON(models: #"{"id":"m1","kind":"local","loaded":true,"languages":123,"auto_detect":"yes"}"#)
        let h = try! #require(EngineAPI.parseHealth(status: 200, data: data))
        #expect(h.languages == nil)
        #expect(h.autoDetect == nil)
    }

    @Test func healthStatusNotOkOrMissingFieldsReturnsNil() {
        #expect(EngineAPI.parseHealth(status: 500, data: healthJSON(models: "")) == nil)
        #expect(EngineAPI.parseHealth(status: 200, data: Data("not json".utf8)) == nil)
    }

    // MARK: (g) chọn ngôn ngữ nói khi model chỉ hỗ trợ vi ⇒ lựa chọn khác vô hiệu hoá kèm lý do

    @Test func onlyVietnameseEnabledWhenLanguagesUnknown() {
        #expect(SpeechLanguageAvailability.isEnabled(.vietnamese, supportedLanguages: nil, autoDetect: nil))
        #expect(!SpeechLanguageAvailability.isEnabled(.english, supportedLanguages: nil, autoDetect: nil))
        #expect(!SpeechLanguageAvailability.isEnabled(.automatic, supportedLanguages: nil, autoDetect: nil))
        #expect(SpeechLanguageAvailability.disabledReason(.english, supportedLanguages: nil, autoDetect: nil)?.isEmpty == false)
    }

    @Test func englishAndAutoEnabledWhenModelReportsThem() {
        #expect(SpeechLanguageAvailability.isEnabled(.english, supportedLanguages: ["vi", "en"], autoDetect: true))
        #expect(SpeechLanguageAvailability.isEnabled(.automatic, supportedLanguages: ["vi", "en"], autoDetect: true))
    }

    @Test func emptySupportedLanguagesDisablesEvenVietnamese() {
        // Engine TRẢ LỜI CHẮC CHẮN model này không nói tiếng gì trong danh sách rỗng — khác "không
        // xác định" (nil). Phá nhánh: nếu code coi rỗng giống nil, test này đỏ.
        #expect(!SpeechLanguageAvailability.isEnabled(.vietnamese, supportedLanguages: [], autoDetect: false))
    }

    @Test func autoDetectFalseDisablesAutomaticEvenWithManyLanguages() {
        #expect(!SpeechLanguageAvailability.isEnabled(.automatic, supportedLanguages: ["vi", "en", "ja"], autoDetect: false))
    }

    // MARK: (d) mã ISO ngôn ngữ đích — hợp lệ/sai/rỗng/chữ hoa, khớp engine (/^[a-z]{2,3}$/i)

    @Test func validISOCodesAccepted() {
        for code in ["en", "vi", "fr", "zh", "EN", "Ja", "th"] {
            #expect(TranslationValidation.isValidISOCode(code), "\(code) phải hợp lệ")
        }
    }

    @Test func invalidISOCodesRejected() {
        for code in ["", "e", "english", "en-US", "en_US", "1a", "ab c", "   "] {
            #expect(!TranslationValidation.isValidISOCode(code), "\(code) phải KHÔNG hợp lệ")
        }
    }

    /// Bằng chứng đỏ (đã có TRƯỚC khi sửa): phiên bản cũ của `isValidISOCode` nhận cả tiểu thẻ vùng
    /// kiểu BCP-47 (`en-US`) — nhưng `engine/post/settings.js` (`translate_target`) VÀ route
    /// `POST /v1/translate` (`target`) đều validate đúng `/^[a-z]{2,3}$/i`, không nhận tiểu thẻ.
    /// Ô "Khác…" dùng validate phía client để BẬT nút lưu — lỏng hơn engine ⇒ người dùng tưởng đã
    /// nhập hợp lệ nhưng `PUT /v1/settings` vẫn trả `400 bad_request`.
    @Test func rejectsRegionSubtagsThatEngineWouldReject() {
        #expect(!TranslationValidation.isValidISOCode("en-US"))
        #expect(!TranslationValidation.isValidISOCode("zh-Hans"))
    }

    // MARK: (e) degraded_reason "translate_guard" ⇒ đúng thông điệp tiếng Việt

    @Test func translateGuardHasOwnVietnameseMessage() {
        let msg = DegradedText.message("translate_guard")
        #expect(msg.contains("dịch"), "phải nói rõ liên quan tới dịch: \(msg)")
        // Không rơi vào nhánh default "(reason)" chung — phải là câu riêng, không lộ mã kỹ thuật.
        #expect(!msg.contains("translate_guard"))
    }

    @Test func dictationDecisionNeverInsertsTextWhenTranslateGuardBlocks() {
        let result = TranscribeResult(text: "", silence: false, mode: "translate", model: "m", rewriteError: nil,
                                      totalMs: 10, textRaw: "xin chào", audioMs: 100, actions: [],
                                      degraded: true, degradedReason: "translate_guard", audioId: nil)
        let plan = DictationDecision.plan(for: .success(result))
        #expect(plan.insert == nil, "guard chặn dịch ⇒ KHÔNG được chèn gì (không phải bản gốc, không phải rỗng)")
    }

    // MARK: EngineAPIv4.parseTranslate — thành công/guard/lỗi/kết quả rỗng

    @Test func parseTranslateSuccessReturnsText() {
        let data = Data(#"{"text":"Hello world","degraded":false,"degraded_reason":null}"#.utf8)
        let result = EngineAPIv4Result(EngineAPI.parseTranslate(status: 200, data: data))
        #expect(result.text == "Hello world")
    }

    @Test func parseTranslateRejectsEmptyTextAsFailureNotSuccess() {
        // "kết quả rỗng" (2f): engine không nên trả text rỗng ở 200, nhưng nếu có ⇒ KHÔNG coi là
        // thành công (không chèn chuỗi rỗng im lặng).
        for text in ["", "   ", "\n"] {
            let data = try! JSONSerialization.data(withJSONObject: ["text": text, "degraded": false, "degraded_reason": NSNull()])
            guard case .failure = EngineAPI.parseTranslate(status: 200, data: data) else {
                Issue.record("text rỗng (\(text.debugDescription)) ở 200 phải là .failure, không phải .success"); return
            }
        }
    }

    @Test func parseTranslateMissingTextFieldIsFailure() {
        let data = Data(#"{"degraded":false,"degraded_reason":null}"#.utf8)
        guard case .failure = EngineAPI.parseTranslate(status: 200, data: data) else {
            Issue.record("thiếu trường text phải là .failure"); return
        }
    }

    @Test func parseTranslateNon200StatusIsFailure() {
        let data = Data(#"{"error":{"code":"cloud_disabled","message":"Đám mây đang tắt"}}"#.utf8)
        guard case .failure(.engine(503, "cloud_disabled", let msg)) = EngineAPI.parseTranslate(status: 503, data: data) else {
            Issue.record("503 cloud_disabled phải map đúng ClientError.engine"); return
        }
        #expect(msg.contains("Đám mây"))
    }

    @Test func parseTranslateGuardShapeStillParsesAsSuccessIfStatus200() {
        // Lưu ý: server trả degraded_reason:"translate_guard" KÈM status 200 (xem contract) — client
        // KHÔNG tự coi 200 là "có text" nếu "text" là null; đây là hình dạng THẬT engine trả khi bị
        // guard chặn — phải là .failure vì "text" là null, không phải chuỗi rỗng.
        let data = Data(#"{"text":null,"degraded":true,"degraded_reason":"translate_guard"}"#.utf8)
        guard case .failure = EngineAPI.parseTranslate(status: 200, data: data) else {
            Issue.record("text:null (translate_guard) ở 200 phải là .failure — client không tự chèn gì"); return
        }
    }
}

/// Tiện ích nhỏ cho test: lấy `.text` từ `.success`, nổ rõ ràng nếu `.failure` (thay vì optional mơ hồ).
private func EngineAPIv4Result(_ r: Result<TranslationResult, ClientError>) -> TranslationResult {
    switch r {
    case .success(let v): return v
    case .failure(let e): fatalError("mong .success, ra .failure(\(e))")
    }
}
