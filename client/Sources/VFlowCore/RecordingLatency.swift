import Foundation

/// Một lần đo "độ trễ bắt đầu ghi" (V3, item 3b): các mốc thời gian ĐƠN ĐIỆU (`CFAbsoluteTime`/
/// `ProcessInfo.systemUptime` — KHÔNG phải giờ tường, không lùi khi đổi múi giờ/đồng bộ NTP) từ lúc
/// nhấn phím tới khi có khung âm thanh đầu tiên. KHÔNG BAO GIỜ ghi đĩa, KHÔNG chứa nội dung giọng
/// nói — chỉ ba con số (giây), giữ TRONG RAM của phiên chạy hiện tại (xem `RecordingLatencyLog`).
public struct RecordingLatencySample: Equatable, Sendable {
    /// Lúc nhận sự kiện phím xuống (khởi động cử chỉ ghi).
    public var keyDownAt: TimeInterval
    /// Lúc gọi `AudioRecorder.start()` (có thể = `keyDownAt` khi đã prewarm, xem `AudioRecorder.prewarm`).
    public var recorderStartCalledAt: TimeInterval
    /// Lúc nhận được khối âm thanh ĐẦU TIÊN từ tap micro — `nil` nếu lượt ghi bị huỷ trước khi có
    /// âm thanh (vd. bấm đúp quá nhanh, hoặc engine chưa sẵn sàng).
    public var firstBufferReceivedAt: TimeInterval?

    public init(keyDownAt: TimeInterval, recorderStartCalledAt: TimeInterval, firstBufferReceivedAt: TimeInterval? = nil) {
        self.keyDownAt = keyDownAt
        self.recorderStartCalledAt = recorderStartCalledAt
        self.firstBufferReceivedAt = firstBufferReceivedAt
    }

    /// Giây từ nhấn phím tới khối âm thanh đầu tiên — mục tiêu chính cần giảm (A3). `nil` nếu chưa
    /// có khối âm thanh.
    public var keyDownToFirstBufferSeconds: TimeInterval? {
        guard let t = firstBufferReceivedAt else { return nil }
        return max(0, t - keyDownAt)
    }

    /// Giây từ nhấn phím tới lúc GỌI `recorder.start()` — phần "chờ phân biệt giữ/bấm đúp"/các bước
    /// khác TRƯỚC khi mã nguồn thật sự yêu cầu mở mic (0 khi đã prewarm và gọi ngay ở key_down).
    public var keyDownToRecorderStartSeconds: TimeInterval { max(0, recorderStartCalledAt - keyDownAt) }
}

/// Bộ nhớ trong-phiên các mẫu đo (vòng, giữ tối đa `capacity` mẫu gần nhất) + trung vị/lần gần
/// nhất — hiện ở Cài đặt › Nâng cao. KHÔNG ghi đĩa (xem `RecordingLatencySample`).
public struct RecordingLatencyLog: Sendable {
    public static let defaultCapacity = 50
    public let capacity: Int
    private var samples: [RecordingLatencySample] = []

    public init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { samples.count }

    public mutating func record(_ sample: RecordingLatencySample) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public var latest: RecordingLatencySample? { samples.last }

    /// Trung vị `keyDownToFirstBufferSeconds` trên các mẫu CÓ khối âm thanh đầu tiên (bỏ mẫu bị
    /// huỷ trước khi có âm thanh) — `nil` khi chưa có mẫu nào đủ dữ liệu (0 mẫu, không bịa số 0).
    public var medianKeyDownToFirstBufferSeconds: TimeInterval? {
        Self.median(samples.compactMap { $0.keyDownToFirstBufferSeconds })
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }
}

/// Định dạng hiện ở Cài đặt › Nâng cao — tiếng Việt, mili giây làm tròn, "—" khi chưa đủ dữ liệu
/// (KHÔNG hiện số 0 giả, khớp nguyên tắc truth-first chung của dự án).
public enum RecordingLatencyText {
    public static func summary(log: RecordingLatencyLog) -> String {
        guard log.count > 0 else { return "Chưa có lượt ghi nào trong phiên này" }
        let medianText = log.medianKeyDownToFirstBufferSeconds.map { "\(Int(($0 * 1000).rounded())) ms" } ?? "—"
        let latestText = log.latest?.keyDownToFirstBufferSeconds.map { "\(Int(($0 * 1000).rounded())) ms" } ?? "—"
        return "Trung vị \(medianText) · lần gần nhất \(latestText) · \(log.count) mẫu"
    }
}

/// Nơi gom các mẫu đo của PHIÊN HIỆN TẠI (chỉ trong RAM, không ghi đĩa) để Cài đặt › Nâng cao đọc.
/// An toàn đa luồng: mốc "khối âm thanh đầu tiên" đến từ luồng audio, mốc phím từ luồng chính.
///
/// Cách nối (AppController/AudioRecorder): `begin(keyDownAt:)` khi một cử chỉ ghi THẬT bắt đầu (kèm mốc
/// phím xuống của cử chỉ đó, xem `RecordingLatencyGesture`), `recorderStartCalled(at:)` ngay trước
/// `recorder.start()`, `firstBufferReceived(at:)` ở khối âm thanh đầu tiên (chỉ lần đầu của mỗi lượt
/// được tính), `cancel()` khi lượt bị huỷ/lỗi trước khi có âm thanh — lượt huỷ KHÔNG tạo mẫu (không
/// phải một lần đo độ trễ). Mọi mốc dùng `ProcessInfo.processInfo.systemUptime` (đơn điệu).
public final class RecordingLatencyStore: @unchecked Sendable {
    public static let shared = RecordingLatencyStore()
    /// Phát (trên luồng gọi `record`) sau mỗi mẫu mới để màn hình Cài đặt làm mới.
    public static let didRecord = Notification.Name("org.aios.vflow.recordingLatencyDidRecord")

    private let lock = NSLock()
    private var log: RecordingLatencyLog
    private var pendingKeyDownAt: TimeInterval?
    private var pendingRecorderStartAt: TimeInterval?

    public init(capacity: Int = RecordingLatencyLog.defaultCapacity) {
        log = RecordingLatencyLog(capacity: capacity)
    }

    public var snapshot: RecordingLatencyLog {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    public func record(_ sample: RecordingLatencySample) {
        lock.lock()
        log.record(sample)
        lock.unlock()
        NotificationCenter.default.post(name: Self.didRecord, object: nil)
    }

    /// Bắt đầu một lượt đo mới. Lượt trước còn dở (chưa có khối âm thanh) bị bỏ, không tạo mẫu.
    public func begin(keyDownAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        pendingKeyDownAt = keyDownAt
        pendingRecorderStartAt = nil
    }

    public func recorderStartCalled(at: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        guard pendingKeyDownAt != nil, pendingRecorderStartAt == nil else { return }
        pendingRecorderStartAt = at
    }

    /// Chỉ khối ĐẦU TIÊN của lượt đang đo có tác dụng; gọi khi không có lượt nào đang đo là vô hại.
    public func firstBufferReceived(at: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        guard let keyDownAt = pendingKeyDownAt else { lock.unlock(); return }
        let startAt = pendingRecorderStartAt ?? keyDownAt
        pendingKeyDownAt = nil
        pendingRecorderStartAt = nil
        lock.unlock()
        record(RecordingLatencySample(keyDownAt: keyDownAt, recorderStartCalledAt: startAt, firstBufferReceivedAt: at))
    }

    /// Lượt ghi bị huỷ/lỗi trước khi có âm thanh ⇒ bỏ lượt đang đo, KHÔNG tạo mẫu (không bịa số, không
    /// kéo trung vị). Không có lượt đang đo ⇒ vô hại.
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        pendingKeyDownAt = nil
        pendingRecorderStartAt = nil
    }
}

/// Mốc "phím xuống" của cử chỉ ghi hiện tại. Ghi âm chỉ BẮT ĐẦU sau cử chỉ (giữ ⌥ quá ngưỡng, đúp ⌥,
/// hoặc ⌥+⌃ cho Command Mode), nên mốc phím phải nhớ từ lúc phím xuống chứ không phải lúc máy trạng
/// thái ra lệnh bắt đầu. Quy tắc (khớp `HotkeyStateMachine`): ⌥ trái xuống khi máy rảnh ⇒ mốc mới (với
/// đúp ⌥ đó là lần chạm THỨ HAI vì lần đầu rảnh lại ngay); ⌃ trái xuống khi đang `armed`/`recording` ⇒
/// mốc mới (Command Mode tính từ ⌃). Mọi phím khác không đổi mốc. Command Mode ĐƯỢC đo (cùng đường ghi).
/// Thuần, test được với `HotkeyStateMachine` thật.
public struct RecordingLatencyGesture: Sendable {
    private var keyDownAt: TimeInterval?

    public init() {}

    /// Gọi TRƯỚC `machine.handle(input)` với `phase` hiện tại của máy.
    public mutating func observe(_ input: KeyInput, phase: HotkeyPhase, at now: TimeInterval) {
        switch (input, phase) {
        case (.leftOptionDown, .idle): keyDownAt = now
        case (.leftControlDown, .armed), (.leftControlDown, .recording): keyDownAt = now
        default: break
        }
    }

    /// Mốc phím xuống cho lệnh bắt đầu ghi vừa phát ra; dùng một lần (lượt kế tiếp phải có phím xuống mới).
    /// `nil` khi chưa từng thấy phím xuống (vd. tín hiệu giả lập) — người gọi dùng `now` thay thế.
    public mutating func consumeKeyDownAt() -> TimeInterval? {
        defer { keyDownAt = nil }
        return keyDownAt
    }
}
