import AVFoundation
import CoreAudio
import VFlowCore

/// Ghi micro bằng AVAudioEngine, đổi sang 16 kHz mono Int16 ngay trong RAM. Không bao giờ ghi đĩa.
///
/// KHÔNG BAO GIỜ huỷ lượt ghi vì một thông báo cấu hình (Q2). `AVAudioEngineConfigurationChange` bắn rất
/// thường và, đo thật, khi bắn thì engine ĐÃ TỰ DỪNG: nên mỗi thông báo/nhịp kiểm tra đều đi qua
/// `VFlowCore.MicRecoverySession` (kiểm trạng thái thật, dựng lại êm, giữ nguyên mẫu đã thu) —
/// chỉ khi mọi bước khôi phục đều hỏng mới báo `.failed` cho `AppController` quyết định gửi/báo lỗi.
final class AudioRecorder: @unchecked Sendable {
    enum Event: Sendable {
        /// Đã khôi phục, ghi tiếp. `fellBackFromUID` != nil ⇒ micro đã chọn không dùng lại được, đã rơi về mặc định hệ thống.
        case recovered(fellBackFromUID: String?)
        /// Khôi phục thất bại. `neverStarted`: chưa từng nhận khung âm thanh nào trong lượt.
        case failed(detail: String, deviceName: String?, collectedSeconds: Double, neverStarted: Bool)
    }

    private let queue = DispatchQueue(label: "org.aios.vflow.audio")
    private var engine: AVAudioEngine?
    private let buffer = RecordingBuffer()
    private var configObserver: NSObjectProtocol?
    private var session: MicRecoverySession?
    private var watchdog: Timer?
    private var deviceName: String?
    private let frameClock = FrameClock()
    /// Mức âm 0…1 (gọi trên luồng chính).
    var onLevel: (@MainActor (Float) -> Void)?
    /// Sự kiện khôi phục/thất bại giữa lượt (gọi trên luồng chính).
    var onEvent: (@MainActor (Event) -> Void)?
    /// Chỉ bắn khi khôi phục THẤT BẠI hẳn (không còn thu được nữa), kèm thông điệp đúng nguyên nhân.
    /// Dùng cho nơi chỉ cần "đã hỏng" (sheet Dạy từ); `AppController` dùng `onEvent` để quyết định gửi/báo lỗi.
    var onInterrupted: (@MainActor (String) -> Void)?
    /// Gọi MỘT lần cho mỗi lần `start()` khi khung âm thanh ĐẦU TIÊN của lượt đó tới tap (mốc đơn điệu
    /// `systemUptime` lấy ngay đầu callback tap) — dùng đo độ trễ bắt đầu ghi (`RecordingLatencyStore`).
    /// Đặt MỘT lần trước khi ghi; không đặt (vd. sheet Dạy từ) thì không đo. Khung đến muộn của một
    /// lượt đã `stop()`/`cancel()` bị `FirstBufferGate` chặn, không lọt vào lượt kế tiếp.
    var onFirstBuffer: (@Sendable (TimeInterval) -> Void)?
    private var firstBufferGate: FirstBufferGate?

    private final class FirstBufferGate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true
        func fireOnce() -> Bool { lock.lock(); defer { lock.unlock() }; guard open else { return false }; open = false; return true }
        func invalidate() { lock.lock(); open = false; lock.unlock() }
    }

    /// Mốc khung cuối nhận được (ghi từ luồng audio, đọc từ luồng chính).
    private final class FrameClock: @unchecked Sendable {
        private let lock = NSLock()
        private var last: TimeInterval?
        var lastFrame: TimeInterval? { lock.lock(); defer { lock.unlock() }; return last }
        func mark(_ t: TimeInterval) { lock.lock(); last = t; lock.unlock() }
        func reset() { lock.lock(); last = nil; lock.unlock() }
    }

    static func permission() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    /// Danh sách micro thật (Cài đặt › Chung) — `AVCaptureDevice.DiscoverySession`, không cần quyền
    /// Micro để CHỈ liệt kê (tên/UID), chỉ cần quyền để ghi thật.
    static func availableDevices() -> [MicrophoneSelection.Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { MicrophoneSelection.Device(uid: $0.uniqueID, name: $0.localizedName) }
    }

    /// Số giây (16 kHz) đã thu được tới lúc này.
    var collectedSeconds: Double { queue.sync { buffer.seconds } }

    /// `deviceUID` nil = mặc định hệ thống (hành vi CŨ, không đổi gì — xem `MicrophoneSelection`).
    /// Có UID ⇒ cố gắng ghim micro đó vào `AVAudioEngine` bằng CoreAudio TRƯỚC khi đọc định dạng vào;
    /// không tìm được thiết bị/ghim lỗi ⇒ bỏ qua ÊM, dùng mặc định hệ thống (không chặn ghi âm vì lỗi
    /// chọn thiết bị — xem contract mục 7a).
    ///
    /// Mở micro thất bại ngay từ đầu (định dạng 0 Hz khi hệ thống đang đổi tuyến âm thanh, `engine.start()`
    /// ném lỗi tạm thời): nếu hệ thống CÓ micro mặc định thì KHÔNG báo đỏ ngay mà đi vào khôi phục êm;
    /// chỉ khi máy hoàn toàn không có thiết bị vào mới ném lỗi tại chỗ.
    @MainActor
    func start(deviceUID: String? = nil) throws {
        teardown() // dọn dấu vết lượt trước (nếu có)
        queue.sync { buffer.clear() }
        frameClock.reset()
        firstBufferGate?.invalidate()
        let gate = FirstBufferGate()
        firstBufferGate = gate
        deviceName = Self.deviceName(forUID: deviceUID)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let launched = launch(pinUID: deviceUID, requirePin: false)
        let s = MicRecoverySession(backend: self, chosenUID: deviceUID, startedAtUptime: startedAt) { [weak self] event in
            MainActor.assumeIsolated { self?.sessionEvent(event) }
        }
        session = s
        if case .failed(let why) = launched {
            guard AVCaptureDevice.default(for: .audio) != nil else {
                s.cancel(); session = nil
                firstBufferGate?.invalidate()
                throw ClientError.micUnavailable("không có thiết bị vào (\(why))")
            }
            s.recoverAfterStartFailure()
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak s] _ in
            MainActor.assumeIsolated { s?.watchdogTick() }
        }
    }

    private enum Launch { case started, failed(String) }

    /// Dựng engine mới (đã thay engine cũ nếu có), nối tap, `start()`. Không đụng vào mẫu đã thu.
    @MainActor
    private func launch(pinUID: String?, requirePin: Bool) -> Launch {
        discardEngine()
        let e = AVAudioEngine() // mới mỗi lần: theo kịp đổi thiết bị
        if let uid = pinUID {
            let pinned = Self.setPreferredInputDevice(uid: uid, on: e)
            if requirePin && !pinned { return .failed("không ghim được micro đã chọn") }
        }
        guard installTap(on: e) else {
            let f = e.inputNode.outputFormat(forBus: 0)
            return .failed("định dạng \(f.sampleRate) Hz, \(f.channelCount) kênh")
        }
        e.prepare()
        do {
            try e.start()
        } catch {
            e.inputNode.removeTap(onBus: 0)
            return .failed(error.localizedDescription)
        }
        engine = e
        observeConfigurationChange(of: e)
        return .started
    }

    /// Nối tap theo định dạng HIỆN TẠI của đầu vào; false nếu định dạng chưa dùng được.
    @MainActor
    private func installTap(on e: AVAudioEngine) -> Bool {
        let input = e.inputNode
        let format = input.outputFormat(forBus: 0)
        guard MicInputFormat(sampleRate: format.sampleRate, channels: Int(format.channelCount)).isUsable else { return false }
        input.removeTap(onBus: 0)
        let gate = firstBufferGate
        // format: nil = dùng đúng định dạng hiện tại của nút vào. TUYỆT ĐỐI không truyền định dạng đọc từ
        // trước: nếu tuyến âm thanh vừa đổi (Bluetooth 16 kHz ↔ 48 kHz) thì `installTap` ném NSException
        // "Failed to create tap due to format mismatch" — Swift không bắt được, app sẽ sập (đo thật khi thử khôi phục).
        // @Sendable: chạy trên LUỒNG ÂM THANH, không được kế thừa @MainActor của hàm bao quanh.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { @Sendable [weak self] buffer, _ in
            let arrivedAt = ProcessInfo.processInfo.systemUptime
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let chans = Int(buffer.format.channelCount)
            var planar: [[Float]] = []
            planar.reserveCapacity(chans)
            for c in 0..<chans { planar.append(Array(UnsafeBufferPointer(start: data[c], count: n))) }
            let mono = AudioMath.downmix(planar: planar)
            let level = AudioMath.level(mono)
            let rate = Int(buffer.format.sampleRate.rounded())
            self.frameClock.mark(arrivedAt)
            self.queue.async {
                self.buffer.append(mono: mono, inputRate: rate) // đổi tần số giữa chừng: giữ nguyên mẫu cũ
                if let gate, gate.fireOnce() { self.onFirstBuffer?(arrivedAt) }
            }
            Task { @MainActor in self.onLevel?(level) }
        }
        return true
    }

    @MainActor
    private func observeConfigurationChange(of e: AVAudioEngine) {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in
            // KHÔNG phải lỗi: kiểm trạng thái thật rồi mới quyết định (xem `MicRecoverySession`).
            MainActor.assumeIsolated { self?.session?.configurationChanged() }
        }
    }

    /// Dừng + gỡ engine hiện tại (không đụng mẫu đã thu).
    @MainActor
    private func discardEngine() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
        guard let e = engine else { return }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        engine = nil
        queue.sync {} // hàng đợi xử lý xong các khối đã nhận trước khi đổi engine
    }

    @MainActor
    private func sessionEvent(_ event: MicRecoverySession.Event) {
        switch event {
        case .recovered(let fell):
            if fell != nil { deviceName = Self.deviceName(forUID: nil) }
            onEvent?(.recovered(fellBackFromUID: fell))
        case .failed(let detail):
            session?.cancel() // một lần thất bại là đủ, không bắn lặp
            let secs = collectedSeconds
            let neverStarted = frameClock.lastFrame == nil && secs == 0
            onEvent?(.failed(detail: detail, deviceName: deviceName, collectedSeconds: secs, neverStarted: neverStarted))
            // Người dùng khác (sheet Dạy từ) chỉ cần biết "đã hỏng hẳn" + thông điệp đúng nguyên nhân.
            if case .error(let message) = MicRecoveryPolicy.outcome(collectedSeconds: 0, deviceName: deviceName, neverStarted: neverStarted, detail: detail) {
                onInterrupted?(message)
            }
        }
    }

    /// Chụp nhanh PCM 16 kHz LE đã ghi ĐƯỢC TỚI LÚC NÀY mà KHÔNG dừng ghi — dùng cho "Xem chữ chạy
    /// trực tiếp" (`POST /v1/partial`, gọi mỗi ~1 giây trong lúc vẫn đang ghi). An toàn gọi nhiều
    /// lần; không xoá/làm mất mẫu nào (khác `stop()`).
    func snapshotPCM() -> Data {
        queue.sync { buffer.snapshotData() }
    }

    /// Dừng và trả PCM 16 kHz LE.
    @MainActor
    func stop() -> Data {
        teardown()
        return queue.sync { buffer.finish() }
    }

    /// Huỷ: bỏ toàn bộ âm thanh.
    @MainActor
    func cancel() {
        teardown()
        queue.sync { buffer.clear() }
    }

    @MainActor
    private func teardown() {
        watchdog?.invalidate()
        watchdog = nil
        session?.cancel()
        session = nil
        firstBufferGate?.invalidate() // khung muộn của lượt này không được tính cho lượt sau
        firstBufferGate = nil
        discardEngine()
        // Hàng đợi xử lý xong các khối đã nhận trước khi đọc kết quả.
        queue.sync {}
    }

    /// Tên hiển thị của micro (để thông điệp lỗi nói đúng thiết bị); nil nếu không biết.
    private static func deviceName(forUID uid: String?) -> String? {
        if let uid, let d = AVCaptureDevice(uniqueID: uid) { return d.localizedName }
        return AVCaptureDevice.default(for: .audio)?.localizedName
    }

    /// Ghim `engine.inputNode` vào đúng `AudioDeviceID` của `uid` qua CoreAudio
    /// (`kAudioOutputUnitProperty_CurrentDevice`) — PHẢI gọi trước khi đọc `outputFormat`/tạo tap.
    /// Trả false nếu không tìm được thiết bị hoặc ghim lỗi (người gọi quyết định có coi là thất bại không).
    @discardableResult
    private static func setPreferredInputDevice(uid: String, on engine: AVAudioEngine) -> Bool {
        guard let deviceID = audioDeviceID(forUID: uid), let audioUnit = engine.inputNode.audioUnit else { return false }
        var devID = deviceID
        let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        return status == noErr
    }

    /// Dùng `withUnsafeMutablePointer` tường minh: con trỏ trong `AudioValueTranslation` phải CÒN
    /// SỐNG đến hết lúc `AudioObjectGetPropertyData` chạy, không chỉ lúc khởi tạo struct (cảnh báo
    /// "temporary pointer" của Swift nếu viết `&cfUID` trực tiếp trong initializer).
    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDeviceForUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { cfUIDPtr in
            withUnsafeMutablePointer(to: &deviceID) { deviceIDPtr in
                var translation = AudioValueTranslation(
                    mInputData: cfUIDPtr, mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: deviceIDPtr, mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size))
                return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &translation)
            }
        }
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }
}

// MARK: cầu nối cho MicRecoverySession

@MainActor
extension AudioRecorder: MicBackend {
    var isEngineRunning: Bool { engine?.isRunning ?? false }

    var inputFormat: MicInputFormat {
        guard let e = engine else { return MicInputFormat(sampleRate: 0, channels: 0) }
        let f = e.inputNode.outputFormat(forBus: 0)
        return MicInputFormat(sampleRate: f.sampleRate, channels: Int(f.channelCount))
    }

    var lastFrameUptime: TimeInterval? { frameClock.lastFrame }
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func restartSameEngine() -> Bool {
        guard let e = engine else { return false }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        queue.sync {}
        guard installTap(on: e) else { return false }
        e.prepare()
        do { try e.start() } catch { return false }
        return true
    }

    func rebuildEngine(pinUID: String?) -> Bool {
        if case .started = launch(pinUID: pinUID, requirePin: pinUID != nil) { return true }
        return false
    }
}
