import AVFoundation
import CoreAudio
import VFlowCore

/// Ghi micro bằng AVAudioEngine, đổi sang 16 kHz mono Int16 ngay trong RAM. Không bao giờ ghi đĩa.
final class AudioRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.aios.vflow.audio")
    private var engine: AVAudioEngine?
    private var converter: PCM16Converter?
    private var samples: [Int16] = []
    private var configObserver: NSObjectProtocol?
    /// Mức âm 0…1 (gọi trên luồng chính).
    var onLevel: (@MainActor (Float) -> Void)?
    /// Thiết bị đổi/rút micro trong lúc ghi.
    var onInterrupted: (@MainActor (String) -> Void)?

    static func permission() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    /// Danh sách micro thật (Cài đặt › Chung) — `AVCaptureDevice.DiscoverySession`, không cần quyền
    /// Micro để CHỈ liệt kê (tên/UID), chỉ cần quyền để ghi thật.
    static func availableDevices() -> [MicrophoneSelection.Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { MicrophoneSelection.Device(uid: $0.uniqueID, name: $0.localizedName) }
    }

    /// `deviceUID` nil = mặc định hệ thống (hành vi CŨ, không đổi gì — xem `MicrophoneSelection`).
    /// Có UID ⇒ cố gắng ghim micro đó vào `AVAudioEngine` bằng CoreAudio TRƯỚC khi đọc định dạng vào;
    /// không tìm được thiết bị/ghim lỗi ⇒ bỏ qua ÊM, dùng mặc định hệ thống (không chặn ghi âm vì lỗi
    /// chọn thiết bị — xem contract mục 7a).
    @MainActor
    func start(deviceUID: String? = nil) throws {
        let engine = AVAudioEngine() // mới mỗi lần: theo kịp đổi thiết bị
        if let uid = deviceUID { Self.setPreferredInputDevice(uid: uid, on: engine) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate >= 8000, format.channelCount > 0 else {
            throw ClientError.micUnavailable("không có thiết bị vào (định dạng \(format.sampleRate) Hz, \(format.channelCount) kênh)")
        }
        let conv = PCM16Converter(inputRate: Int(format.sampleRate.rounded()))
        queue.sync { converter = conv; samples = []; samples.reserveCapacity(16_000 * 30) }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let chans = Int(buffer.format.channelCount)
            var planar: [[Float]] = []
            planar.reserveCapacity(chans)
            for c in 0..<chans { planar.append(Array(UnsafeBufferPointer(start: data[c], count: n))) }
            let mono = AudioMath.downmix(planar: planar)
            let level = AudioMath.level(mono)
            self.queue.async {
                if let out = self.converter?.process(mono) { self.samples.append(contentsOf: out) }
            }
            Task { @MainActor in self.onLevel?(level) }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onInterrupted?("thiết bị micro thay đổi hoặc bị rút") }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw ClientError.micUnavailable(error.localizedDescription)
        }
        self.engine = engine
    }

    /// Dừng và trả PCM 16 kHz LE.
    @MainActor
    func stop() -> Data {
        teardown()
        return queue.sync {
            if let tail = converter?.finish() { samples.append(contentsOf: tail) }
            let data = AudioMath.littleEndianData(samples)
            samples = []
            converter = nil
            return data
        }
    }

    /// Huỷ: bỏ toàn bộ âm thanh.
    @MainActor
    func cancel() {
        teardown()
        queue.sync { samples = []; converter = nil }
    }

    @MainActor
    private func teardown() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        // Hàng đợi xử lý xong các khối đã nhận trước khi đọc kết quả.
        queue.sync {}
    }

    /// Ghim `engine.inputNode` vào đúng `AudioDeviceID` của `uid` qua CoreAudio
    /// (`kAudioOutputUnitProperty_CurrentDevice`) — PHẢI gọi trước khi đọc `outputFormat`/tạo tap.
    /// CHƯA kiểm được bằng micro ngoài thật (môi trường dựng không có micro ngoài để đổi) — xem
    /// báo cáo cuối; lỗi bất kỳ bước nào đều bị bỏ qua êm, không chặn ghi âm.
    private static func setPreferredInputDevice(uid: String, on engine: AVAudioEngine) {
        guard let deviceID = audioDeviceID(forUID: uid), let audioUnit = engine.inputNode.audioUnit else { return }
        var devID = deviceID
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
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
