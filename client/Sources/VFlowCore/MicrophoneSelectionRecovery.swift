import Foundation

// Khôi phục micro giữa lượt ghi (Q2). BẰNG CHỨNG ĐO THẬT (macOS 26.6, tai nghe Bluetooth là mặc định):
// `AVAudioEngineConfigurationChange` bắn ~0,2–0,4 s sau `engine.start()` bình thường VÀ khi đó
// engine ĐÃ TỰ DỪNG (`isRunning == false`, 0 khung âm thanh) — nên (a) coi nó là lỗi chí mạng làm huỷ
// lượt ghi oan; (b) chỉ "bỏ qua" cũng sai: engine chết thật, câu nói ra file rỗng. Việc đúng: kiểm
// TRẠNG THÁI THẬT (engine chạy? định dạng dùng được? khung còn tới?), chết thì dựng lại ÊM và giữ
// nguyên mọi mẫu đã thu. Logic thuần này test được bằng backend giả; AVAudioEngine nằm ở `AudioRecorder`.

/// Định dạng đầu vào hiện tại của micro.
public struct MicInputFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var channels: Int
    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
    }
    /// 0 Hz/0 kênh (thiết bị biến mất, tuyến âm thanh đang đổi) hoặc tần số vô lý ⇒ không ghi được.
    public var isUsable: Bool { sampleRate >= 8000 && channels > 0 }
}

public enum MicRecoveryPolicy {
    /// Engine báo chạy + định dạng tốt mà không có khung mới quá ngần này ⇒ coi là đứng (ms).
    public static let stallMs: Double = 1500
    /// Chưa có khung ĐẦU TIÊN sau ngần này kể từ lúc bắt đầu ⇒ dựng lại (ms). Đo thật: khung đầu của micro
    /// thường tới sau ~0,2–0,7 s; chờ lâu hơn nữa thì người nói đã nói xong trong im lặng (rẻ hơn nhiều khi
    /// dựng lại oan một micro chỉ chậm — micro Continuity/iPhone chậm ~4 s vẫn ra khung sau khi dựng lại).
    public static let noFirstFrameMs: Double = 3000
    /// Sau thông báo cấu hình mà engine vẫn "chạy": chờ ngần này (ms) xem có khung MỚI không.
    public static let verifyAfterChangeMs = 700
    /// Sau mỗi lần dựng lại: chờ tối đa ngần này (ms) cho một khung mới trước khi coi là thất bại.
    public static let frameWaitAfterRestartMs = 800
    public static let framePollMs = 50
    /// Đã thu ≥ ngần này giây thì GỬI ĐI khi micro chết hẳn, không vứt câu nói.
    public static let minimumUsefulSeconds: Double = 0.5
    /// Trần số lần khôi phục trong MỘT lượt (chống vòng lặp vô tận khi tuyến âm thanh nhấp nháy).
    public static let maxRecoveriesPerRecording = 6

    public struct InputState: Equatable, Sendable {
        public var engineRunning: Bool
        public var format: MicInputFormat
        /// Mili giây kể từ khung cuối; nil = chưa nhận khung nào trong lượt.
        public var msSinceLastFrame: Double?
        public var msSinceStart: Double
        public init(engineRunning: Bool, format: MicInputFormat, msSinceLastFrame: Double?, msSinceStart: Double) {
            self.engineRunning = engineRunning
            self.format = format
            self.msSinceLastFrame = msSinceLastFrame
            self.msSinceStart = msSinceStart
        }
    }

    public enum Reason: Equatable, Sendable {
        case formatInvalid, engineStopped, noFirstFrame, stalled
    }

    public enum Decision: Equatable, Sendable {
        case ignore
        case recover(Reason)
    }

    /// Quyết định theo TRẠNG THÁI THẬT, không theo thời gian "giai đoạn khởi động": thông báo cấu hình
    /// lúc khởi động mà engine vẫn chạy + đang nhận khung ⇒ bỏ qua; engine đã chết ⇒ dựng lại dù đang ở đâu.
    public static func decide(_ s: InputState) -> Decision {
        guard s.format.isUsable else { return .recover(.formatInvalid) }
        guard s.engineRunning else { return .recover(.engineStopped) }
        guard let since = s.msSinceLastFrame else {
            return s.msSinceStart > noFirstFrameMs ? .recover(.noFirstFrame) : .ignore
        }
        return since > stallMs ? .recover(.stalled) : .ignore
    }

    public enum Step: Equatable, Sendable {
        /// Dừng, cấu hình lại tap theo định dạng mới và `start()` lại CÙNG engine.
        case restartSameEngine
        /// Dựng `AVAudioEngine` mới. `pinUID` = ghim thiết bị đã chọn; nil = mặc định hệ thống.
        case rebuild(pinUID: String?)
    }

    /// Thứ tự thử + độ trễ trước mỗi bước (ms). Có thiết bị đã chọn: thử lại nó trước, rồi mới rơi về
    /// mặc định hệ thống. Bước cuối chờ lâu hơn vì đổi tuyến Bluetooth (HFP) mất cỡ 1–2 giây.
    public static func steps(chosenUID: String?) -> [(step: Step, delayMs: Int)] {
        var out: [(Step, Int)] = [(.restartSameEngine, 0)]
        if let uid = chosenUID { out.append((.rebuild(pinUID: uid), 350)) }
        out.append((.rebuild(pinUID: nil), chosenUID == nil ? 350 : 900))
        out.append((.rebuild(pinUID: nil), 1800))
        return out
    }

    public enum Outcome: Equatable, Sendable {
        /// Đã có đủ âm thanh: gửi đi, HUD nhắc ngắn (KHÔNG phải lỗi đỏ).
        case sendCollected(notice: String)
        /// Không có gì để gửi: lỗi đỏ với đúng nguyên nhân.
        case error(message: String)
    }

    /// Khi khôi phục thất bại. `neverStarted`: chưa từng nhận khung nào (mở micro thất bại ngay từ đầu).
    public static func outcome(collectedSeconds: Double, deviceName: String?, neverStarted: Bool, detail: String? = nil) -> Outcome {
        if collectedSeconds >= minimumUsefulSeconds {
            return .sendCollected(notice: "Micro bị ngắt giữa chừng — đã gửi phần ghi được")
        }
        let name = deviceName.map { " (\($0))" } ?? ""
        let extra = detail.map { ": \($0)" } ?? ""
        if neverStarted { return .error(message: "không mở được micro\(name)\(extra)") }
        return .error(message: "micro bị ngắt giữa chừng\(name)\(extra)")
    }

    /// Thiết bị đã chọn không còn ⇒ nhắc nhẹ (không phải lỗi).
    public static let deviceMissingNotice = "Micro đã chọn không còn — dùng micro mặc định"
}

/// Cầu nối tới engine âm thanh thật (hoặc bản giả trong test). Mọi thứ chạy trên luồng chính.
@MainActor
public protocol MicBackend: AnyObject {
    var isEngineRunning: Bool { get }
    var inputFormat: MicInputFormat { get }
    /// Mốc `systemUptime` của khung cuối nhận được trong lượt này; nil nếu chưa có.
    var lastFrameUptime: TimeInterval? { get }
    var uptime: TimeInterval { get }
    /// true = đã `start()` lại được với định dạng dùng được. KHÔNG xoá mẫu đã thu.
    func restartSameEngine() -> Bool
    /// true = engine mới đã chạy. `pinUID` != nil mà ghim thất bại ⇒ false (để rơi về bước mặc định
    /// và báo đúng việc "thiết bị đã chọn không còn").
    func rebuildEngine(pinUID: String?) -> Bool
}

/// Giám sát một lượt ghi: nhận thông báo cấu hình + nhịp kiểm tra định kỳ, quyết định bỏ qua hay khôi phục.
/// KHÔNG BAO GIỜ huỷ lượt vì một thông báo; chỉ báo `.failed` sau khi mọi bước khôi phục đều hỏng.
@MainActor
public final class MicRecoverySession {
    public enum Event: Equatable, Sendable {
        /// Ghi tiếp được. `fellBackFromUID` != nil ⇒ thiết bị đã chọn không dùng lại được, đã rơi về mặc định.
        case recovered(fellBackFromUID: String?)
        case failed(reason: String)
    }

    private let backend: MicBackend
    private var chosenUID: String?
    private let startedAt: TimeInterval
    private let sleepMs: @Sendable (Int) async -> Void
    private let onEvent: (Event) -> Void
    private var generation = 0
    private var cancelled = false
    private var verifyTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    public private(set) var isRecovering = false
    public private(set) var recoveryCount = 0

    public init(backend: MicBackend, chosenUID: String?, startedAtUptime: TimeInterval,
                sleepMs: @escaping @Sendable (Int) async -> Void = { ms in try? await Task.sleep(for: .milliseconds(ms)) },
                onEvent: @escaping (Event) -> Void) {
        self.backend = backend
        self.chosenUID = chosenUID
        self.startedAt = startedAtUptime
        self.sleepMs = sleepMs
        self.onEvent = onEvent
    }

    public func cancel() {
        cancelled = true
        generation += 1
        verifyTask?.cancel(); verifyTask = nil
        task?.cancel(); task = nil
        isRecovering = false
    }

    private func currentState() -> MicRecoveryPolicy.InputState {
        let t = backend.uptime
        return .init(engineRunning: backend.isEngineRunning, format: backend.inputFormat,
                     msSinceLastFrame: backend.lastFrameUptime.map { max(0, (t - $0) * 1000) },
                     msSinceStart: max(0, (t - startedAt) * 1000))
    }

    /// `AVAudioEngineConfigurationChange`: KHÔNG phải lỗi. Kiểm trạng thái thật.
    public func configurationChanged() {
        guard !cancelled, !isRecovering else { return }
        if case .recover = MicRecoveryPolicy.decide(currentState()) {
            beginRecovery()
            return
        }
        // Engine vẫn báo chạy + khung còn tới: bỏ qua, nhưng xác nhận lại sau một lúc (engine có thể
        // đã tự dừng ngay sau thông báo). Không có khung MỚI nào kể từ thông báo ⇒ dựng lại.
        let notifiedAt = backend.uptime
        verifyTask?.cancel()
        verifyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sleepMs(MicRecoveryPolicy.verifyAfterChangeMs)
            guard !Task.isCancelled, !self.cancelled, !self.isRecovering else { return }
            if let last = self.backend.lastFrameUptime, last >= notifiedAt { return }
            // Không có khung MỚI nào kể từ thông báo (dù engine báo chạy/định dạng tốt) ⇒ dựng lại. Dựng
            // lại một engine khoẻ chỉ tốn một khoảng hở vài chục ms, còn bỏ sót một engine chết thì mất cả câu.
            self.beginRecovery()
        }
    }

    /// Nhịp kiểm tra định kỳ (đầu vào mất mà không có thông báo: rút thiết bị, ngủ/thức…).
    public func watchdogTick() {
        guard !cancelled, !isRecovering else { return }
        if case .recover = MicRecoveryPolicy.decide(currentState()) { beginRecovery() }
    }

    /// Mở micro thất bại ngay từ đầu (định dạng 0 Hz khi đang đổi tuyến, `engine.start()` ném lỗi):
    /// thử khôi phục thay vì báo đỏ ngay.
    public func recoverAfterStartFailure() {
        guard !cancelled, !isRecovering else { return }
        beginRecovery()
    }

    private func beginRecovery() {
        guard !cancelled, !isRecovering else { return }
        guard recoveryCount < MicRecoveryPolicy.maxRecoveriesPerRecording else {
            onEvent(.failed(reason: "micro liên tục bị ngắt"))
            return
        }
        recoveryCount += 1
        isRecovering = true
        generation += 1
        let gen = generation
        verifyTask?.cancel(); verifyTask = nil
        task = Task { @MainActor [weak self] in await self?.runSteps(generation: gen) }
    }

    private func alive(_ gen: Int) -> Bool { !cancelled && generation == gen && !Task.isCancelled }

    private func runSteps(generation gen: Int) async {
        let originalChosen = chosenUID
        for (step, delayMs) in MicRecoveryPolicy.steps(chosenUID: originalChosen) {
            if delayMs > 0 { await sleepMs(delayMs) }
            guard alive(gen) else { return }
            let started: Bool
            switch step {
            case .restartSameEngine: started = backend.restartSameEngine()
            case .rebuild(let uid): started = backend.rebuildEngine(pinUID: uid)
            }
            guard alive(gen) else { return }
            guard started else { continue }
            let since = backend.uptime
            if await waitForFrame(since: since, generation: gen) {
                guard alive(gen) else { return }
                isRecovering = false
                var fell: String?
                if case .rebuild(let uid) = step, uid == nil, let c = originalChosen { fell = c; chosenUID = nil }
                onEvent(.recovered(fellBackFromUID: fell))
                return
            }
            guard alive(gen) else { return }
        }
        guard alive(gen) else { return }
        isRecovering = false
        onEvent(.failed(reason: "không khôi phục được micro"))
    }

    private func waitForFrame(since: TimeInterval, generation gen: Int) async -> Bool {
        let polls = max(1, MicRecoveryPolicy.frameWaitAfterRestartMs / MicRecoveryPolicy.framePollMs)
        for _ in 0..<polls {
            if let f = backend.lastFrameUptime, f >= since { return true }
            await sleepMs(MicRecoveryPolicy.framePollMs)
            guard alive(gen) else { return false }
        }
        if let f = backend.lastFrameUptime, f >= since { return true }
        return false
    }
}

/// Bộ đệm PCM 16 kHz của một lượt ghi: giữ nguyên mọi mẫu đã thu kể cả khi tần số đầu vào đổi giữa chừng
/// (đổi tuyến Bluetooth 48 kHz ↔ 16 kHz): xả phần đuôi bộ chuyển cũ rồi dùng bộ mới. Chỉ trong RAM.
public final class RecordingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var converter: PCM16Converter?

    public init(reserveSeconds: Int = 30) {
        samples.reserveCapacity(PCM16Converter.targetRate * reserveSeconds)
    }

    /// Thêm một khối mono Float ở tần số `inputRate`.
    public func append(mono: [Float], inputRate: Int) {
        guard inputRate > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if converter?.inputRate != inputRate {
            if let tail = converter?.finish() { samples.append(contentsOf: tail) }
            converter = PCM16Converter(inputRate: inputRate)
        }
        if let out = converter?.process(mono) { samples.append(contentsOf: out) }
    }

    /// Số giây (16 kHz) đã thu được tới lúc này.
    public var seconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(samples.count) / Double(PCM16Converter.targetRate)
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return samples.isEmpty
    }

    /// Ảnh chụp PCM LE đã thu, không dừng/không mất mẫu.
    public func snapshotData() -> Data {
        lock.lock(); defer { lock.unlock() }
        return AudioMath.littleEndianData(samples)
    }

    /// Kết thúc lượt: xả đuôi bộ chuyển, trả PCM LE rồi xoá.
    public func finish() -> Data {
        lock.lock(); defer { lock.unlock() }
        if let tail = converter?.finish() { samples.append(contentsOf: tail) }
        let data = AudioMath.littleEndianData(samples)
        samples = []
        converter = nil
        return data
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        samples = []
        converter = nil
    }
}
