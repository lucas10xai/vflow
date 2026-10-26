import Foundation
import Testing
@testable import VFlowCore

private func sine(_ freq: Double, rate: Int, count: Int, amp: Float = 0.5) -> [Float] {
    (0..<count).map { amp * Float(sin(2 * Double.pi * freq * Double($0) / Double(rate))) }
}

private func rms(_ x: ArraySlice<Int16>) -> Double {
    (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
}

/// Chuyển toàn bộ theo các khối cho trước.
private func convert(_ input: [Float], rate: Int, chunks: [Int]? = nil) -> [Int16] {
    let c = PCM16Converter(inputRate: rate)
    var out: [Int16] = []
    if let chunks {
        var i = 0, k = 0
        while i < input.count {
            let n = min(chunks[k % chunks.count], input.count - i)
            out += c.process(Array(input[i..<(i + n)]))
            i += n; k += 1
        }
    } else {
        out += c.process(input)
    }
    return out + c.finish()
}

@Suite struct PCM16ConverterTests {
    @Test(arguments: [(48_000, 48_000, 16_000), (44_100, 44_100, 16_000), (44_100, 44_101, 16_001),
                      (48_000, 1, 1), (48_000, 3, 1), (48_000, 4, 2), (16_000, 777, 777), (8_000, 5, 10)])
    func outputLength(rate: Int, inputCount: Int, expected: Int) {
        let out = convert([Float](repeating: 0.1, count: inputCount), rate: rate)
        #expect(out.count == expected)
        #expect(PCM16Converter.outputCount(inputSamples: inputCount, inputRate: rate) == expected)
    }

    @Test func emptyInputGivesNothing() {
        #expect(convert([], rate: 48_000).isEmpty)
    }

    @Test(arguments: [48_000, 44_100])
    func chunkedEqualsWhole(rate: Int) {
        let input = sine(440, rate: rate, count: rate / 2 + 37)
        let whole = convert(input, rate: rate)
        // Khối lẻ, khối 1 mẫu, khối lớn: kết quả phải giống từng mẫu.
        #expect(convert(input, rate: rate, chunks: [1, 7, 4096, 513, 2]) == whole)
        #expect(convert(input, rate: rate, chunks: [1]) == whole)
    }

    @Test(arguments: [48_000, 44_100])
    func dcLevelPreserved(rate: Int) {
        let out = convert([Float](repeating: 0.5, count: rate), rate: rate)
        let interior = out[200..<(out.count - 200)]
        #expect(interior.allSatisfy { abs(Int($0) - 16384) <= 2 }, "DC phải giữ nguyên ~16384")
    }

    @Test(arguments: [48_000, 44_100])
    func speechBandTonePreserved(rate: Int) {
        let out = convert(sine(1000, rate: rate, count: rate), rate: rate)
        let r = rms(out[400..<(out.count - 400)])
        let expected = 0.5 * 32767 / 2.0.squareRoot()
        #expect(abs(r - expected) / expected < 0.02, "1 kHz phải giữ biên độ, rms=\(r)")
        // Đúng tần số: đếm điểm cắt 0 trong 1 s ⇒ ~2000.
        let crossings = zip(out.dropFirst(400), out.dropFirst(401)).filter { ($0 < 0) != ($1 < 0) }.count
        #expect(abs(crossings - 2000 * (out.count - 401) / 16000) <= 4)
    }

    @Test func aboveNyquistIsRemovedNotAliased() {
        // 12 kHz ở 48 kHz: không có anti-alias sẽ thành tiếng 4 kHz rất to.
        let out = convert(sine(12_000, rate: 48_000, count: 48_000), rate: 48_000)
        let r = rms(out[400..<(out.count - 400)])
        #expect(r < 0.03 * 0.5 * 32767, "răng cưa còn rms=\(r)")
    }

    @Test func passthroughAt16kIsExact() {
        let input: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
        #expect(convert(input, rate: 16_000, chunks: [2, 1]) == input.map(PCM16Converter.toInt16))
    }

    @Test func int16ClampingAndNaN() {
        #expect(PCM16Converter.toInt16(1.0) == 32767)
        #expect(PCM16Converter.toInt16(1.5) == 32767)
        #expect(PCM16Converter.toInt16(-1.0) == -32767)
        #expect(PCM16Converter.toInt16(-3) == -32768)
        #expect(PCM16Converter.toInt16(.nan) == 0)
        #expect(PCM16Converter.toInt16(.infinity) == 32767)
        #expect(PCM16Converter.toInt16(-.infinity) == -32768)
        #expect(PCM16Converter.toInt16(0.5) == 16384)
    }

    @Test func clippedInputDoesNotWrapAround() {
        // Đầu vào vượt biên (micro quá to): phải kẹp, không tràn thành số âm.
        let out = convert([Float](repeating: 1.4, count: 4800), rate: 48_000)
        #expect(out[100..<(out.count - 100)].allSatisfy { $0 == 32767 })
    }
}

@Suite struct AudioMathTests {
    @Test func stereoPlanarDownmix() {
        #expect(AudioMath.downmix(planar: [[1, 0.5, 0], [-1, 0.5, 1]]) == [0, 0.5, 0.5])
        // Kênh dài ngắn khác nhau: lấy độ dài ngắn nhất.
        #expect(AudioMath.downmix(planar: [[1, 1, 1], [1, 1]]) == [1, 1])
        #expect(AudioMath.downmix(planar: []) == [])
    }

    @Test func interleavedDownmixDropsPartialFrame() {
        #expect(AudioMath.downmix(interleaved: [1, -1, 0.5, 0.5, 0.9], channels: 2) == [0, 0.5])
    }

    @Test func littleEndianBytes() {
        let d = AudioMath.littleEndianData([1, -2, 0x1234, Int16.min])
        #expect([UInt8](d) == [0x01, 0x00, 0xFE, 0xFF, 0x34, 0x12, 0x00, 0x80])
    }

    @Test func levelRange() {
        #expect(AudioMath.level([]) == 0)
        #expect(AudioMath.level([0, 0]) == 0)
        #expect(AudioMath.level([1, -1]) == 1)
        let quiet = AudioMath.level([Float](repeating: 0.001, count: 10))
        #expect(quiet >= 0 && quiet < 0.5)
    }
}

@Suite struct RetryBufferTests {
    @Test func keepsOnlyLatestAndExpiresAfterFiveMinutes() {
        var r = RetryBuffer()
        r.store(pcm: Data([1]), mode: "auto", app: nil, at: 0)
        r.store(pcm: Data([2]), mode: "email", app: "com.apple.mail", at: 10)
        #expect(r.current(at: 20)?.pcm == Data([2]))
        #expect(r.current(at: 10 + 299.9) != nil)
        #expect(r.current(at: 10 + 300) == nil)
        #expect(r.current(at: 10 + 1) == nil, "đã hết hạn thì xoá hẳn")
    }

    @Test func clearRemoves() {
        var r = RetryBuffer()
        r.store(pcm: Data([1]), mode: "auto", app: nil, at: 0)
        r.clear()
        #expect(r.current(at: 1) == nil)
    }
}
