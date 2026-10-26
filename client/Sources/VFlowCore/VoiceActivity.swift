import Foundation

/// Phát hiện tiếng nói theo mức năng lượng (VAD đơn giản), ngưỡng THÍCH NGHI theo nhiễu nền — dùng
/// để tự dừng ghi âm khi im lặng ở chế độ hands-free (xem contract mục 7b). THUẦN: chỉ nhận mức âm
/// đã tính sẵn (`AudioMath.level`, 0...1) theo từng khối, không đụng AVFoundation — test được bằng
/// PCM tổng hợp (xem `VoiceActivityTests`).
public struct VoiceActivityDetector: Sendable {
    /// Mức năng lượng nhiễu nền đang ước lượng (thích nghi chậm, chỉ khi KHÔNG có tiếng nói — tiếng
    /// nói không được kéo ngưỡng lên, nếu không sẽ không bao giờ phát hiện được im lặng sau đó).
    public private(set) var noiseFloor: Float
    /// Tổng thời gian im lặng LIÊN TỤC gần nhất (giây) — tiếng nói xuất hiện lại thì reset về 0, nên
    /// một khoảng ngưng ngắn giữa câu (ít hơn ngưỡng cấu hình) không bao giờ bị tính là "đủ để dừng".
    public private(set) var silenceSeconds: TimeInterval = 0
    /// Chỉ tính chuyện tự dừng SAU KHI đã nghe thấy tiếng nói ít nhất một lần trong lượt ghi này —
    /// tránh tự dừng ngay vì vài trăm ms đầu im lặng trước khi người dùng kịp nói.
    public private(set) var hasDetectedVoice = false

    /// Mức vượt quá nhiễu nền bao nhiêu mới coi là "có tiếng nói".
    private let voiceMargin: Float
    /// Tốc độ thích nghi khi đang coi là CÓ tiếng nói — CHẬM, để nói liên tục/dài không tự kéo
    /// ngưỡng lên rồi lại bị hiểu nhầm thành im lặng giữa câu.
    private let adaptRateWhileVoice: Float
    /// Tốc độ thích nghi khi đang coi là im lặng — NHANH hơn, để bắt kịp nhiễu nền thật nhanh.
    private let adaptRateWhileSilence: Float

    public init(initialNoiseFloor: Float = 0.05, voiceMargin: Float = 0.12,
                adaptRateWhileVoice: Float = 0.05, adaptRateWhileSilence: Float = 0.2) {
        self.noiseFloor = max(0, min(initialNoiseFloor, 1))
        self.voiceMargin = voiceMargin
        self.adaptRateWhileVoice = adaptRateWhileVoice
        self.adaptRateWhileSilence = adaptRateWhileSilence
    }

    /// Ngưỡng hiện tại (nhiễu nền + biên) — public để hiện/kiểm tra, không dùng nội bộ nơi khác.
    public var threshold: Float { noiseFloor + voiceMargin }

    /// Đưa một khối mức âm (0...1) vào, trả `true` nếu khối NÀY được coi là có tiếng nói. Nhiễu nền
    /// LUÔN được thích nghi (không chỉ lúc im lặng) — nếu không, một lần đoán sai ban đầu (ngưỡng
    /// thấp hơn nhiễu nền thật) sẽ mãi mãi coi nhiễu là tiếng nói (không bao giờ vào nhánh thích
    /// nghi) và không bao giờ tự sửa được; chỉ tốc độ thích nghi khác nhau giữa hai trạng thái.
    @discardableResult
    public mutating func process(level: Float, chunkSeconds: TimeInterval) -> Bool {
        let clamped = max(0, min(level, 1))
        let isVoice = clamped > threshold
        let rate = isVoice ? adaptRateWhileVoice : adaptRateWhileSilence
        noiseFloor += (clamped - noiseFloor) * rate
        noiseFloor = max(0, min(noiseFloor, 0.9))
        if isVoice {
            hasDetectedVoice = true
            silenceSeconds = 0
        } else {
            silenceSeconds += max(0, chunkSeconds)
        }
        return isVoice
    }

    /// Có nên tự dừng ngay bây giờ không. `limitSeconds` = cài đặt `silence_stop_seconds`; `0` =
    /// tắt hẳn (không bao giờ tự dừng, dùng cho README mục "0 = tắt").
    public func shouldStop(afterSilenceSeconds limitSeconds: Double) -> Bool {
        guard limitSeconds > 0, hasDetectedVoice else { return false }
        return silenceSeconds >= limitSeconds
    }

    /// Giây còn lại trước khi tự dừng — dùng cho đếm ngược HUD; `nil` = không áp dụng (tắt, chưa
    /// nghe tiếng nói, hoặc chưa bắt đầu im lặng).
    public func secondsUntilStop(limitSeconds: Double) -> Double? {
        guard limitSeconds > 0, hasDetectedVoice, silenceSeconds > 0 else { return nil }
        return max(0, limitSeconds - silenceSeconds)
    }
}

/// Chọn micro: thiết bị đã cấu hình (lưu theo UID) nếu còn tồn tại, rơi về "mặc định hệ thống" nếu
/// biến mất — THUẦN, test bằng danh sách thiết bị giả (xem contract mục 7a).
public enum MicrophoneSelection {
    public struct Device: Equatable, Sendable {
        public var uid: String
        public var name: String
        public init(uid: String, name: String) {
            self.uid = uid
            self.name = name
        }
    }

    public enum Resolved: Equatable, Sendable {
        /// Dùng đúng thiết bị đã chọn.
        case configured(Device)
        /// Mặc định hệ thống (do người dùng chọn, hoặc chưa chọn gì).
        case systemDefault
        /// Thiết bị đã chọn KHÔNG còn trong danh sách ⇒ rơi về mặc định, cần báo HUD một lần.
        case fallbackDeviceMissing(previousUID: String)
    }

    /// `configuredUID` nil = người dùng chọn "Mặc định hệ thống" (không phải lỗi).
    public static func resolve(configuredUID: String?, availableDevices: [Device]) -> Resolved {
        guard let uid = configuredUID else { return .systemDefault }
        if let device = availableDevices.first(where: { $0.uid == uid }) { return .configured(device) }
        return .fallbackDeviceMissing(previousUID: uid)
    }
}

/// Giới hạn ghi âm hands-free: `max_audio_seconds` từ `/healthz` nếu engine có báo, trong khoảng an
/// toàn [`defaultSeconds`, `maxAllowedSeconds`]; vắng mặt (contract hiện chưa có) ⇒ dùng
/// `defaultSeconds` (không suy đoán, xem contract mục 7c).
public enum RecordingLimit {
    public static let defaultSeconds = 120
    public static let maxAllowedSeconds = 1200
    /// Hiện cảnh báo "còn N giây" khi còn đúng ngần này.
    public static let warnAtRemainingSeconds = 30

    public static func resolve(engineMaxAudioSeconds: Int?) -> Int {
        guard let v = engineMaxAudioSeconds, v > 0 else { return defaultSeconds }
        return max(defaultSeconds, min(v, maxAllowedSeconds))
    }
}
