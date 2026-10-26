import Foundation
import Testing
@testable import VFlowCore

private func json(_ s: String) -> Data { Data(s.utf8) }
private func err(_ code: String, _ msg: String) -> Data { json(#"{"error":{"code":"\#(code)","message":"\#(msg)"}}"#) }

@Suite struct ErrorMappingTests {
    @Test func unauthorizedBadToken() {
        guard case .failure(let e) = EngineAPI.parseTranscribe(status: 401, data: err("unauthorized", "Thiếu hoặc sai token.")) else {
            Issue.record("401 phải là lỗi"); return
        }
        #expect(e == .engine(status: 401, code: "unauthorized", message: "Thiếu hoặc sai token."))
        #expect(ErrorText.message(e).contains("token"))
        #expect(ErrorText.message(.engine(status: 403, code: "unauthorized", message: "Host")).contains("Host"))
    }

    @Test func modelUnavailableKeepsReason() {
        let e = ClientError.engine(status: 503, code: "model_unavailable", message: "Model chưa tải (lý do: tunnel_down)")
        #expect(ErrorText.message(e) == "Model chưa sẵn sàng (tunnel_down)")
        // Không có lý do dạng chuẩn: vẫn hiện nguyên thông điệp, không nuốt.
        let raw = ClientError.engine(status: 503, code: "model_unavailable", message: "thiếu tệp encoder.onnx")
        #expect(ErrorText.message(raw).contains("thiếu tệp encoder.onnx"))
    }

    @Test(arguments: [("bad_audio", "Âm thanh không hợp lệ"), ("timeout", "quá thời gian"),
                      ("payload_too_large", "120 giây"), ("internal", "nội bộ")])
    func knownCodes(code: String, fragment: String) {
        #expect(ErrorText.message(.engine(status: 400, code: code, message: "x")).contains(fragment))
    }

    @Test func unknownCodeIsShownNotSwallowed() {
        let m = ErrorText.message(.engine(status: 418, code: "teapot", message: "ấm trà"))
        #expect(m.contains("teapot") && m.contains("ấm trà"))
    }

    @Test func clientSideErrorsHaveVietnameseText() {
        #expect(ErrorText.message(.engineNotRunning) == "Engine không chạy")
        #expect(ErrorText.message(.micDenied).contains("Micro"))
        #expect(ErrorText.message(.accessibilityDenied).contains("Accessibility"))
        #expect(ErrorText.message(.tokenMissing(path: "/x/token")).contains("/x/token"))
    }

    @Test func nonContractBodyIsBadResponseWithStatus() {
        guard case .failure(let e) = EngineAPI.parseTranscribe(status: 502, data: json("<html>Bad gateway</html>")) else {
            Issue.record("phải lỗi"); return
        }
        guard case .badResponse(502, let d) = e else { Issue.record("sai loại: \(e)"); return }
        #expect(d.contains("Bad gateway"))
        #expect(ErrorText.message(e).contains("502"))
    }

    @Test func okWithoutTextIsNotSuccess() {
        guard case .failure(.badResponse) = EngineAPI.parseTranscribe(status: 200, data: json(#"{"id":"x"}"#)) else {
            Issue.record("thiếu text phải là lỗi"); return
        }
        guard case .failure(.badResponse) = EngineAPI.parseTranscribe(status: 200, data: json("not json")) else {
            Issue.record("không phải JSON phải là lỗi"); return
        }
    }
}

@Suite struct TranscribeParsingTests {
    @Test func successFields() throws {
        let body = json(#"""
        {"id":"tr_1","model":"zipformer-vi-30m","mode":"clean","language":"vi","text_raw":"ừm xin chào","text":"xin chào",
         "audio_ms":1200,"timings_ms":{"stt":100,"post":2,"total":103},"rtf":0.08,
         "post":{"applied":[],"rewrite":{"used":false,"error":null}}}
        """#)
        let r = try EngineAPI.parseTranscribe(status: 200, data: body).get()
        #expect(r == TranscribeResult(text: "xin chào", silence: false, mode: "clean", model: "zipformer-vi-30m",
                                      rewriteError: nil, totalMs: 103, textRaw: "ừm xin chào", audioMs: 1200))
    }

    @Test func silenceMeansNothingInserted() throws {
        let r = try EngineAPI.parseTranscribe(status: 200, data: json(#"{"text":"","silence":true,"mode":"normal","model":"m"}"#)).get()
        #expect(r.silence)
        let plan = DictationDecision.plan(for: .success(r))
        #expect(plan.insert == nil)
        #expect(plan.overlay == .notice("Không nghe thấy gì"))
    }

    @Test func whitespaceOnlyTextIsNotInserted() {
        let r = TranscribeResult(text: "  \n", silence: false, mode: "normal", model: "m", rewriteError: nil, totalMs: nil)
        #expect(DictationDecision.plan(for: .success(r)).insert == nil)
    }

    @Test func rewriteFailureStillPastesButReportsError() throws {
        let body = json(#"{"text":"gửi anh bản deploy","mode":"email","model":"m","post":{"rewrite":{"used":false,"error":"timeout"}}}"#)
        let r = try EngineAPI.parseTranscribe(status: 200, data: body).get()
        #expect(r.rewriteError == "timeout")
        let plan = DictationDecision.plan(for: .success(r))
        #expect(plan.insert == "gửi anh bản deploy")
        guard case .error(let m) = plan.overlay else { Issue.record("phải báo lỗi viết lại"); return }
        #expect(m.contains("timeout"))
    }

    @Test func failureKeepsRetryAudio() {
        let plan = DictationDecision.plan(for: .failure(.engineNotRunning))
        #expect(plan.insert == nil && !plan.clearRetry)
        #expect(plan.overlay == .error("Engine không chạy"))
        #expect(DictationDecision.plan(for: .success(.init(text: "a", silence: false, mode: "", model: "", rewriteError: nil, totalMs: nil))).clearRetry)
    }

    @Test func pasteFailureIsReported() {
        guard case .error(let m) = DictationDecision.overlay(after: .pasteFailedTextLeftOnClipboard, planned: .done) else {
            Issue.record("phải lỗi"); return
        }
        #expect(m.contains("clipboard"))
        #expect(DictationDecision.overlay(after: .pastedRestored, planned: .done) == .done)
    }

    @Test func noFocusedInputShowsCopiedNotice() {
        #expect(DictationDecision.overlay(after: .noFocusedInputTextKeptOnClipboard, planned: .done) == .notice("Đã chép — bấm ⌘V"))
    }
}

@Suite struct RequestTests {
    @Test func transcribeRequestMatchesContract() throws {
        let pcm = Data([1, 0, 2, 0])
        let r = EngineAPI.transcribeRequest(port: 7611, token: "abc", pcm: pcm, mode: .auto, app: "com.apple.Terminal")
        let url = try #require(r.url)
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.scheme == "http" && c.host == "127.0.0.1" && c.port == 7611 && c.path == "/v1/transcribe")
        #expect(c.queryItems == [URLQueryItem(name: "mode", value: "auto"), URLQueryItem(name: "app", value: "com.apple.Terminal")])
        #expect(!(c.queryItems ?? []).contains { $0.name == "model" }, "client không ép model")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "audio/L16; rate=16000; channels=1")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(r.httpBody == pcm)
    }

    @Test func noAppMeansNoAppQuery() throws {
        let r = EngineAPI.transcribeRequest(port: 1, token: "t", pcm: Data(), mode: .email, app: nil)
        #expect(r.url?.query == "mode=email")
        #expect(EngineAPI.healthRequest(port: 7611).url?.absoluteString == "http://127.0.0.1:7611/healthz")
    }

    @Test func tokenParsing() {
        let t = String(repeating: "a1", count: 32)
        #expect(EngineAPI.parseToken(t + "\n") == t)
        #expect(EngineAPI.parseToken("") == nil)
        #expect(EngineAPI.parseToken(String(repeating: "A1", count: 32)) == nil)
        #expect(EngineAPI.parseToken(String(t.dropLast())) == nil)
    }
}

@Suite struct HealthTests {
    @Test func modelsWithReasons() throws {
        let body = json(#"""
        {"ok":true,"version":"0.1.0","models":[{"id":"zipformer-vi-30m","kind":"local","loaded":true},
        {"id":"phowhisper-large","kind":"remote","loaded":false,"reason":"tunnel_down"}]}
        """#)
        let h = try #require(EngineAPI.parseHealth(status: 200, data: body))
        #expect(h.version == "0.1.0" && h.models.count == 2)
        #expect(EngineAPI.menuLine(h.models[0]) == "zipformer-vi-30m (local): sẵn sàng")
        #expect(EngineAPI.menuLine(h.models[1]).contains("tunnel_down"))
        #expect(EngineAPI.menuLine(ModelStatus(id: "x", kind: "local", loaded: false, reason: nil)).contains("không rõ lý do"))
    }

    @Test func foreignServerIsNotAnEngine() {
        #expect(EngineAPI.parseHealth(status: 200, data: json(#"{"status":"ok"}"#)) == nil)
        #expect(EngineAPI.parseHealth(status: 200, data: json(#"{"ok":false,"version":"0.1.0","models":[]}"#)) == nil)
        #expect(EngineAPI.parseHealth(status: 404, data: json("")) == nil)
    }
}

@Suite struct DictionaryRequestTests {
    @Test func getRequestMatchesContract() throws {
        let r = EngineAPI.dictionaryGetRequest(port: 7611, token: "abc")
        #expect(r.url?.absoluteString == "http://127.0.0.1:7611/v1/dictionary")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func putRequestEncodesEntriesMatchingEngineSchema() throws {
        let e = DictionaryEntry(term: "deploy", spoken: ["đi plôi", "đì ploi"], kind: "term", caseExact: true, uses: 3, lastUsed: "2026-10-26T01:00:00Z")
        let r = EngineAPI.dictionaryPutRequest(port: 7611, token: "abc", entries: [e])
        #expect(r.httpMethod == "PUT")
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let entries = try #require(obj["entries"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["term"] as? String == "deploy")
        #expect(entries[0]["spoken"] as? [String] == ["đi plôi", "đì ploi"])
        #expect(entries[0]["case"] as? String == "exact")
        #expect(entries[0]["uses"] as? Int == 3)
    }

    @Test func putRequestOmitsCaseKeyWhenNotExact() throws {
        let r = EngineAPI.dictionaryPutRequest(port: 7611, token: "abc", entries: [DictionaryEntry(term: "deploy", spoken: ["x"])])
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let entries = try #require(obj["entries"] as? [[String: Any]])
        #expect(entries[0]["case"] == nil)
    }

    @Test func listParsingRoundTrips() throws {
        let body = json(#"{"entries":[{"term":"deploy","spoken":["đi plôi"],"kind":"term","uses":12,"last_used":"2026-10-26T01:00:00Z"}]}"#)
        let entries = try EngineAPI.parseDictionaryList(status: 200, data: body).get()
        #expect(entries == [DictionaryEntry(term: "deploy", spoken: ["đi plôi"], kind: "term", caseExact: false, uses: 12, lastUsed: "2026-10-26T01:00:00Z")])
    }

    @Test func listParsingSurfacesEngineErrorNotSwallowed() {
        guard case .failure(.engine(400, "bad_request", let msg)) = EngineAPI.parseDictionaryList(status: 400, data: err("bad_request", "entries phải là một mảng")) else {
            Issue.record("phải forward lỗi bad_request"); return
        }
        #expect(msg.contains("mảng"))
    }

    @Test func correctionsRequestAndEmptySuggestionsParse() throws {
        let r = EngineAPI.correctionsRequest(port: 7611, token: "abc", before: "đi plôi", after: "deploy")
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["before"] as? String == "đi plôi")
        #expect(obj["after"] as? String == "deploy")
        let empty = try EngineAPI.parseCorrections(status: 200, data: json(#"{"suggestions":[]}"#)).get()
        #expect(empty.isEmpty, "không có gợi ý ⇒ mảng rỗng, không phải lỗi")
        let some = try EngineAPI.parseCorrections(status: 200, data: json(#"{"suggestions":[{"term":"deploy","spoken":["đi plôi"]}]}"#)).get()
        #expect(some == [CorrectionSuggestion(term: "deploy", spoken: ["đi plôi"])])
    }
}

@Suite struct DictationModeTests {
    /// Danh sách theo hợp đồng (contract/engine-api.md mục Chế độ): chỉ `tidy`/`email` gửi CHỮ qua 9Router;
    /// `auto` mặc định không bao giờ gọi LLM (bất biến 10).
    static let contractSendsTextToCloud: Set<DictationMode> = [.tidy, .email]

    @Test func sendsTextToCloudMatchesContractList() {
        for m in DictationMode.allCases {
            #expect(m.sendsTextToCloud == Self.contractSendsTextToCloud.contains(m), "\(m): sendsTextToCloud lệch với hợp đồng")
        }
    }

    /// Một nguồn duy nhất: mô tả hiển thị ở Tổng quan/Cài đặt/menu đều đọc từ `subtitle`/`sendsTextToCloud`
    /// của `DictationMode` này, nên chỉ cần kiểm chuỗi "gửi chữ" trong `subtitle` khớp đúng cờ gọi LLM.
    @Test func subtitleMentionsSendingTextOnlyWhenModeCallsLLM() {
        for m in DictationMode.allCases {
            let mentionsSendingText = m.subtitle.lowercased().contains("gửi chữ")
            #expect(mentionsSendingText == m.sendsTextToCloud, "\(m): mô tả \"\(m.subtitle)\" không khớp sendsTextToCloud=\(m.sendsTextToCloud)")
        }
    }

    @Test func autoDescribesLocalOnlyRoutingNotPrivacyLie() {
        let s = DictationMode.auto.subtitle
        #expect(!DictationMode.auto.sendsTextToCloud)
        #expect(s.contains("terminal") || s.lowercased().contains("terminal"))
        #expect(s.contains("Làm sạch"))
        #expect(s.contains("Thường"))
        #expect(s.contains("thủ công"))
    }
}

@Suite struct OverlayTextTests {
    @Test func fourStatesHaveSymbolsAndVietnamese() {
        #expect(OverlayText.present(.listening(level: 0)).text == "Đang nghe")
        #expect(OverlayText.present(.listening(level: 0)).showsLevel)
        #expect(OverlayText.present(.transcribing).text == "Đang dịch")
        #expect(OverlayText.present(.done).text == "Xong")
        let e = OverlayText.present(.error(String(repeating: "x", count: 200)))
        #expect(e.text.hasPrefix("Lỗi: ") && e.text.count <= 5 + OverlayText.maxErrorChars)
        #expect(e.accessibilityLabel.count > 200, "VoiceOver đọc đủ thông điệp")
        for s in [OverlayState.listening(level: 0), .transcribing, .done, .error("x")] {
            #expect(!OverlayText.present(s).symbol.isEmpty)
        }
    }

    /// HUD (U2 mục D): CHỈ "đang dịch" hiện vòng xoay; mọi trạng thái khác hiện biểu tượng SF
    /// Symbol tĩnh (hai thứ không bao giờ cùng hiện).
    @Test func onlyTranscribingShowsSpinner() {
        let states: [OverlayState] = [.listening(level: 0), .listeningLocked(level: 0), .listeningCommand(level: 0),
                                      .transcribing, .done, .notice("x"), .error("x")]
        for s in states {
            let p = OverlayText.present(s)
            #expect(p.showsSpinner == (s == .transcribing), "trạng thái \(s) có showsSpinner sai")
        }
    }

    /// Sóng âm CHỈ hiện ở ba trạng thái đang nghe (giữ phím, đã khoá, lệnh) — không hiện khi đang
    /// dịch/xong/thông báo/lỗi (những lúc đó không còn mức âm thật để hiện).
    @Test func levelMeterOnlyShowsWhileListening() {
        let listening: [OverlayState] = [.listening(level: 0), .listeningLocked(level: 0), .listeningCommand(level: 0)]
        let notListening: [OverlayState] = [.transcribing, .done, .notice("x"), .error("x")]
        for s in listening { #expect(OverlayText.present(s).showsLevel, "\(s) phải hiện sóng âm") }
        for s in notListening { #expect(!OverlayText.present(s).showsLevel, "\(s) không được hiện sóng âm") }
    }

    /// "Đã khoá" (hands-free) phải nhắc rõ cách thoát bằng chữ (bấm ⌥ để xong, Esc để huỷ) — không
    /// chỉ dựa vào hình, vì bấm ⌥ lần nữa khi KHÔNG khoá sẽ huỷ ghi, hành vi khác hẳn.
    @Test func lockedStateTellsHowToFinishOrCancelInWords() {
        let p = OverlayText.present(.listeningLocked(level: 0))
        #expect(p.text.contains("⌥"))
        #expect(p.text.lowercased().contains("esc"))
    }
}
