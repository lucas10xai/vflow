import Foundation

/// Mở rộng `EngineAPI` (V2): thống kê, xuất/nhập, chẩn đoán, gợi ý từ điển, xem chữ chạy trực tiếp —
/// theo contract/engine-api.md. Giữ nguyên quy ước của file gốc: request builder trả `URLRequest`
/// thuần, `parse*` trả `Result<T, ClientError>` và KHÔNG BAO GIỜ suy đoán giá trị khi trường vắng
/// mặt/`null` (vd. `avg_wpm: null` ⇒ `nil`, không phải `0` — xem `StatsSummary`).

// MARK: - Thống kê (GET/DELETE /v1/stats)

public struct DayStat: Equatable, Sendable {
    public var date: String
    public var words: Int
    public var count: Int
    public var audioMs: Int

    public init(date: String, words: Int, count: Int, audioMs: Int) {
        self.date = date
        self.words = words
        self.count = count
        self.audioMs = audioMs
    }
}

public struct AppWordStat: Equatable, Sendable, Identifiable {
    public var app: String
    public var words: Int
    public var count: Int
    public var id: String { app }

    public init(app: String, words: Int, count: Int) {
        self.app = app
        self.words = words
        self.count = count
    }
}

public struct StatsSummary: Equatable, Sendable {
    public var enabled: Bool
    public var since: String?
    public var weeks: Int
    public var weekStart: String
    public var today: String
    public var totalWords: Int
    public var totalCount: Int
    public var totalAudioMs: Int
    /// `nil` = chưa đủ dữ liệu (< 60 s âm thanh) — KHÔNG BAO GIỜ hiện số 0 giả, hiện "—" ở UI.
    public var avgWpm: Int?
    public var currentStreak: Int
    public var bestStreak: Int
    public var days: [DayStat]
    public var topApps: [AppWordStat]

    public init(enabled: Bool, since: String?, weeks: Int, weekStart: String, today: String, totalWords: Int,
                totalCount: Int, totalAudioMs: Int, avgWpm: Int?, currentStreak: Int, bestStreak: Int,
                days: [DayStat], topApps: [AppWordStat]) {
        self.enabled = enabled
        self.since = since
        self.weeks = weeks
        self.weekStart = weekStart
        self.today = today
        self.totalWords = totalWords
        self.totalCount = totalCount
        self.totalAudioMs = totalAudioMs
        self.avgWpm = avgWpm
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.days = days
        self.topApps = topApps
    }
}

public extension EngineAPI {
    static func statsRequest(port: Int, token: String, weeks: Int = 16) -> URLRequest {
        var c = URLComponents(url: baseURL(port: port).appendingPathComponent("v1/stats"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "weeks", value: String(weeks))]
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func statsDeleteRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/stats"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "DELETE"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func parseStats(status: Int, data: Data) -> Result<StatsSummary, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = obj["enabled"] as? Bool,
              let weeks = obj["weeks"] as? Int,
              let weekStart = obj["week_start"] as? String,
              let today = obj["today"] as? String,
              let totalWords = obj["total_words"] as? Int,
              let totalCount = obj["total_count"] as? Int,
              let totalAudioMs = obj["total_audio_ms"] as? Int,
              let currentStreak = obj["current_streak"] as? Int,
              let bestStreak = obj["best_streak"] as? Int,
              let rawDays = obj["days"] as? [[String: Any]],
              let rawTopApps = obj["top_apps"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường thống kê"))
        }
        let days = rawDays.compactMap { d -> DayStat? in
            guard let date = d["date"] as? String, let words = d["words"] as? Int,
                  let count = d["count"] as? Int, let audioMs = d["audio_ms"] as? Int else { return nil }
            return DayStat(date: date, words: words, count: count, audioMs: audioMs)
        }
        let topApps = rawTopApps.compactMap { a -> AppWordStat? in
            guard let app = a["app"] as? String, let words = a["words"] as? Int, let count = a["count"] as? Int else { return nil }
            return AppWordStat(app: app, words: words, count: count)
        }
        return .success(StatsSummary(enabled: enabled, since: obj["since"] as? String, weeks: weeks, weekStart: weekStart,
                                     today: today, totalWords: totalWords, totalCount: totalCount, totalAudioMs: totalAudioMs,
                                     avgWpm: obj["avg_wpm"] as? Int, currentStreak: currentStreak, bestStreak: bestStreak,
                                     days: days, topApps: topApps))
    }

    /// `DELETE /v1/stats` → `{"ok":true}`.
    static func parseOk(status: Int, data: Data) -> Result<Void, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["ok"] as? Bool == true else {
            return .failure(.badResponse(status: status, detail: "thiếu trường ok"))
        }
        return .success(())
    }
}

// MARK: - Gợi ý từ điển (GET /v1/dictionary/suggestions, POST .../dismiss)

public struct DictionarySuggestion: Equatable, Sendable, Identifiable {
    public var term: String
    public var variants: [String]
    public var count: Int
    public var lastSeen: String
    public var id: String { term }

    public init(term: String, variants: [String], count: Int, lastSeen: String) {
        self.term = term
        self.variants = variants
        self.count = count
        self.lastSeen = lastSeen
    }
}

public extension EngineAPI {
    static func dictionarySuggestionsRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/dictionary/suggestions"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func dictionarySuggestionDismissRequest(port: Int, token: String, term: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/dictionary/suggestions/dismiss"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["term": term])
        return r
    }

    static func parseDictionarySuggestions(status: Int, data: Data) -> Result<[DictionarySuggestion], ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["suggestions"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường suggestions"))
        }
        return .success(raw.compactMap { s in
            guard let term = s["term"] as? String, let variants = s["variants"] as? [String],
                  let count = s["count"] as? Int, let lastSeen = s["last_seen"] as? String else { return nil }
            return DictionarySuggestion(term: term, variants: variants, count: count, lastSeen: lastSeen)
        })
    }
}

// MARK: - Xuất/nhập (GET /v1/export, POST /v1/import)

public enum ImportMode: String, Sendable { case merge, replace }

public struct ImportApplied: Equatable, Sendable {
    public var dictionary: Int
    public var snippets: Int
    public var settings: Int
    public var statsDays: Int
    public var history: Int
    public var ignored: [String]

    public init(dictionary: Int, snippets: Int, settings: Int, statsDays: Int, history: Int, ignored: [String]) {
        self.dictionary = dictionary
        self.snippets = snippets
        self.settings = settings
        self.statsDays = statsDays
        self.history = history
        self.ignored = ignored
    }
}

public extension EngineAPI {
    static func exportRequest(port: Int, token: String, includeHistory: Bool) -> URLRequest {
        var c = URLComponents(url: baseURL(port: port).appendingPathComponent("v1/export"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "include_history", value: includeHistory ? "1" : "0")]
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    /// `data` nguyên vẹn là nội dung lưu ra tệp (`NSSavePanel`) — client KHÔNG tái dựng JSON từ các
    /// kiểu Swift riêng (tránh làm rơi trường chưa model hoá, vd `stats.days` chi tiết/`history`).
    /// Chỉ kiểm `format`/`version` đúng dạng trước khi coi là hợp lệ để lưu.
    static func validateExportResponse(status: Int, data: Data) -> Result<Data, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["format"] as? String == "vflow-export", obj["version"] is Int else {
            return .failure(.badResponse(status: status, detail: "gói xuất không đúng dạng"))
        }
        return .success(data)
    }

    /// `data`: nội dung tệp người dùng chọn qua `NSOpenPanel` (nguyên văn, KHÔNG sửa) — engine kiểm
    /// hợp lệ NGHIÊM toàn bộ trước khi áp dụng (contract: sai bất kỳ phần nào ⇒ từ chối cả gói).
    static func importRequest(port: Int, token: String, mode: ImportMode, data: Data) -> URLRequest {
        var c = URLComponents(url: baseURL(port: port).appendingPathComponent("v1/import"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = data
        return r
    }

    static func parseImportResult(status: Int, data: Data) -> Result<ImportApplied, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true, let applied = obj["applied"] as? [String: Any],
              let dictionary = applied["dictionary"] as? Int, let snippets = applied["snippets"] as? Int,
              let settings = applied["settings"] as? Int, let statsDays = applied["stats_days"] as? Int,
              let history = applied["history"] as? Int else {
            return .failure(.badResponse(status: status, detail: "thiếu trường applied"))
        }
        return .success(ImportApplied(dictionary: dictionary, snippets: snippets, settings: settings,
                                      statsDays: statsDays, history: history, ignored: obj["ignored"] as? [String] ?? []))
    }
}

// MARK: - Chẩn đoán (GET /v1/diagnostics)

public struct RecentErrorEntry: Equatable, Sendable {
    public var at: String
    public var route: String
    public var status: Int
    public var code: String

    public init(at: String, route: String, status: Int, code: String) {
        self.at = at
        self.route = route
        self.status = status
        self.code = code
    }
}

public struct DiagnosticsInfo: Equatable, Sendable {
    public var engineVersion: String
    public var node: String
    public var platform: String
    public var uptimeSeconds: Int
    public var modelDefault: String
    public var modelStatus: [ModelStatus]
    public var sttDefault: String
    public var settings: AppSettings
    public var countDictionary: Int
    public var countSnippets: Int
    public var countHistory: Int
    public var countStatsDays: Int
    public var homeBasename: String
    public var recentErrors: [RecentErrorEntry]
    /// Văn bản để "Sao chép chẩn đoán"/"Lưu chẩn đoán…" — JSON gốc engine trả (đã không chứa
    /// token/khoá/văn bản dictation theo hợp đồng), định dạng đẹp để dễ đọc khi dán.
    public var prettyText: String

    public init(engineVersion: String, node: String, platform: String, uptimeSeconds: Int, modelDefault: String,
                modelStatus: [ModelStatus], sttDefault: String, settings: AppSettings, countDictionary: Int,
                countSnippets: Int, countHistory: Int, countStatsDays: Int, homeBasename: String,
                recentErrors: [RecentErrorEntry], prettyText: String) {
        self.engineVersion = engineVersion
        self.node = node
        self.platform = platform
        self.uptimeSeconds = uptimeSeconds
        self.modelDefault = modelDefault
        self.modelStatus = modelStatus
        self.sttDefault = sttDefault
        self.settings = settings
        self.countDictionary = countDictionary
        self.countSnippets = countSnippets
        self.countHistory = countHistory
        self.countStatsDays = countStatsDays
        self.homeBasename = homeBasename
        self.recentErrors = recentErrors
        self.prettyText = prettyText
    }
}

public extension EngineAPI {
    static func diagnosticsRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/diagnostics"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func parseDiagnostics(status: Int, data: Data) -> Result<DiagnosticsInfo, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let engineVersion = obj["engine_version"] as? String,
              let node = obj["node"] as? String,
              let platform = obj["platform"] as? String,
              let uptimeSeconds = obj["uptime_s"] as? Int,
              let model = obj["model"] as? [String: Any],
              let modelDefault = model["default"] as? String,
              let rawModelStatus = model["status"] as? [[String: Any]],
              let stt = obj["stt"] as? [String: Any],
              let sttDefault = stt["default"] as? String,
              let settingsObj = obj["settings"] as? [String: Any],
              let settings = appSettings(from: settingsObj),
              let counts = obj["counts"] as? [String: Any],
              let countDictionary = counts["dictionary"] as? Int,
              let countSnippets = counts["snippets"] as? Int,
              let countHistory = counts["history"] as? Int,
              let countStatsDays = counts["stats_days"] as? Int,
              let paths = obj["paths"] as? [String: Any],
              let homeBasename = paths["home_basename"] as? String,
              let rawRecentErrors = obj["recent_errors"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường chẩn đoán"))
        }
        let modelStatus = rawModelStatus.compactMap { m -> ModelStatus? in
            guard let id = m["id"] as? String else { return nil }
            return ModelStatus(id: id, kind: m["kind"] as? String ?? "?", loaded: m["loaded"] as? Bool ?? false, reason: m["reason"] as? String)
        }
        let recentErrors = rawRecentErrors.compactMap { e -> RecentErrorEntry? in
            guard let at = e["at"] as? String, let route = e["route"] as? String,
                  let status = e["status"] as? Int, let code = e["code"] as? String else { return nil }
            return RecentErrorEntry(at: at, route: route, status: status, code: code)
        }
        let pretty: String
        if let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            pretty = String(decoding: prettyData, as: UTF8.self)
        } else {
            pretty = String(decoding: data, as: UTF8.self)
        }
        return .success(DiagnosticsInfo(engineVersion: engineVersion, node: node, platform: platform, uptimeSeconds: uptimeSeconds,
                                        modelDefault: modelDefault, modelStatus: modelStatus, sttDefault: sttDefault,
                                        settings: settings, countDictionary: countDictionary, countSnippets: countSnippets,
                                        countHistory: countHistory, countStatsDays: countStatsDays, homeBasename: homeBasename,
                                        recentErrors: recentErrors, prettyText: pretty))
    }
}

// MARK: - Xem chữ chạy trực tiếp (POST /v1/partial)

public struct PartialResult: Equatable, Sendable {
    public var text: String
    public var audioMs: Int
    public var sttMs: Int

    public init(text: String, audioMs: Int, sttMs: Int) {
        self.text = text
        self.audioMs = audioMs
        self.sttMs = sttMs
    }
}

public extension EngineAPI {
    static func partialRequest(port: Int, token: String, pcm: Data, timeout: TimeInterval = 5) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/partial"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("audio/L16; rate=16000; channels=1", forHTTPHeaderField: "Content-Type")
        r.httpBody = pcm
        return r
    }

    static func parsePartial(status: Int, data: Data) -> Result<PartialResult, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String, let audioMs = obj["audio_ms"] as? Int,
              let sttMs = obj["stt_ms"] as? Int else {
            return .failure(.badResponse(status: status, detail: "thiếu trường partial"))
        }
        return .success(PartialResult(text: text, audioMs: audioMs, sttMs: sttMs))
    }

    /// `true` ⇒ engine đang bận yêu cầu `/v1/partial` khác — client tự bỏ qua lần này (contract: tối
    /// đa 1 yêu cầu đồng thời), KHÔNG hiện lỗi.
    static func isPartialBusy(_ error: ClientError) -> Bool {
        if case .engine(_, "busy", _) = error { return true }
        return false
    }
}
