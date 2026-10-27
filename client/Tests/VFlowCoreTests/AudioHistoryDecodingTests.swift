import Foundation
import Testing
@testable import VFlowCore

private func json(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

@Suite struct AudioListDecodingTests {
    private func body(items: [[String: Any]] = [["id": "tr_1", "bytes": 64044, "audio_ms": 2000, "at": "2026-10-27T01:00:00.000Z"]],
                      drop: String? = nil) -> Data {
        var o: [String: Any] = ["enabled": true, "count": items.count, "bytes": 64044, "budget_bytes": 209_715_200, "days": 7, "items": items]
        if let drop { o.removeValue(forKey: drop) }
        return json(o)
    }

    @Test func decodesFullSummary() throws {
        let s = try EngineAPI.parseAudioList(status: 200, data: body()).get()
        #expect(s.enabled)
        #expect(s.count == 1)
        #expect(s.bytes == 64044)
        #expect(s.budgetBytes == 209_715_200)
        #expect(s.days == 7)
        #expect(s.items == [AudioHistoryItem(id: "tr_1", bytes: 64044, audioMs: 2000, at: "2026-10-27T01:00:00.000Z")])
    }

    @Test func emptyItemsIsValidNotAnError() throws {
        let s = try EngineAPI.parseAudioList(status: 200, data: body(items: [])).get()
        #expect(s.count == 0)
        #expect(s.items.isEmpty)
    }

    /// Thiếu BẤT KỲ trường cấp trên nào ⇒ lỗi thật `badResponse`, không được suy ra 0/false/rỗng
    /// (sẽ hiện "Chưa có tệp âm thanh nào" trong khi thật ra không biết).
    @Test(arguments: ["enabled", "count", "bytes", "budget_bytes", "days", "items"])
    func missingTopLevelFieldIsBadResponse(field: String) {
        guard case .failure(.badResponse(let status, _)) = EngineAPI.parseAudioList(status: 200, data: body(drop: field)) else {
            Issue.record("thiếu \(field) phải là badResponse"); return
        }
        #expect(status == 200)
    }

    @Test func malformedItemIsErrorNotSilentlyDropped() {
        let items: [[String: Any]] = [
            ["id": "tr_1", "bytes": 10, "audio_ms": 1, "at": "x"],
            ["id": "tr_2", "bytes": 10, "audio_ms": 1], // thiếu `at`
        ]
        guard case .failure(.badResponse(_, let detail)) = EngineAPI.parseAudioList(status: 200, data: body(items: items)) else {
            Issue.record("mục hỏng phải thành lỗi"); return
        }
        #expect(detail.contains("2"), "phải nêu mục thứ mấy hỏng")
    }

    @Test func countMayExceedListedItemsBecauseEngineCapsTheList() throws {
        var o = try #require(JSONSerialization.jsonObject(with: body()) as? [String: Any])
        o["count"] = 900
        let s = try EngineAPI.parseAudioList(status: 200, data: json(o)).get()
        #expect(s.count == 900)
        #expect(s.items.count == 1)
    }

    @Test func nonJSONBodyIsBadResponse() {
        guard case .failure(.badResponse) = EngineAPI.parseAudioList(status: 200, data: Data("<html>".utf8)) else {
            Issue.record("không phải JSON phải lỗi"); return
        }
    }

    @Test func engineErrorIsPassedThroughWithItsCode() {
        let err = json(["error": ["code": "unauthorized", "message": "sai token"]])
        guard case .failure(.engine(401, "unauthorized", _)) = EngineAPI.parseAudioList(status: 401, data: err) else {
            Issue.record("phải giữ mã lỗi engine"); return
        }
    }

    @Test func deleteAllRequiresOkAndDeletedFields() throws {
        #expect(try EngineAPI.parseAudioDeleteAll(status: 200, data: json(["ok": true, "deleted": 3])).get() == 3)
        guard case .failure(.badResponse) = EngineAPI.parseAudioDeleteAll(status: 200, data: json(["ok": true])) else {
            Issue.record("thiếu deleted phải lỗi"); return
        }
        guard case .failure(.badResponse) = EngineAPI.parseAudioDeleteAll(status: 200, data: json(["ok": false, "deleted": 0])) else {
            Issue.record("ok=false phải lỗi"); return
        }
    }
}

@Suite struct AudioItemURLTests {
    @Test func validIdIsUsedAsIs() {
        let url = EngineAPI.audioItemURL(port: 27711, id: "tr_01H-abc_9")
        #expect(url.absoluteString == "http://127.0.0.1:27711/v1/audio/tr_01H-abc_9")
    }

    /// `audio_id` đọc từ history.jsonl trên đĩa; "." chuẩn hoá thành `/v1/audio/` và DELETE sẽ xoá
    /// TOÀN BỘ âm thanh. Mọi id sai định dạng phải bị thay bằng id mồi (engine trả 404).
    @Test(arguments: [".", "..", "../settings", "a/b", "", "id có dấu cách", "%2e%2e", "tr_1?x=1", "tr_1#f"])
    func invalidIdNeverReachesThePath(id: String) {
        for req in [EngineAPI.audioDeleteOneRequest(port: 27711, token: "t", id: id),
                    EngineAPI.audioGetRequest(port: 27711, token: "t", id: id)] {
            let url = req.url!
            #expect(url.absoluteString == "http://127.0.0.1:27711/v1/audio/invalid-audio-id", "id=\(id)")
            #expect(url.query == nil)
        }
        #expect(!EngineAPI.isValidAudioId(id))
    }

    @Test func deleteOneUsesDELETEAndBearer() {
        let r = EngineAPI.audioDeleteOneRequest(port: 1, token: "abc", id: "tr_1")
        #expect(r.httpMethod == "DELETE")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func missingMeansOnly404() {
        #expect(EngineAPI.isAudioMissing(.engine(status: 404, code: "not_found", message: "")))
        #expect(EngineAPI.isAudioMissing(.badResponse(status: 404, detail: "")))
        #expect(!EngineAPI.isAudioMissing(.engine(status: 500, code: "internal", message: "")))
        #expect(!EngineAPI.isAudioMissing(.engine(status: 401, code: "unauthorized", message: "")))
        #expect(!EngineAPI.isAudioMissing(.network("hết giờ")))
        #expect(!EngineAPI.isAudioMissing(.engineNotRunning))
    }
}

@Suite struct AudioHistoryPolicyTests {
    @Test func historyOffForcesAudioOffEvenIfEngineStillRemembersOn() {
        #expect(AudioHistoryPolicy.reconcilePatch(historyEnabled: false, engineAudioHistory: true)?.audioHistory == false)
        #expect(!AudioHistoryPolicy.effectiveToggle(historyEnabled: false, engineAudioHistory: true))
        #expect(!AudioHistoryPolicy.canEnable(historyEnabled: false))
        #expect(AudioHistoryPolicy.disabledReason(historyEnabled: false) != nil)
    }

    @Test func historyOffAndAudioAlreadyOffNeedsNoPatch() {
        #expect(AudioHistoryPolicy.reconcilePatch(historyEnabled: false, engineAudioHistory: false) == nil)
    }

    /// Bật lại Lịch sử KHÔNG được tự bật lưu âm thanh (vừa bật Lịch sử, engine audio_history=false).
    @Test func turningHistoryBackOnNeverEnablesAudio() {
        #expect(AudioHistoryPolicy.reconcilePatch(historyEnabled: true, engineAudioHistory: false) == nil)
        #expect(!AudioHistoryPolicy.effectiveToggle(historyEnabled: true, engineAudioHistory: false))
        #expect(AudioHistoryPolicy.canEnable(historyEnabled: true))
        #expect(AudioHistoryPolicy.disabledReason(historyEnabled: true) == nil)
    }

    @Test func historyOnKeepsUserChoiceOn() {
        #expect(AudioHistoryPolicy.reconcilePatch(historyEnabled: true, engineAudioHistory: true) == nil)
        #expect(AudioHistoryPolicy.effectiveToggle(historyEnabled: true, engineAudioHistory: true))
    }

    @Test func reconcilePatchSendsExactlyAudioHistoryFalse() throws {
        let patch = try #require(AudioHistoryPolicy.reconcilePatch(historyEnabled: false, engineAudioHistory: true))
        let r = EngineAPI.settingsPutRequest(port: 1, token: "t", patch: patch)
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj.count == 1)
        #expect(obj["audio_history"] as? Bool == false)
    }
}

@Suite struct AudioHistoryFormatTests {
    @Test func sizeTextUsesVietnameseDecimalComma() {
        #expect(AudioHistoryFormat.sizeText(bytes: 0) == "0 B")
        #expect(AudioHistoryFormat.sizeText(bytes: 512) == "512 B")
        #expect(AudioHistoryFormat.sizeText(bytes: 1536) == "1,5 KB")
        #expect(AudioHistoryFormat.sizeText(bytes: 200 * 1024 * 1024) == "200 MB")
        #expect(AudioHistoryFormat.sizeText(bytes: Int(3.4 * 1024 * 1024)) == "3,4 MB")
        #expect(AudioHistoryFormat.sizeText(bytes: -5) == "0 B")
    }

    @Test func usageTextShowsRealCountAndBytes() {
        let s = AudioHistorySummary(enabled: true, count: 12, bytes: Int(3.4 * 1024 * 1024), budgetBytes: 200 * 1024 * 1024, days: 7, items: [])
        #expect(AudioHistoryFormat.usageText(s) == "12 tệp · 3,4 MB / giới hạn 200 MB")
    }

    @Test func usageTextForEmptyStoreSaysSoInsteadOfZeroBytes() {
        let s = AudioHistorySummary(enabled: false, count: 0, bytes: 0, budgetBytes: 0, days: 7, items: [])
        #expect(AudioHistoryFormat.usageText(s) == "Chưa có tệp âm thanh nào")
    }
}

@Suite struct TeachErrorTextTests {
    @Test func busyIs429NotAGenericError() {
        let m = TeachErrorText.message(.engine(status: 429, code: "busy", message: "x"))
        #expect(m.contains("bận"))
    }

    @Test func tooLongMentionsPerAttemptLimitForBothCodes() {
        for code in ["too_long", "payload_too_large"] {
            let m = TeachErrorText.message(.engine(status: 413, code: code, message: ""))
            #expect(m.contains("\(TeachWordVariants.maxSecondsPerAttempt) giây"), "code=\(code): \(m)")
        }
    }

    @Test func missingModelCarriesEngineReason() {
        let m = TeachErrorText.message(.engine(status: 503, code: "model_unavailable", message: "Model chưa sẵn sàng (lý do: not_downloaded)"))
        #expect(m.contains("not_downloaded"))
        #expect(m.contains("model"))
    }

    @Test func missingModelWithoutReasonStillSaysModel() {
        let m = TeachErrorText.message(.engine(status: 503, code: "model_unavailable", message: "không rõ"))
        #expect(m.contains("model"))
    }

    @Test func micDeniedPointsToSystemSettings() {
        #expect(TeachErrorText.message(.micDenied).contains("Micro"))
        #expect(TeachErrorText.message(.micDenied).contains("Quyền riêng tư"))
    }

    @Test func engineNotRunningAndNetworkSayEngineIsNotRunning() {
        for e in [ClientError.engineNotRunning, .network("Connection refused")] {
            #expect(TeachErrorText.message(e).contains("Engine chưa chạy"))
        }
    }

    @Test func otherErrorsFallBackToGenericText() {
        let e = ClientError.engine(status: 500, code: "internal", message: "")
        #expect(TeachErrorText.message(e) == ErrorText.message(e))
    }
}
