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
@Suite(.enabled(if: LiveEngine.isConfigured))
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

    @Test func exportIsValidAndContainsNoSecrets() async throws {
        let (data, status) = try await LiveEngine.get("/v1/export?include_history=1")
        let saved = try EngineAPI.validateExportResponse(status: status, data: data).get()
        let text = String(decoding: saved, as: UTF8.self).lowercased()
        #expect(!text.contains("rewrite.key"))
        #expect(!text.contains("\"token\""))
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
}
