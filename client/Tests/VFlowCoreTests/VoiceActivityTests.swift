import Foundation
import Testing
@testable import VFlowCore

/// Sinh PCM tổng hợp (Float, -1...1) để đo VAD trên "âm thanh" thật thay vì mức âm bịa sẵn.
private enum SyntheticPCM {
    static func silence(count: Int, seed: UInt64 = 1) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in Float(rng.nextUnit() - 0.5) * 0.004 } // nhiễu nền cực nhỏ
    }

    static func noise(count: Int, amplitude: Float, seed: UInt64 = 2) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in Float(rng.nextUnit() - 0.5) * 2 * amplitude }
    }

    /// Giọng nói giả: sóng sin biên độ `amplitude` (300 Hz, đủ "ồn" để không phải DC thuần).
    static func speech(count: Int, amplitude: Float, sampleRate: Float = 16000) -> [Float] {
        (0..<count).map { i in amplitude * sin(2 * Float.pi * 300 * Float(i) / sampleRate) }
    }
}

/// RNG tất định (không phụ thuộc hệ thống) để test lặp lại được chính xác.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
}

@Suite struct VoiceActivityDetectorTests {
    let chunkSize = 1600 // 100 ms @ 16kHz
    let chunkSeconds: TimeInterval = 0.1

    private func levels(_ chunks: [[Float]]) -> [Float] { chunks.map(AudioMath.level) }

    @Test func pureSilenceNeverCountsAsVoiceAndEventuallyStops() {
        var vad = VoiceActivityDetector()
        var sawVoice = false
        for i in 0..<30 {
            let chunk = SyntheticPCM.silence(count: chunkSize, seed: UInt64(i))
            if vad.process(level: AudioMath.level(chunk), chunkSeconds: chunkSeconds) { sawVoice = true }
        }
        #expect(!sawVoice)
        // Chưa từng nghe tiếng nói ⇒ KHÔNG tự dừng (tránh dừng ngay vì vài trăm ms đầu im lặng).
        #expect(!vad.shouldStop(afterSilenceSeconds: 1))
    }

    @Test func loudSpeechIsDetectedAsVoice() {
        var vad = VoiceActivityDetector()
        // Vài khối im lặng để xác lập nhiễu nền trước.
        for i in 0..<5 { vad.process(level: AudioMath.level(SyntheticPCM.silence(count: chunkSize, seed: UInt64(i))), chunkSeconds: chunkSeconds) }
        let speechChunk = SyntheticPCM.speech(count: chunkSize, amplitude: 0.5)
        let detected = vad.process(level: AudioMath.level(speechChunk), chunkSeconds: chunkSeconds)
        #expect(detected)
        #expect(vad.hasDetectedVoice)
        #expect(vad.silenceSeconds == 0)
    }

    @Test func backgroundNoiseAloneDoesNotTriggerVoiceAfterAdapting() {
        var vad = VoiceActivityDetector()
        var voiceFlags: [Bool] = []
        for i in 0..<50 {
            let chunk = SyntheticPCM.noise(count: chunkSize, amplitude: 0.03, seed: UInt64(i) + 100)
            voiceFlags.append(vad.process(level: AudioMath.level(chunk), chunkSeconds: chunkSeconds))
        }
        // Ngưỡng ban đầu có thể thấp hơn mức nhiễu nền thật ⇒ vài lần dương giả lúc ĐẦU là chấp
        // nhận được, nhưng bộ thích nghi PHẢI tự sửa: 20 khối CUỐI (sau khi đã có thời gian thích
        // nghi) không còn lần nào bị coi là "có tiếng nói" — không được mãi mãi hiểu nhầm.
        let last20 = voiceFlags.suffix(20)
        #expect(!last20.contains(true), "nhiễu nền ổn định phải được thích nghi về đúng (không còn bị coi là tiếng nói) sau một thời gian")
    }

    @Test func quietSpeechAboveNoiseFloorIsStillDetected() {
        var vad = VoiceActivityDetector()
        for i in 0..<10 { vad.process(level: AudioMath.level(SyntheticPCM.noise(count: chunkSize, amplitude: 0.02, seed: UInt64(i))), chunkSeconds: chunkSeconds) }
        let quietSpeech = SyntheticPCM.speech(count: chunkSize, amplitude: 0.18)
        let detected = vad.process(level: AudioMath.level(quietSpeech), chunkSeconds: chunkSeconds)
        #expect(detected)
    }

    @Test func shortMidSentencePauseDoesNotTriggerEarlyStop() {
        var vad = VoiceActivityDetector()
        // Nói 0.5s, ngưng 1.5s (NGẮN hơn ngưỡng 3s cấu hình), nói lại — không được tự dừng giữa chừng.
        func speak(_ seconds: Double) {
            for _ in stride(from: 0.0, to: seconds, by: chunkSeconds) {
                vad.process(level: AudioMath.level(SyntheticPCM.speech(count: chunkSize, amplitude: 0.5)), chunkSeconds: chunkSeconds)
            }
        }
        func pause(_ seconds: Double) {
            for i in stride(from: 0.0, to: seconds, by: chunkSeconds) {
                let stopped = vad.shouldStop(afterSilenceSeconds: 3)
                #expect(!stopped, "không được dừng sớm giữa câu khi im lặng \(i)s < ngưỡng 3s")
                vad.process(level: AudioMath.level(SyntheticPCM.silence(count: chunkSize, seed: UInt64(i * 1000))), chunkSeconds: chunkSeconds)
            }
        }
        speak(0.5)
        pause(1.5)
        speak(0.5) // nói lại ⇒ reset bộ đếm im lặng
        #expect(vad.silenceSeconds == 0)
        pause(1.5) // lại im lặng ngắn — vẫn chưa đủ 3s kể từ lần nói lại
        #expect(!vad.shouldStop(afterSilenceSeconds: 3))
    }

    @Test func sustainedSilenceAfterSpeechEventuallyStops() {
        var vad = VoiceActivityDetector()
        for _ in stride(from: 0.0, to: 0.5, by: chunkSeconds) {
            vad.process(level: AudioMath.level(SyntheticPCM.speech(count: chunkSize, amplitude: 0.5)), chunkSeconds: chunkSeconds)
        }
        var stoppedAt: Double?
        for i in stride(from: 0.0, to: 5.0, by: chunkSeconds) {
            vad.process(level: AudioMath.level(SyntheticPCM.silence(count: chunkSize, seed: UInt64(i * 1000))), chunkSeconds: chunkSeconds)
            if vad.shouldStop(afterSilenceSeconds: 3) { stoppedAt = i; break }
        }
        #expect(stoppedAt != nil, "im lặng liên tục đủ lâu (>= 3s) sau khi đã nói phải tự dừng")
        if let s = stoppedAt { #expect(s >= 2.9 && s <= 3.2) }
    }

    @Test func zeroLimitMeansNeverStop() {
        var vad = VoiceActivityDetector()
        for _ in stride(from: 0.0, to: 0.5, by: chunkSeconds) {
            vad.process(level: AudioMath.level(SyntheticPCM.speech(count: chunkSize, amplitude: 0.5)), chunkSeconds: chunkSeconds)
        }
        for i in stride(from: 0.0, to: 30.0, by: chunkSeconds) {
            vad.process(level: AudioMath.level(SyntheticPCM.silence(count: chunkSize, seed: UInt64(i * 1000))), chunkSeconds: chunkSeconds)
        }
        #expect(!vad.shouldStop(afterSilenceSeconds: 0))
        #expect(vad.secondsUntilStop(limitSeconds: 0) == nil)
    }

    @Test func countdownApproachesZeroBeforeStop() {
        var vad = VoiceActivityDetector()
        vad.process(level: AudioMath.level(SyntheticPCM.speech(count: chunkSize, amplitude: 0.5)), chunkSeconds: chunkSeconds)
        vad.process(level: AudioMath.level(SyntheticPCM.silence(count: chunkSize, seed: 9)), chunkSeconds: 2.0)
        let remaining = vad.secondsUntilStop(limitSeconds: 3)
        #expect(remaining != nil)
        #expect(remaining! > 0.9 && remaining! < 1.1)
    }
}

@Suite struct MicrophoneSelectionTests {
    typealias Device = MicrophoneSelection.Device

    @Test func noConfiguredUIDMeansSystemDefault() {
        #expect(MicrophoneSelection.resolve(configuredUID: nil, availableDevices: [Device(uid: "a", name: "A")]) == .systemDefault)
    }

    @Test func configuredDeviceStillPresentIsUsed() {
        let devices = [Device(uid: "a", name: "A"), Device(uid: "b", name: "B")]
        #expect(MicrophoneSelection.resolve(configuredUID: "b", availableDevices: devices) == .configured(Device(uid: "b", name: "B")))
    }

    @Test func configuredDeviceGoneFallsBackAndFlags() {
        let devices = [Device(uid: "a", name: "A")]
        #expect(MicrophoneSelection.resolve(configuredUID: "removed-usb-mic", availableDevices: devices) == .fallbackDeviceMissing(previousUID: "removed-usb-mic"))
    }
}

@Suite struct RecordingLimitTests {
    @Test func noHealthzValueUsesDefault120() {
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: nil) == 120)
    }

    @Test func engineReportedValueWithinRangeIsUsed() {
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: 600) == 600)
    }

    @Test func engineValueBelowDefaultIsClampedUpToDefault() {
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: 10) == 120)
    }

    @Test func engineValueAboveMaxIsClampedDownToMax() {
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: 999_999) == 1200)
    }

    @Test func zeroOrNegativeIsTreatedAsUnset() {
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: 0) == 120)
        #expect(RecordingLimit.resolve(engineMaxAudioSeconds: -5) == 120)
    }
}
