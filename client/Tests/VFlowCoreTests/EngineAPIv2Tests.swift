import Foundation
import Testing
@testable import VFlowCore

private func json(_ s: String) -> Data { Data(s.utf8) }
private func err(_ code: String, _ msg: String) -> Data { json(#"{"error":{"code":"\#(code)","message":"\#(msg)"}}"#) }

/// Mẫu JSON LẤY NGUYÊN từ contract/engine-api.md (mục "Cài đặt người dùng") — nguồn duy nhất cho
/// `GET /v1/settings`, lồng trong `diagnostics.settings` và `export.settings`.
private let settingsSample = #"""
{ "cloud_llm": true, "llm_model": "ag/gemini-3.8-flash", "llm_timeout_ms": 3500, "actions_enabled": true,
  "stats_enabled": true, "app_rules": { "com.apple.Terminal": "dev" }, "voice_punctuation": true, "tone": "neutral",
  "whisper_mode": false, "learn_from_edits": true, "live_preview": true, "silence_stop_seconds": 0 }
"""#

@Suite struct SettingsV2RequestTests {
    @Test func parsesAllV2FieldsFromContractSample() throws {
        let s = try EngineAPI.parseSettings(status: 200, data: json(settingsSample)).get()
        #expect(s.cloudLlm && s.llmModel == "ag/gemini-3.8-flash" && s.llmTimeoutMs == 3500 && s.actionsEnabled)
        #expect(s.statsEnabled)
        #expect(s.appRules == [AppRule(bundleId: "com.apple.Terminal", mode: .dev)])
        #expect(s.voicePunctuation)
        #expect(s.tone == .neutral)
        #expect(!s.whisperMode)
        #expect(s.learnFromEdits)
        #expect(s.livePreview, "mặc định mới true, xem contract mục Cài đặt")
        #expect(s.silenceStopSeconds == 0)
    }

    @Test func missingV2KeysFallBackToCurrentDefaultsNotError() throws {
        // Engine cũ chưa có các khoá item 2–7 — client phải vẫn đọc được, dùng mặc định hiện hành.
        let old = #"{"cloud_llm":true,"llm_model":null,"llm_timeout_ms":8000,"actions_enabled":true}"#
        let s = try EngineAPI.parseSettings(status: 200, data: json(old)).get()
        #expect(s.statsEnabled && s.voicePunctuation && s.learnFromEdits && s.livePreview)
        #expect(!s.whisperMode)
        #expect(s.tone == .neutral)
        #expect(s.appRules.isEmpty)
        #expect(s.silenceStopSeconds == 0)
    }

    @Test func putRequestEncodesAppRulesAndTone() throws {
        let patch = SettingsPatch(statsEnabled: false,
                                  appRules: [AppRule(bundleId: "com.apple.Terminal", mode: .dev), AppRule(bundleId: "com.slack.app", mode: .tidy)],
                                  voicePunctuation: false, tone: .formal, whisperMode: true, learnFromEdits: false, livePreview: false)
        let r = EngineAPI.settingsPutRequest(port: 7611, token: "t", patch: patch)
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["stats_enabled"] as? Bool == false)
        let rules = try #require(obj["app_rules"] as? [String: String])
        #expect(rules["com.apple.Terminal"] == "dev" && rules["com.slack.app"] == "tidy")
        #expect(obj["tone"] as? String == "formal")
        #expect(obj["whisper_mode"] as? Bool == true)
        #expect(obj["learn_from_edits"] as? Bool == false)
        #expect(obj["live_preview"] as? Bool == false)
    }
}

@Suite struct AppRuleValidationTests {
    @Test func rejectsBadBundleIds() {
        for bad in ["", "nope", "com..bad", ".com.bad", "1com.bad", "com.bad.", "com.bad!x"] {
            #expect(AppRuleValidation.error(bundleId: bad, currentCount: 0) != nil, "phải chặn: \(bad)")
        }
    }

    @Test func acceptsGoodBundleIds() {
        for good in ["com.apple.Terminal", "com.todesktop.230313mzl4w4u92", "org.aios.vflow"] {
            #expect(AppRuleValidation.error(bundleId: good, currentCount: 0) == nil, "phải cho qua: \(good)")
        }
    }

    @Test func blocksOver100Rules() {
        #expect(AppRuleValidation.error(bundleId: "com.apple.Terminal", currentCount: 100) != nil)
        #expect(AppRuleValidation.error(bundleId: "com.apple.Terminal", currentCount: 99) == nil)
        // Sửa luật ĐÃ CÓ (không phải thêm mới) không bị chặn bởi trần, dù đang ở 100.
        #expect(AppRuleValidation.error(bundleId: "com.apple.Terminal", currentCount: 100, excludingBundleId: "com.apple.Terminal") == nil)
    }
}

@Suite struct StatsRequestTests {
    private let statsSample = #"""
    { "enabled": true, "since": "2026-09-01", "weeks": 16, "week_start": "monday", "today": "2026-10-27",
      "total_words": 12345, "total_count": 321, "total_audio_ms": 9876543, "avg_wpm": 95,
      "current_streak": 4, "best_streak": 12,
      "days": [ { "date": "2026-09-08", "words": 0, "count": 0, "audio_ms": 0 } ],
      "top_apps": [ { "app": "com.apple.Terminal", "words": 5000, "count": 120 } ] }
    """#

    @Test func requestMatchesContract() throws {
        let r = EngineAPI.statsRequest(port: 7611, token: "t", weeks: 16)
        #expect(r.url?.absoluteString == "http://127.0.0.1:7611/v1/stats?weeks=16")
        #expect(r.httpMethod == "GET")
        let d = EngineAPI.statsDeleteRequest(port: 7611, token: "t")
        #expect(d.httpMethod == "DELETE")
    }

    @Test func parsesContractSample() throws {
        let s = try EngineAPI.parseStats(status: 200, data: json(statsSample)).get()
        #expect(s.enabled && s.since == "2026-09-01" && s.weeks == 16 && s.weekStart == "monday" && s.today == "2026-10-27")
        #expect(s.totalWords == 12345 && s.totalCount == 321 && s.totalAudioMs == 9876543)
        #expect(s.avgWpm == 95)
        #expect(s.currentStreak == 4 && s.bestStreak == 12)
        #expect(s.days == [DayStat(date: "2026-09-08", words: 0, count: 0, audioMs: 0)])
        #expect(s.topApps == [AppWordStat(app: "com.apple.Terminal", words: 5000, count: 120)])
    }

    /// Bất biến: `avg_wpm:null` (< 60s audio) PHẢI ra `nil`, KHÔNG BAO GIỜ `0` giả.
    @Test func nullAvgWpmIsNilNotZero() throws {
        let body = #"{"enabled":true,"since":null,"weeks":16,"week_start":"monday","today":"2026-10-27","total_words":0,"total_count":0,"total_audio_ms":0,"avg_wpm":null,"current_streak":0,"best_streak":0,"days":[],"top_apps":[]}"#
        let s = try EngineAPI.parseStats(status: 200, data: json(body)).get()
        #expect(s.avgWpm == nil)
        #expect(s.since == nil)
        #expect(AvgWpmText.text(s.avgWpm) == "—")
    }

    @Test func badRequestForInvalidWeeksIsForwarded() {
        guard case .failure(.engine(400, "bad_request", let msg)) = EngineAPI.parseStats(status: 400, data: err("bad_request", "weeks phải 1–104")) else {
            Issue.record("phải forward bad_request"); return
        }
        #expect(msg.contains("weeks"))
    }

    @Test func deleteOkParses() throws {
        try EngineAPI.parseOk(status: 200, data: json(#"{"ok":true}"#)).get()
    }
}

@Suite struct DictionarySuggestionsRequestTests {
    @Test func parsesContractSample() throws {
        let body = #"{ "suggestions": [ { "term": "Supabase", "variants": ["xu pa bết"], "count": 3, "last_seen": "2026-10-26T01:00:00.000Z" } ] }"#
        let s = try EngineAPI.parseDictionarySuggestions(status: 200, data: json(body)).get()
        #expect(s == [DictionarySuggestion(term: "Supabase", variants: ["xu pa bết"], count: 3, lastSeen: "2026-10-26T01:00:00.000Z")])
    }

    @Test func emptyIsNotError() throws {
        let s = try EngineAPI.parseDictionarySuggestions(status: 200, data: json(#"{"suggestions":[]}"#)).get()
        #expect(s.isEmpty)
    }

    @Test func dismissRequestEncodesTerm() throws {
        let r = EngineAPI.dictionarySuggestionDismissRequest(port: 7611, token: "t", term: "Supabase")
        #expect(r.httpMethod == "POST")
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["term"] as? String == "Supabase")
    }
}

@Suite struct ExportImportRequestTests {
    private let exportSample = #"""
    { "format": "vflow-export", "version": 1, "exported_at": "2026-10-27T00:00:00.000Z",
      "dictionary": [], "snippets": [], "settings": \#(settingsSample),
      "stats": { "backfilled": true, "days": {} } }
    """#

    @Test func exportRequestEncodesIncludeHistory() throws {
        let r0 = EngineAPI.exportRequest(port: 7611, token: "t", includeHistory: false)
        #expect(r0.url?.absoluteString.contains("include_history=0") == true)
        let r1 = EngineAPI.exportRequest(port: 7611, token: "t", includeHistory: true)
        #expect(r1.url?.absoluteString.contains("include_history=1") == true)
    }

    @Test func validatesContractSampleAsSavableBytes() throws {
        let data = try EngineAPI.validateExportResponse(status: 200, data: json(exportSample)).get()
        #expect(data == json(exportSample), "lưu NGUYÊN VẸN byte engine trả, không tái dựng JSON")
    }

    @Test func rejectsWrongFormatMarker() {
        guard case .failure(.badResponse) = EngineAPI.validateExportResponse(status: 200, data: json(#"{"format":"something-else","version":1}"#)) else {
            Issue.record("phải lỗi khi format sai"); return
        }
    }

    @Test func importRequestEncodesModeAndRawBody() throws {
        let payload = json(#"{"format":"vflow-export"}"#)
        let merge = EngineAPI.importRequest(port: 7611, token: "t", mode: .merge, data: payload)
        #expect(merge.url?.absoluteString.contains("mode=merge") == true)
        #expect(merge.httpBody == payload)
        let replace = EngineAPI.importRequest(port: 7611, token: "t", mode: .replace, data: payload)
        #expect(replace.url?.absoluteString.contains("mode=replace") == true)
    }

    @Test func parsesAppliedCountsFromContractSample() throws {
        let body = #"{"ok":true,"applied":{"dictionary":2,"snippets":1,"settings":3,"stats_days":9,"history":0}}"#
        let r = try EngineAPI.parseImportResult(status: 200, data: json(body)).get()
        #expect(r == ImportApplied(dictionary: 2, snippets: 1, settings: 3, statsDays: 9, history: 0, ignored: []))
    }

    @Test func parsesIgnoredTokenField() throws {
        let body = #"{"ok":true,"applied":{"dictionary":0,"snippets":0,"settings":0,"stats_days":0,"history":0},"ignored":["token"]}"#
        let r = try EngineAPI.parseImportResult(status: 200, data: json(body)).get()
        #expect(r.ignored == ["token"])
    }

    /// Bất biến 12: gói hỏng một phần ⇒ engine trả lỗi cả gói (không nhập nửa vời) — client chỉ cần
    /// forward lỗi `bad_request` đúng, không tự "sửa giúp".
    @Test func partiallyInvalidPackageIsRejectedAsWholeNotPartial() {
        guard case .failure(.engine(400, "bad_request", let msg)) = EngineAPI.parseImportResult(status: 400, data: err("bad_request", "dictionary: entries[2].term rỗng")) else {
            Issue.record("phải forward lỗi, không coi là nhập được một phần"); return
        }
        #expect(msg.contains("dictionary"))
    }
}

@Suite struct DiagnosticsRequestTests {
    private let diagnosticsSample = #"""
    { "engine_version": "0.1.0", "node": "v22.x", "platform": "darwin-arm64", "uptime_s": 120,
      "model": { "default": "zipformer-vi-30m", "status": [{"id":"zipformer-vi-30m","kind":"local","loaded":true}] },
      "stt": { "default": "zipformer-vi-30m" }, "settings": \#(settingsSample),
      "counts": { "dictionary": 12, "snippets": 3, "history": 40, "stats_days": 9 },
      "paths": { "home_basename": ".vflow" },
      "recent_errors": [ { "at": "2026-10-27T00:00:00.000Z", "route": "/v1/transcribe", "status": 503, "code": "model_unavailable" } ] }
    """#

    @Test func parsesContractSample() throws {
        let d = try EngineAPI.parseDiagnostics(status: 200, data: json(diagnosticsSample)).get()
        #expect(d.engineVersion == "0.1.0" && d.node == "v22.x" && d.platform == "darwin-arm64" && d.uptimeSeconds == 120)
        #expect(d.modelDefault == "zipformer-vi-30m")
        #expect(d.modelStatus == [ModelStatus(id: "zipformer-vi-30m", kind: "local", loaded: true, reason: nil)])
        #expect(d.sttDefault == "zipformer-vi-30m")
        #expect(d.settings.livePreview)
        #expect(d.countDictionary == 12 && d.countSnippets == 3 && d.countHistory == 40 && d.countStatsDays == 9)
        #expect(d.homeBasename == ".vflow")
        #expect(d.recentErrors == [RecentErrorEntry(at: "2026-10-27T00:00:00.000Z", route: "/v1/transcribe", status: 503, code: "model_unavailable")])
    }

    /// Bất biến 13 (chỉ phần client có thể tự kiểm): văn bản dùng cho "Sao chép chẩn đoán" không
    /// được chứa khoá/token kể cả khi mẫu vô tình có trường đó (engine không BAO GIỜ trả nó theo
    /// hợp đồng, nhưng client không thêm field nào — `prettyText` chỉ là JSON engine đã trả).
    @Test func prettyTextRoundTripsWithoutAddingFields() throws {
        let d = try EngineAPI.parseDiagnostics(status: 200, data: json(diagnosticsSample)).get()
        #expect(!d.prettyText.isEmpty)
        #expect(!d.prettyText.lowercased().contains("rewrite.key"))
    }

    @Test func requestMatchesContract() {
        let r = EngineAPI.diagnosticsRequest(port: 7611, token: "t")
        #expect(r.url?.absoluteString == "http://127.0.0.1:7611/v1/diagnostics")
        #expect(r.httpMethod == "GET")
    }
}

@Suite struct PartialRequestTests {
    @Test func requestMatchesContract() throws {
        let pcm = Data([1, 2, 3, 4])
        let r = EngineAPI.partialRequest(port: 7611, token: "t", pcm: pcm)
        #expect(r.url?.absoluteString == "http://127.0.0.1:7611/v1/partial")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "audio/L16; rate=16000; channels=1")
        #expect(r.httpBody == pcm)
    }

    @Test func parsesContractSample() throws {
        let body = #"{ "text": "xin chào", "audio_ms": 1500, "stt_ms": 120 }"#
        let p = try EngineAPI.parsePartial(status: 200, data: json(body)).get()
        #expect(p == PartialResult(text: "xin chào", audioMs: 1500, sttMs: 120))
    }

    /// Bất biến 17: `/v1/partial` bận ⇒ 429 `busy` — client phải nhận ra để TỰ BỎ QUA, không hiện lỗi.
    @Test func busyIsRecognizedForSilentSkip() {
        let r = EngineAPI.parsePartial(status: 429, data: err("busy", "Đang bận"))
        guard case .failure(let e) = r else { Issue.record("429 phải là lỗi"); return }
        #expect(EngineAPI.isPartialBusy(e))
        #expect(!EngineAPI.isPartialBusy(.engine(status: 500, code: "internal", message: "x")))
    }
}

/// `post.degraded`/`post.degraded_reason` (contract mục "Chế độ", item 7) — bản dự phòng cục bộ
/// thay cho đám mây đã định; HUD phải báo ĐÚNG nguyên nhân bằng tiếng Việt (mục 6 của yêu cầu V2).
@Suite struct DegradedResultTests {
    @Test func parsesDegradedFlagAndReasonFromTranscribeResponse() throws {
        let body = #"{"text":"đã dùng bản làm sạch","mode":"clean","model":"m","post":{"degraded":true,"degraded_reason":"cloud_disabled","rewrite":{"used":false,"error":null}}}"#
        let r = try EngineAPI.parseTranscribe(status: 200, data: json(body)).get()
        #expect(r.degraded)
        #expect(r.degradedReason == "cloud_disabled")
    }

    @Test func notDegradedWhenAbsent() throws {
        let body = #"{"text":"x","mode":"normal","model":"m","post":{"applied":[],"rewrite":{"used":false,"error":null}}}"#
        let r = try EngineAPI.parseTranscribe(status: 200, data: json(body)).get()
        #expect(!r.degraded)
        #expect(r.degradedReason == nil)
    }

    @Test(arguments: [
        ("llm_timeout", "9Router chậm"),
        ("llm_error", "9Router lỗi"),
        ("guard", "chặn vì đổi nghĩa"),
        ("cloud_disabled", "Đám mây đang tắt"),
    ])
    func messageMatchesExactReason(code: String, fragment: String) {
        #expect(DegradedText.message(code).contains(fragment))
    }

    @Test func unknownReasonIsShownNotSwallowed() {
        #expect(DegradedText.message("something_new").contains("something_new"))
    }

    /// Kết quả vẫn ĐƯỢC CHÈN (chữ dự phòng dùng được) — chỉ khác thông điệp HUD, không phải lỗi.
    @Test func degradedResultStillInsertsTextWithNoticeOverlay() {
        let r = TranscribeResult(text: "bản làm sạch", silence: false, mode: "clean", model: "m", rewriteError: nil,
                                 totalMs: nil, degraded: true, degradedReason: "llm_timeout")
        let plan = DictationDecision.plan(for: .success(r))
        #expect(plan.insert == "bản làm sạch")
        #expect(plan.overlay == .notice(DegradedText.message("llm_timeout")))
        #expect(plan.clearRetry)
    }

    /// Không có `degraded_reason` dù `degraded:true` (không nên xảy ra theo hợp đồng, nhưng không
    /// được làm plan() crash/nuốt kết quả) ⇒ rơi về đường cũ (rewriteError hoặc .done).
    @Test func degradedTrueWithoutReasonFallsBackSafely() {
        let r = TranscribeResult(text: "x", silence: false, mode: "clean", model: "m", rewriteError: nil,
                                 totalMs: nil, degraded: true, degradedReason: nil)
        let plan = DictationDecision.plan(for: .success(r))
        #expect(plan.insert == "x")
        #expect(plan.overlay == .done)
    }
}
