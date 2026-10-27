import Foundation

/// Mọi đường thoát mà một `audio_id` KHÔNG được gắn vào mục lịch sử nào (Lịch sử tắt, Command Mode,
/// ghi lịch sử lỗi, người dùng huỷ giữa chừng…) đều phải xoá bản ghi âm đó phía engine — nếu không
/// nó thành tệp mồ côi: không còn nút nghe lại, không ai xoá được ngoài "Xoá toàn bộ âm thanh".
/// Xoá là BEST-EFFORT: lỗi (engine chết, 404) không bao giờ chặn luồng dictation.
public enum AudioDisposal {
    /// Gọi `delete` đúng một lần với `audioId` (nếu có). Trả `true` ⇔ đã gọi và `delete` báo thành công;
    /// `false` ⇔ không có id để xoá hoặc `delete` thất bại — người gọi bỏ qua kết quả.
    @discardableResult
    public static func discard(audioId: String?, delete: @Sendable (String) async -> Bool) async -> Bool {
        guard let audioId, !audioId.isEmpty else { return false }
        return await delete(audioId)
    }
}

/// Giữ bất biến "Lịch sử tắt ⇒ engine `audio_history=false`" NGAY khi công tắc Lịch sử đổi, không phụ
/// thuộc tab Cài đặt › Dữ liệu có đang mở hay không (tab đó chỉ sửa thêm khi mở). `send` gửi
/// `PUT /v1/settings` thật; tiêm vào để test được không cần mạng.
public struct AudioHistoryEnforcer: Sendable {
    public typealias Send = @Sendable (SettingsPatch) async -> Result<AppSettings, ClientError>
    private let send: Send

    public init(send: @escaping Send) { self.send = send }

    /// Công tắc "Lưu lịch sử" vừa đổi thành `enabled`. Tắt ⇒ gửi `audio_history=false` (idempotent —
    /// không cần biết engine đang giữ giá trị nào). Bật ⇒ KHÔNG gửi gì: bật lại Lịch sử không bao giờ
    /// tự bật lưu âm thanh. Trả lỗi thật nếu gửi thất bại (engine chưa chạy…) để người gọi quyết định.
    @discardableResult
    public func historyEnabledChanged(to enabled: Bool) async -> Result<Void, ClientError> {
        guard let patch = AudioHistoryPolicy.reconcilePatch(historyEnabled: enabled, engineAudioHistory: true) else {
            return .success(())
        }
        switch await send(patch) {
        case .success: return .success(())
        case .failure(let e): return .failure(e)
        }
    }
}

public extension HistoryGate {
    /// Kết quả của một lần đọc chính tả có thể mang `audio_id`: có ghi mục lịch sử không, và bản ghi
    /// âm nào phải xoá vì KHÔNG có mục nào trỏ tới nó.
    struct Decision: Equatable, Sendable {
        public var record: Bool
        public var discardAudioId: String?
    }

    /// `entryCarriesAudio`: mục lịch sử sẽ ghi có lưu `audio_id` không — dictation thường có, Command
    /// Mode KHÔNG (mục chỉ lưu lệnh và kết quả), nên âm thanh của lệnh luôn phải xoá.
    static func decide(enabled: Bool, insertedText: String?, audioId: String?, entryCarriesAudio: Bool = true) -> Decision {
        let record = shouldRecord(enabled: enabled, insertedText: insertedText)
        let kept = record && entryCarriesAudio
        return Decision(record: record, discardAudioId: kept ? nil : audioId)
    }
}
