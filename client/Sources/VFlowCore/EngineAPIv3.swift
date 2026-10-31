import Foundation

/// Mở rộng `EngineAPI` (V3): "Dạy từ bằng giọng" (`/v1/teach`) và Lịch sử âm thanh (`/v1/audio*`).
/// Theo hợp đồng engine E3 thực hiện song song (chưa có trong contract/engine-api.md lúc viết file
/// này — xem mô tả trong TASK của worker A3/V3; nếu engine chạy thật chưa có các route này, mọi
/// hàm `parse*` ở đây vẫn hoạt động đúng luật chung: 404/lỗi khác trả `ClientError` thật, KHÔNG
/// giả định thành công).

// MARK: - Dạy từ bằng giọng (POST /v1/teach)

public struct TeachResult: Equatable, Sendable {
    public var heard: String
    public var audioMs: Int
    public var sttMs: Int

    public init(heard: String, audioMs: Int, sttMs: Int) {
        self.heard = heard
        self.audioMs = audioMs
        self.sttMs = sttMs
    }
}

public extension EngineAPI {
    /// Âm thanh CÙNG định dạng/quy tắc `/v1/partial` (PCM 16 kHz mono LE) — không ghi đĩa phía
    /// client (xem `AudioRecorder`), chỉ truyền thẳng vào RAM rồi gửi.
    /// `model`: TUỲ CHỌN (mặc định `default_model` của engine) — màn hình chọn model dùng tham số
    /// này để "nạp" (ensure) một model cụ thể và thấy lỗi `model_unavailable` ngay, không đợi lần
    /// đọc chính tả thật đầu tiên mới biết model hỏng.
    static func teachRequest(port: Int, token: String, pcm: Data, model: String? = nil, timeout: TimeInterval = 20) -> URLRequest {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        c.path = "/v1/teach"
        if let model, !model.isEmpty { c.queryItems = [URLQueryItem(name: "model", value: model)] }
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("audio/L16; rate=16000; channels=1", forHTTPHeaderField: "Content-Type")
        r.httpBody = pcm
        return r
    }

    static func parseTeach(status: Int, data: Data) -> Result<TeachResult, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let heard = obj["heard"] as? String, let audioMs = obj["audio_ms"] as? Int,
              let sttMs = obj["stt_ms"] as? Int else {
            return .failure(.badResponse(status: status, detail: "thiếu trường heard/audio_ms/stt_ms"))
        }
        return .success(TeachResult(heard: heard, audioMs: audioMs, sttMs: sttMs))
    }

    /// `true` ⇒ engine đang bận yêu cầu khác (tối đa 1 `/v1/teach`/`/v1/partial` đồng thời theo cùng
    /// luật) — client tự báo "đang bận, thử lại" thay vì lỗi chung.
    static func isTeachBusy(_ error: ClientError) -> Bool {
        if case .engine(_, "busy", _) = error { return true }
        return false
    }

    /// `true` ⇒ đoạn ghi quá dài cho một lần dạy từ (giới hạn 15 giây, khác 30 giây của `/v1/partial`).
    static func isTeachTooLong(_ error: ClientError) -> Bool {
        if case .engine(_, "too_long", _) = error { return true }
        return false
    }
}

// MARK: - Lịch sử âm thanh (GET/DELETE /v1/audio, GET /v1/audio/<id>, GET /v1/audio/export)

public struct AudioHistoryItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var bytes: Int
    public var audioMs: Int
    public var at: String

    public init(id: String, bytes: Int, audioMs: Int, at: String) {
        self.id = id
        self.bytes = bytes
        self.audioMs = audioMs
        self.at = at
    }
}

public struct AudioHistorySummary: Equatable, Sendable {
    public var enabled: Bool
    public var count: Int
    public var bytes: Int
    public var budgetBytes: Int
    public var days: Int
    public var items: [AudioHistoryItem]

    public init(enabled: Bool, count: Int, bytes: Int, budgetBytes: Int, days: Int, items: [AudioHistoryItem]) {
        self.enabled = enabled
        self.count = count
        self.bytes = bytes
        self.budgetBytes = budgetBytes
        self.days = days
        self.items = items
    }
}

public extension EngineAPI {
    static func audioListRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/audio"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func parseAudioList(status: Int, data: Data) -> Result<AudioHistorySummary, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = obj["enabled"] as? Bool, let count = obj["count"] as? Int,
              let bytes = obj["bytes"] as? Int, let budgetBytes = obj["budget_bytes"] as? Int,
              let days = obj["days"] as? Int, let rawItems = obj["items"] as? [[String: Any]] else {
            return .failure(.badResponse(status: status, detail: "thiếu trường âm thanh lịch sử"))
        }
        // Mục hỏng là lỗi thật (hợp đồng engine luôn có đủ 4 trường) — KHÔNG lặng lẽ bỏ qua rồi hiện
        // số tệp lệch với danh sách. `count` có thể lớn hơn `items.count` (engine chỉ liệt kê tối đa
        // 500 mục gần nhất), nên không bắt hai số bằng nhau.
        var items: [AudioHistoryItem] = []
        items.reserveCapacity(rawItems.count)
        for (index, i) in rawItems.enumerated() {
            guard let id = i["id"] as? String, let b = i["bytes"] as? Int,
                  let ms = i["audio_ms"] as? Int, let at = i["at"] as? String else {
                return .failure(.badResponse(status: status, detail: "mục âm thanh thứ \(index + 1) thiếu trường id/bytes/audio_ms/at"))
            }
            items.append(AudioHistoryItem(id: id, bytes: b, audioMs: ms, at: at))
        }
        return .success(AudioHistorySummary(enabled: enabled, count: count, bytes: bytes, budgetBytes: budgetBytes, days: days, items: items))
    }

    /// `true` ⇔ `id` đúng định dạng id engine (`[A-Za-z0-9_-]+`, xem `engine/post/audiostore.js`).
    static func isValidAudioId(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { s in
            (s.value >= 48 && s.value <= 57) || (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122) || s == "-" || s == "_"
        }
    }

    /// URL một bản ghi âm. `audio_id` đọc từ `history.jsonl` trên đĩa: id sai định dạng (vd. ".",
    /// "..", "a/b") KHÔNG được ghép vào đường dẫn — "." sẽ bị chuẩn hoá thành `/v1/audio/` và một
    /// lệnh DELETE sẽ xoá TOÀN BỘ âm thanh. Id sai ⇒ dùng id mồi không bao giờ tồn tại ⇒ engine trả
    /// 404 (client coi là "bản ghi không còn").
    static func audioItemURL(port: Int, id: String) -> URL {
        let segment = isValidAudioId(id) ? id : "invalid-audio-id"
        return baseURL(port: port).appendingPathComponent("v1/audio").appendingPathComponent(segment)
    }

    /// 404 ⇒ bản ghi âm không còn phía engine (hết hạn, vượt ngân sách, đã xoá): client gỡ `audio_id`
    /// khỏi mục lịch sử và ẩn nút phát. Chỉ 404 — lỗi khác (engine bận/chết) KHÔNG làm mất tham chiếu.
    static func isAudioMissing(_ error: ClientError) -> Bool {
        switch error {
        case .engine(let status, _, _): return status == 404
        case .badResponse(let status, _): return status == 404
        default: return false
        }
    }

    static func audioGetRequest(port: Int, token: String, id: String, timeout: TimeInterval = 20) -> URLRequest {
        var r = URLRequest(url: audioItemURL(port: port, id: id),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    /// `data` nguyên vẹn (audio/wav) khi 200 — client chỉ ghi ra tệp TẠM 0600, xoá NGAY sau khi phát
    /// xong (xem `AudioPlaybackCoordinator`), không bao giờ thêm vào `~/.vflow` thật của client.
    static func parseAudioGet(status: Int, data: Data) -> Result<Data, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        return .success(data)
    }

    static func audioDeleteOneRequest(port: Int, token: String, id: String) -> URLRequest {
        var r = URLRequest(url: audioItemURL(port: port, id: id),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "DELETE"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func audioDeleteAllRequest(port: Int, token: String) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/audio"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        r.httpMethod = "DELETE"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func parseAudioDeleteAll(status: Int, data: Data) -> Result<Int, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true, let deleted = obj["deleted"] as? Int else {
            return .failure(.badResponse(status: status, detail: "thiếu trường deleted"))
        }
        return .success(deleted)
    }

    static func audioExportRequest(port: Int, token: String, timeout: TimeInterval = 30) -> URLRequest {
        var r = URLRequest(url: baseURL(port: port).appendingPathComponent("v1/audio/export"),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    /// Engine trả ZIP hợp lệ kể cả khi chưa có tệp nào (chỉ có `index.json`); lỗi ⇒ thông điệp
    /// tiếng Việt của engine qua `ErrorText.message`, không có mã riêng ở client.
    static func parseAudioExport(status: Int, data: Data) -> Result<Data, ClientError> {
        guard status == 200 else { return .failure(errorFrom(status: status, data: data)) }
        return .success(data)
    }
}

/// Phát lại MỘT bản âm thanh lịch sử — điều phối thuần: chỉ MỘT bản đang phát tại một thời điểm,
/// bắt đầu bản mới tự dừng bản cũ. Lớp AppKit (`AVAudioPlayer`, tệp tạm 0600) nằm ở `VFlow`, lớp
/// này chỉ giữ ID nào đang phát để UI biết tô sáng nút nào — test được không cần âm thanh thật.
public enum AudioPlaybackState: Equatable, Sendable {
    case idle
    case playing(id: String)
    case error(id: String, message: String)
}

public struct AudioPlaybackCoordinator: Sendable {
    public private(set) var state: AudioPlaybackState = .idle

    public init() {}

    /// Bấm phát mục `id`: đang phát CHÍNH mục đó ⇒ coi là bấm "dừng" (trả `.stop`); đang phát mục
    /// KHÁC hoặc đang rảnh ⇒ bắt đầu mục mới (trả `.startNew`, lớp AppKit tự dừng player cũ trước
    /// khi phát cái mới).
    public enum Intent: Equatable, Sendable { case stop, startNew(id: String) }

    public mutating func togglePlay(id: String) -> Intent {
        if case .playing(let current) = state, current == id {
            state = .idle
            return .stop
        }
        state = .playing(id: id)
        return .startNew(id: id)
    }

    public mutating func finished(id: String) {
        if case .playing(let current) = state, current == id { state = .idle }
    }

    public mutating func failed(id: String, message: String) {
        state = .error(id: id, message: message)
    }

    public mutating func stop() { state = .idle }
}

/// Quy tắc "Lưu âm thanh để nghe lại" ↔ "Lưu lịch sử" (client giữ lịch sử, engine giữ âm thanh): âm
/// thanh CHỈ có nghĩa khi có mục lịch sử mang `audio_id` đi cùng — Lịch sử tắt thì không có chỗ nào
/// để nghe lại, mà engine vẫn ghi tệp mồ côi nếu `audio_history` còn bật. Thuần, test được.
public enum AudioHistoryPolicy {
    /// Công tắc "Lưu âm thanh" bật được không (cần Lịch sử bật).
    public static func canEnable(historyEnabled: Bool) -> Bool { historyEnabled }

    /// Lý do hiện cạnh công tắc khi bị vô hiệu hoá; `nil` khi dùng được.
    public static func disabledReason(historyEnabled: Bool) -> String? {
        historyEnabled ? nil : "Cần bật Lịch sử (Cài đặt › Lịch sử & riêng tư) — âm thanh chỉ lưu kèm câu trong Lịch sử."
    }

    /// Giá trị công tắc HIỂN THỊ: Lịch sử tắt thì luôn tắt, dù engine còn nhớ `true` (sẽ được
    /// `reconcilePatch` sửa).
    public static func effectiveToggle(historyEnabled: Bool, engineAudioHistory: Bool) -> Bool {
        historyEnabled && engineAudioHistory
    }

    /// Bản vá cần gửi engine để giữ bất biến "Lịch sử tắt ⇒ `audio_history=false`"; `nil` = đã đúng.
    /// Bật lại Lịch sử KHÔNG bao giờ tự bật lưu âm thanh (không có nhánh trả `true`).
    public static func reconcilePatch(historyEnabled: Bool, engineAudioHistory: Bool) -> SettingsPatch? {
        guard !historyEnabled, engineAudioHistory else { return nil }
        return SettingsPatch(audioHistory: false)
    }
}

/// Định dạng số liệu "Lưu âm thanh" cho UI (dấu thập phân kiểu Việt).
public enum AudioHistoryFormat {
    /// "0 B", "512 B", "1,5 KB", "3,4 MB", "1,2 GB" (hệ 1024).
    public static func sizeText(bytes: Int) -> String {
        let b = max(0, bytes)
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(b)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(b) B" }
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
        return "\(text) \(units[unit])"
    }

    /// "12 tệp · 3,4 MB / giới hạn 200 MB"; chưa có tệp: "Chưa có tệp âm thanh nào".
    public static func usageText(_ s: AudioHistorySummary) -> String {
        guard s.count > 0 else { return "Chưa có tệp âm thanh nào" }
        var text = "\(s.count) tệp · \(sizeText(bytes: s.bytes))"
        if s.budgetBytes > 0 { text += " / giới hạn \(sizeText(bytes: s.budgetBytes))" }
        return text
    }

    /// Xuất ZIP nạp CẢ gói vào RAM (`URLSession.data`): vượt ngưỡng này thì từ chối thay vì để máy
    /// hết RAM. Giảm giới hạn dung lượng hoặc xoá bớt rồi xuất lại.
    public static let maxExportBytes = 1024 * 1024 * 1024
}

/// Lỗi thật tiếng Việt cho từng tình huống của sheet "Dạy từ bằng giọng" (chưa có model, 429 bận,
/// 413 quá dài, thiếu quyền micro, engine chưa chạy) — `ErrorText.message` chung quá ngắn/không đúng
/// ngữ cảnh (vd. `payload_too_large` ở đó nói "tối đa 120 giây" trong khi dạy từ chỉ cho 10 giây).
public enum TeachErrorText {
    public static func message(_ error: ClientError) -> String {
        switch error {
        case .engine(let status, let code, let message):
            if code == "busy" || status == 429 {
                return "Engine đang bận xử lý một lượt khác — chờ vài giây rồi ghi lại."
            }
            if code == "too_long" || code == "payload_too_large" || status == 413 {
                return "Đoạn ghi quá dài (mỗi lần tối đa \(TeachWordVariants.maxSecondsPerAttempt) giây) — nói ngắn hơn hoặc bấm Dừng sớm hơn."
            }
            if code == "model_unavailable" {
                if let reason = ErrorText.reason(in: message) {
                    return "Chưa có model nhận dạng giọng nói (\(reason)) — chờ model tải xong hoặc xem tab Tổng quan, rồi thử lại."
                }
                return "Chưa có model nhận dạng giọng nói — chờ model tải xong hoặc xem tab Tổng quan, rồi thử lại."
            }
            if code == "bad_audio" { return "Âm thanh vừa ghi không hợp lệ — thử ghi lại." }
            return ErrorText.message(error)
        case .micDenied:
            return "Chưa cấp quyền Micro — mở Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Micro, bật vflow, rồi ghi lại."
        case .engineNotRunning, .network, .engineGaveUp:
            return "Engine chưa chạy hoặc không kết nối được — chờ engine khởi động (xem tab Tổng quan) rồi thử lại."
        default:
            return ErrorText.message(error)
        }
    }

    /// Thông báo khi engine nghe ra chuỗi rỗng (im lặng, hoặc chỉ ký hiệu) — không phải lỗi mạng.
    public static let nothingHeard = "Engine không nghe ra chữ nào — nói to và gần micro hơn rồi ghi lại."
}
