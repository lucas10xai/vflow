import Foundation

/// Chuyển âm thanh micro (Float32, mọi tần số, mọi số kênh) thành PCM 16 kHz mono Int16
/// theo từng khối, giữ trạng thái giữa các khối (kết quả giống hệt khi xử lý một lần).
/// Nội suy band-limited (sinc cửa sổ Blackman) chống răng cưa khi hạ tần số.
/// Chỉ trong RAM, không ghi đĩa.
public final class PCM16Converter {
    public static let targetRate = 16_000

    public let inputRate: Int
    private let zeroCrossings = 8
    /// Tần số cắt chuẩn hoá theo tần số vào (chu kỳ/mẫu).
    private let cutoff: Double
    /// Bán kính cửa sổ (đơn vị mẫu vào).
    private let halfWidth: Int

    private var buffer: [Float] = []
    /// Chỉ số toàn cục của `buffer[0]`.
    private var bufferStart = 0
    private var totalInput = 0
    /// Chỉ số mẫu ra kế tiếp.
    private var nextOutput = 0
    private var finished = false

    public init(inputRate: Int) {
        precondition(inputRate > 0, "inputRate phải > 0")
        self.inputRate = inputRate
        let ratio = Double(Self.targetRate) / Double(inputRate)
        cutoff = 0.5 * min(1.0, ratio) * 0.92
        halfWidth = Int((Double(zeroCrossings) / (2 * cutoff)).rounded(.up))
    }

    /// Số mẫu ra tương ứng `n` mẫu vào: ceil(n · 16000 / rate).
    public static func outputCount(inputSamples n: Int, inputRate: Int) -> Int {
        (n * targetRate + inputRate - 1) / inputRate
    }

    /// Đưa một khối mono vào, trả các mẫu 16 kHz đã tính được.
    public func process(_ mono: [Float]) -> [Int16] {
        precondition(!finished, "process sau finish")
        guard !mono.isEmpty else { return [] }
        if inputRate == Self.targetRate {
            totalInput += mono.count
            nextOutput += mono.count
            return mono.map(Self.toInt16)
        }
        buffer.append(contentsOf: mono)
        totalInput += mono.count
        return drain(final: false)
    }

    /// Kết thúc: xả nốt phần đuôi (coi phía sau là im lặng).
    public func finish() -> [Int16] {
        guard !finished else { return [] }
        finished = true
        if inputRate == Self.targetRate { return [] }
        return drain(final: true)
    }

    private func drain(final: Bool) -> [Int16] {
        var out: [Int16] = []
        let limit = Self.outputCount(inputSamples: totalInput, inputRate: inputRate)
        while nextOutput < limit {
            // Vị trí mẫu ra theo trục mẫu vào, tính bằng số nguyên để không trôi.
            let num = nextOutput * inputRate
            let base = num / Self.targetRate
            let frac = Double(num % Self.targetRate) / Double(Self.targetRate)
            if !final && base + halfWidth + 1 >= totalInput { break }
            out.append(Self.toInt16(sample(base: base, frac: frac)))
            nextOutput += 1
        }
        // Bỏ các mẫu vào không còn cần nữa.
        let keepFrom = (nextOutput * inputRate) / Self.targetRate - halfWidth - 1
        if keepFrom > bufferStart {
            let drop = min(keepFrom - bufferStart, buffer.count)
            buffer.removeFirst(drop)
            bufferStart += drop
        }
        return out
    }

    private func sample(base: Int, frac: Double) -> Float {
        var acc = 0.0
        var weightSum = 0.0
        for i in (base - halfWidth)...(base + halfWidth + 1) {
            let t = Double(i - base) - frac // khoảng cách tới vị trí ra (mẫu vào)
            if abs(t) > Double(halfWidth) { continue }
            let w = kernel(t)
            weightSum += w
            let idx = i - bufferStart
            if i >= 0, i < totalInput, idx >= 0, idx < buffer.count {
                acc += w * Double(buffer[idx])
            }
        }
        // Chuẩn hoá theo tổng trọng số: hệ số DC đúng bằng 1.
        return weightSum == 0 ? 0 : Float(acc / weightSum)
    }

    private func kernel(_ t: Double) -> Double {
        let x = 2 * cutoff * t
        let sinc = x == 0 ? 1.0 : sin(Double.pi * x) / (Double.pi * x)
        let n = (t / Double(halfWidth) + 1) / 2 // 0…1
        let blackman = 0.42 - 0.5 * cos(2 * Double.pi * n) + 0.08 * cos(4 * Double.pi * n)
        return sinc * blackman
    }

    /// Float [-1, 1] ⇒ Int16; ngoài biên bị kẹp, NaN ⇒ 0.
    public static func toInt16(_ v: Float) -> Int16 {
        guard v.isFinite else { return v.isNaN ? 0 : (v > 0 ? Int16.max : Int16.min) }
        let scaled = (Double(v) * 32767).rounded()
        if scaled >= 32767 { return Int16.max }
        if scaled <= -32768 { return Int16.min }
        return Int16(scaled)
    }
}

public enum AudioMath {
    /// Trộn các kênh (dạng tách kênh) thành mono bằng trung bình cộng.
    public static func downmix(planar channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        if channels.count == 1 { return first }
        let n = channels.map(\.count).min() ?? 0
        var out = [Float](repeating: 0, count: n)
        let scale = 1 / Float(channels.count)
        for ch in channels {
            for i in 0..<n { out[i] += ch[i] * scale }
        }
        return out
    }

    /// Trộn dữ liệu xen kẽ (LRLR…) thành mono. Khung lẻ cuối (thiếu kênh) bị bỏ.
    public static func downmix(interleaved data: [Float], channels: Int) -> [Float] {
        precondition(channels > 0)
        if channels == 1 { return data }
        let frames = data.count / channels
        var out = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channels)
        for f in 0..<frames {
            var s: Float = 0
            for c in 0..<channels { s += data[f * channels + c] }
            out[f] = s * scale
        }
        return out
    }

    /// Int16 ⇒ byte little-endian (định dạng `audio/L16` của engine).
    public static func littleEndianData(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for s in samples {
            let u = UInt16(bitPattern: s)
            data.append(UInt8(u & 0xff))
            data.append(UInt8(u >> 8))
        }
        return data
    }

    /// Mức âm 0…1 cho thanh mức (RMS, thang dB −50…0).
    public static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples where s.isFinite { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return max(0, min(1, (db + 50) / 50))
    }
}

/// Bản âm thanh cuối cùng cho “Thử lại lần cuối”: tối đa một bản, hết hạn sau 5 phút.
public struct RetryBuffer: Sendable {
    public static let lifetime: TimeInterval = 300
    public struct Entry: Sendable {
        public let pcm: Data
        public let mode: String
        public let app: String?
        public let storedAt: TimeInterval
    }
    private var entry: Entry?

    public init() {}

    public mutating func store(pcm: Data, mode: String, app: String?, at now: TimeInterval) {
        entry = Entry(pcm: pcm, mode: mode, app: app, storedAt: now) // thay bản cũ
    }

    /// Trả bản còn hạn; hết hạn thì xoá luôn.
    public mutating func current(at now: TimeInterval) -> Entry? {
        guard let e = entry else { return nil }
        if now - e.storedAt >= Self.lifetime || now < e.storedAt { entry = nil; return nil }
        return e
    }

    public mutating func clear() { entry = nil }
}
