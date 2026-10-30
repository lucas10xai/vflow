import Foundation
import Testing
@testable import VFlowCore

/// Kiểm tích hợp THẬT (không mô phỏng): gọi `EngineAPI` qua `URLSession` thật tới một engine Node
/// THẬT đang chạy ở cổng cô lập (KHÔNG phải 7611, KHÔNG đụng `~/.vflow`). Chỉ chạy khi có
/// `VFLOW_LIVE_TEST_PORT`/`VFLOW_LIVE_TEST_TOKEN` trong môi trường — tạo bằng tay, vd.:
///   node client/scripts/snapshot-seed.mjs /tmp/vflow-x "$PWD"
///   VFLOW_HOME=/tmp/vflow-x node bin/vflow.js serve --port 27711
///   VFLOW_LIVE_TEST_PORT=27711 VFLOW_LIVE_TEST_TOKEN=$(cat /tmp/vflow-x/token) swift test --filter EngineAPILiveIntegration
/// Vắng mặt hai biến môi trường ⇒ bỏ qua ÊM (không fail bộ test thường/CI không có engine).
/// `.serialized` (V5): từ khi có các test Dịch ghi `PUT /v1/settings` (`cloud_llm`/`llm_model`) lên
/// CÙNG engine tạm dùng chung, chạy song song (mặc định của Swift Testing) làm các test khác đọc
/// trúng cấu hình đang bị một test kia đổi giữa chừng — đã ĐO ĐƯỢC race thật (xem báo cáo V5: test
/// trả 200 thay vì 503 vì một test khác vừa bật lại `cloud_llm` cùng lúc). Engine tạm chỉ phục vụ
/// bộ test này nên chạy nối tiếp không mất gì về tốc độ đáng kể.
@Suite(.serialized, .enabled(if: LiveEngine.isConfigured))
struct EngineAPILiveIntegrationTests {
    @Test func healthzReportsMaxAudioSeconds() async throws {
        let (data, status) = try await LiveEngine.get("/healthz", auth: false)
        #expect(status == 200)
        let h = try #require(EngineAPI.parseHealth(status: status, data: data))
        #expect(h.maxAudioSeconds == 1200)
    }

    @Test func statsRoundTripsWeekStartAndSchema() async throws {
        let (data, status) = try await LiveEngine.get("/v1/stats?weeks=16")
        let s = try EngineAPI.parseStats(status: status, data: data).get()
        #expect(s.weekStart == "monday")
        // `days[]` chỉ tới HÔM NAY (không có ngày tương lai) — tuần hiện tại thường NGẮN hơn 7 ngày,
        // nên đúng khoảng (15 tuần đủ + 1..7 ngày của tuần hiện tại), không phải luôn đúng 16*7.
        #expect(s.days.count > 15 * 7 && s.days.count <= 16 * 7)
        #expect(s.today.count == 10)
    }

    @Test func dictionarySuggestionsRoundTrip() async throws {
        let (data, status) = try await LiveEngine.get("/v1/dictionary/suggestions")
        _ = try EngineAPI.parseDictionarySuggestions(status: status, data: data).get()
    }

    /// Bằng chứng đỏ (V6, đo thật): bản trước kiểm `!text.contains("\"token\"")` trên TOÀN văn bản
    /// export — vỡ THẬT khi chạy với engine thật vì `config/dictionary.seed.json` có mục từ điển hợp
    /// lệ `{"term":"token",...}` (từ vựng kỹ thuật bình thường, như "access token" — không phải khoá
    /// bí mật). Chuỗi "token" trong NỘI DUNG do người dùng tự thêm vào từ điển/lịch sử là dữ liệu hợp
    /// lệ, không phải rò rỉ — khoá bí mật chỉ có thể lộ qua trường CẤU HÌNH (`settings`), không bao
    /// giờ qua từ điển/snippets/lịch sử. Kiểm đúng chỗ: `settings` không có khoá nào tên `token`/chứa
    /// `key`, và object GỐC không có trường `token` (đúng hình dạng export thật đã xác nhận bằng tay).
    @Test func exportIsValidAndContainsNoSecrets() async throws {
        let (data, status) = try await LiveEngine.get("/v1/export?include_history=1")
        let saved = try EngineAPI.validateExportResponse(status: status, data: data).get()
        let text = String(decoding: saved, as: UTF8.self).lowercased()
        #expect(!text.contains("rewrite.key"))
        let obj = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(obj["token"] == nil, "object gốc không được có trường token")
        let settings = try #require(obj["settings"] as? [String: Any])
        for key in settings.keys {
            #expect(!key.lowercased().contains("token") && !key.lowercased().contains("key"),
                     "settings không được có khoá liên quan bí mật: \(key)")
        }
    }

    @Test func importRejectsWholePackageWhenOnePartIsBroken() async throws {
        let (exportData, exportStatus) = try await LiveEngine.get("/v1/export?include_history=0")
        #expect(exportStatus == 200)
        var obj = try #require(try JSONSerialization.jsonObject(with: exportData) as? [String: Any])
        var dict = obj["dictionary"] as? [[String: Any]] ?? []
        dict.append(["term": "", "spoken": ["x"]])
        obj["dictionary"] = dict
        let broken = try JSONSerialization.data(withJSONObject: obj)
        let (respData, status) = try await LiveEngine.post("/v1/import?mode=merge", body: broken)
        guard case .failure(.engine(400, "bad_request", let msg)) = EngineAPI.parseImportResult(status: status, data: respData) else {
            Issue.record("gói hỏng một phần phải bị từ chối cả gói"); return
        }
        #expect(msg.contains("dictionary"))
    }

    @Test func diagnosticsRoundTrip() async throws {
        let (data, status) = try await LiveEngine.get("/v1/diagnostics")
        let d = try EngineAPI.parseDiagnostics(status: status, data: data).get()
        #expect(d.settings.livePreview || !d.settings.livePreview) // chỉ cần giải mã được, không crash
        #expect(!d.prettyText.lowercased().contains("rewrite.key"))
    }

    @Test func settingsRoundTripsAllV2Fields() async throws {
        let (data, status) = try await LiveEngine.get("/v1/settings")
        let s = try EngineAPI.parseSettings(status: status, data: data).get()
        _ = s.appRules
        _ = s.tone
    }

    // MARK: V5 — Dịch: languages/auto_detect THẬT ở /healthz, settings mới, POST /v1/translate thật

    /// Engine THẬT (không mock) phải nêu `languages`/`auto_detect` TỪNG MODEL (contract mục Cấu
    /// hình) — KHÔNG ở gốc JSON. Test này tái xác nhận hình dạng thật đã đo bằng tay qua curl trước
    /// khi sửa `EngineAPI.parseHealth` (bằng chứng đỏ: bản cũ đọc `obj["languages"]` ở gốc, luôn ra
    /// `nil` dù engine thật có báo đúng từng model).
    @Test func healthzReportsLanguagesPerModelNotAtTopLevel() async throws {
        let (data, status) = try await LiveEngine.get("/healthz", auth: false)
        #expect(status == 200)
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(raw["languages"] == nil, "engine THẬT không có trường languages ở gốc — xác nhận bằng chứng đỏ")
        let models = try #require(raw["models"] as? [[String: Any]])
        #expect(models.contains { $0["languages"] != nil }, "phải có ÍT NHẤT một model báo languages")
        let h = try #require(EngineAPI.parseHealth(status: status, data: data))
        #expect(h.models.contains { $0.languages != nil })
    }

    @Test func settingsRoundTripsTranslateAndSttLanguageKeys() async throws {
        let (data, status) = try await LiveEngine.get("/v1/settings")
        #expect(status == 200)
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(raw["stt_language"] is String)
        #expect(raw["translate_target"] is String)
        #expect(raw["translate_formality"] is String)
        let s = try EngineAPI.parseSettings(status: status, data: data).get()
        #expect(s.sttLanguage == .vietnamese || s.sttLanguage == .english || s.sttLanguage == .automatic)

        // Ghi rồi đọc lại — đọc-sửa-ghi thật, không phải echo giả.
        let patch = SettingsPatch(translateTarget: "ja", translateFormality: .formal)
        let (putData, putStatus) = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: patch.jsonObject))
        let updated = try EngineAPI.parseSettings(status: putStatus, data: putData).get()
        #expect(updated.translateTarget == "ja")
        #expect(updated.translateFormality == .formal)
        // Dọn lại mặc định để không ảnh hưởng test khác chạy cùng engine tạm này.
        _ = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: SettingsPatch(translateTarget: "en", translateFormality: .neutral).jsonObject))
    }

    @Test func translateSucceedsAgainstRealEngineWithFakeLLM() async throws {
        // Yêu cầu: trước khi chạy, trỏ llm_model sang kịch bản "ok" (xem báo cáo V5 — fake LLM
        // local dùng field "model" để chọn kịch bản, giống engine/post/rewrite.test.js).
        _ = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: ["cloud_llm": true, "llm_model": "ok"]))
        let body = try JSONSerialization.data(withJSONObject: ["text": "Xin chào thế giới", "target": "en"])
        let (data, status) = try await LiveEngine.post("/v1/translate", body: body)
        let result = try EngineAPI.parseTranslate(status: status, data: data).get()
        #expect(!result.text.isEmpty)
    }

    @Test func translateGuardBlockedReturnsNoText() async throws {
        _ = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: ["cloud_llm": true, "llm_model": "guard_vi"]))
        let body = try JSONSerialization.data(withJSONObject: ["text": "Xin chào thế giới", "target": "en"])
        let (data, status) = try await LiveEngine.post("/v1/translate", body: body)
        guard case .failure = EngineAPI.parseTranslate(status: status, data: data) else {
            Issue.record("guard chặn (còn nguyên tiếng Việt) phải là .failure, không trả text"); return
        }
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(raw["degraded_reason"] as? String == "translate_guard")
    }

    @Test func translateWithCloudDisabledReturns503WithoutNetworkCall() async throws {
        _ = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: ["cloud_llm": false]))
        let body = try JSONSerialization.data(withJSONObject: ["text": "Xin chào thế giới", "target": "en"])
        let (data, status) = try await LiveEngine.post("/v1/translate", body: body)
        #expect(status == 503)
        guard case .failure(.engine(503, "cloud_disabled", _)) = EngineAPI.parseTranslate(status: status, data: data) else {
            Issue.record("cloud_llm tắt phải trả 503 cloud_disabled"); return
        }
        _ = try await LiveEngine.put("/v1/settings", body: try JSONSerialization.data(withJSONObject: ["cloud_llm": true, "llm_model": "ok"]))
    }
}

/// Cấu hình đọc từ môi trường — KHÔNG hard-code cổng/token (bí mật không bao giờ vào repo).
enum LiveEngine {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["VFLOW_LIVE_TEST_PORT"] != nil &&
            ProcessInfo.processInfo.environment["VFLOW_LIVE_TEST_TOKEN"] != nil
    }

    private static var port: Int { Int(ProcessInfo.processInfo.environment["VFLOW_LIVE_TEST_PORT"] ?? "") ?? 0 }
    private static var token: String { ProcessInfo.processInfo.environment["VFLOW_LIVE_TEST_TOKEN"] ?? "" }

    static func get(_ path: String, auth: Bool = true) async throws -> (Data, Int) {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        if auth { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func post(_ path: String, body: Data) async throws -> (Data, Int) {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: r)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func put(_ path: String, body: Data) async throws -> (Data, Int) {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        r.httpMethod = "PUT"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: r)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
