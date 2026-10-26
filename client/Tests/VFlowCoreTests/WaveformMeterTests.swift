import Testing
@testable import VFlowCore

@Suite struct WaveformMeterTests {
    @Test func zeroLevelStillShowsMinimumHeightOnEveryBar() {
        for i in 0..<WaveformMeter.defaultBarCount {
            let h = WaveformMeter.barHeight(level: 0, barIndex: i, barCount: WaveformMeter.defaultBarCount)
            #expect(h == WaveformMeter.minHeightRatio)
        }
    }

    @Test func fullLevelMiddleBarIsTallestAtExactlyOne() {
        let middle = (WaveformMeter.defaultBarCount - 1) / 2
        let h = WaveformMeter.barHeight(level: 1, barIndex: middle, barCount: WaveformMeter.defaultBarCount)
        #expect(h == 1.0)
    }

    @Test func fullLevelEdgeBarsAreShorterThanMiddleBar() {
        let middleHeight = WaveformMeter.barHeight(level: 1, barIndex: (WaveformMeter.defaultBarCount - 1) / 2,
                                                    barCount: WaveformMeter.defaultBarCount)
        let edgeHeight = WaveformMeter.barHeight(level: 1, barIndex: 0, barCount: WaveformMeter.defaultBarCount)
        #expect(edgeHeight < middleHeight)
    }

    /// Phá nhánh: nếu bộ đo mic trả giá trị lỗi (NaN đã bị chặn ở lớp mic trước đó, nhưng âm/>1 có
    /// thể lọt qua phép tính trung gian), hàm phải KẸP về [minHeightRatio, 1] — không để vạch cao
    /// âm hoặc vượt khung.
    @Test func outOfRangeLevelsAreClamped() {
        let negative = WaveformMeter.barHeight(level: -5, barIndex: 0, barCount: WaveformMeter.defaultBarCount)
        let tooHigh = WaveformMeter.barHeight(level: 50, barIndex: (WaveformMeter.defaultBarCount - 1) / 2, barCount: WaveformMeter.defaultBarCount)
        #expect(negative == WaveformMeter.minHeightRatio)
        #expect(tooHigh == 1.0)
    }

    @Test func heightIsMonotonicWithLevelForAGivenBar() {
        let low = WaveformMeter.barHeight(level: 0.2, barIndex: 0, barCount: WaveformMeter.defaultBarCount)
        let high = WaveformMeter.barHeight(level: 0.8, barIndex: 0, barCount: WaveformMeter.defaultBarCount)
        #expect(high > low)
    }

    @Test func singleBarHasNoDistanceFactorDivideByZero() {
        // barCount == 1 ⇒ mid == 0 ⇒ phải không chia-cho-0 (NaN) — rơi về distanceRatio 0.
        let h = WaveformMeter.barHeight(level: 0.5, barIndex: 0, barCount: 1)
        #expect(h.isFinite)
    }
}
