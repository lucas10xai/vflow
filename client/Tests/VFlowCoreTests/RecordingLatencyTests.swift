import Foundation
import Testing
@testable import VFlowCore

@Suite struct RecordingLatencySampleTests {
    @Test func keyDownToFirstBufferComputesPositiveDelta() {
        let s = RecordingLatencySample(keyDownAt: 10.0, recorderStartCalledAt: 10.0, firstBufferReceivedAt: 10.03)
        #expect(abs((s.keyDownToFirstBufferSeconds ?? -1) - 0.03) < 0.0001)
    }

    @Test func nilFirstBufferMeansNoSample() {
        let s = RecordingLatencySample(keyDownAt: 10.0, recorderStartCalledAt: 10.05)
        #expect(s.keyDownToFirstBufferSeconds == nil)
    }

    @Test func clampsNegativeDeltaToZero() {
        // Đồng hồ không lùi trong thực tế, nhưng hàm vẫn phải an toàn nếu có sai lệch đo nhỏ.
        let s = RecordingLatencySample(keyDownAt: 10.0, recorderStartCalledAt: 9.999)
        #expect(s.keyDownToRecorderStartSeconds == 0)
    }
}

@Suite struct RecordingLatencyLogTests {
    @Test func zeroSamplesHasNilMedian() {
        let log = RecordingLatencyLog()
        #expect(log.count == 0)
        #expect(log.medianKeyDownToFirstBufferSeconds == nil)
        #expect(log.latest == nil)
    }

    @Test func oneSampleMedianEqualsItself() {
        var log = RecordingLatencyLog()
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.05))
        #expect(log.medianKeyDownToFirstBufferSeconds == 0.05)
    }

    @Test func oddCountMedianIsMiddleValue() {
        var log = RecordingLatencyLog()
        for v: TimeInterval in [0.01, 0.05, 0.03] {
            log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: v))
        }
        #expect(log.medianKeyDownToFirstBufferSeconds == 0.03)
    }

    @Test func evenCountMedianAveragesTwoMiddleValues() {
        var log = RecordingLatencyLog()
        for v: TimeInterval in [0.01, 0.05, 0.03, 0.07] {
            log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: v))
        }
        // sorted: 0.01, 0.03, 0.05, 0.07 -> trung bình (0.03+0.05)/2 = 0.04
        #expect(abs((log.medianKeyDownToFirstBufferSeconds ?? -1) - 0.04) < 0.0001)
    }

    @Test func samplesWithoutFirstBufferAreExcludedFromMedian() {
        var log = RecordingLatencyLog()
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: nil))
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: nil))
        #expect(log.count == 2) // vẫn đếm là mẫu, nhưng không góp vào trung vị
        #expect(log.medianKeyDownToFirstBufferSeconds == nil)
    }

    @Test func ringBufferDropsOldestBeyondCapacity() {
        var log = RecordingLatencyLog(capacity: 2)
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.01))
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.02))
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.03))
        #expect(log.count == 2)
        #expect(log.latest?.firstBufferReceivedAt == 0.03)
        // mẫu 0.01 bị đẩy ra ⇒ trung vị của {0.02, 0.03} = 0.025
        #expect(abs((log.medianKeyDownToFirstBufferSeconds ?? -1) - 0.025) < 0.0001)
    }
}

@Suite struct RecordingLatencyTextTests {
    @Test func zeroSamplesShowsHonestMessageNotFakeZero() {
        let text = RecordingLatencyText.summary(log: RecordingLatencyLog())
        #expect(text == "Chưa có lượt ghi nào trong phiên này")
        #expect(!text.contains("0 ms"))
    }

    @Test func withSamplesShowsMedianAndLatestInMilliseconds() {
        var log = RecordingLatencyLog()
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.05))
        let text = RecordingLatencyText.summary(log: log)
        #expect(text.contains("50 ms"))
        #expect(text.contains("1 mẫu"))
    }
}

@Suite struct RecordingLatencyTextEdgeTests {
    @Test func onlyCancelledAttemptsShowDashNotZero() {
        var log = RecordingLatencyLog()
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: nil))
        let text = RecordingLatencyText.summary(log: log)
        #expect(text == "Trung vị — · lần gần nhất — · 1 mẫu")
    }

    @Test func overflowKeepsOnlyNewestSamplesAndReportsCapacityCount() {
        var log = RecordingLatencyLog(capacity: 3)
        for ms in [900, 800, 100, 200, 300] { // 900 và 800 bị đẩy ra
            log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: Double(ms) / 1000))
        }
        #expect(RecordingLatencyText.summary(log: log) == "Trung vị 200 ms · lần gần nhất 300 ms · 3 mẫu")
    }

    @Test func latestIsLastRecordedEvenIfCancelledWhileMedianIgnoresIt() {
        var log = RecordingLatencyLog()
        log.record(RecordingLatencySample(keyDownAt: 0, recorderStartCalledAt: 0, firstBufferReceivedAt: 0.04))
        log.record(RecordingLatencySample(keyDownAt: 1, recorderStartCalledAt: 1, firstBufferReceivedAt: nil))
        #expect(RecordingLatencyText.summary(log: log) == "Trung vị 40 ms · lần gần nhất — · 2 mẫu")
    }
}

@Suite struct RecordingLatencyStoreTests {
    @Test func fullAttemptRecordsDeltaFromKeyDownToFirstBuffer() {
        let store = RecordingLatencyStore()
        store.begin(keyDownAt: 100)
        store.recorderStartCalled(at: 100.02)
        store.firstBufferReceived(at: 100.12)
        let s = store.snapshot.latest
        #expect(store.snapshot.count == 1)
        #expect(abs((s?.keyDownToFirstBufferSeconds ?? -1) - 0.12) < 0.0001)
        #expect(abs((s?.keyDownToRecorderStartSeconds ?? -1) - 0.02) < 0.0001)
    }

    @Test func onlyTheFirstBufferOfAnAttemptCounts() {
        let store = RecordingLatencyStore()
        store.begin(keyDownAt: 10)
        store.firstBufferReceived(at: 10.05)
        store.firstBufferReceived(at: 10.06) // khối thứ hai của cùng lượt: bỏ qua
        store.firstBufferReceived(at: 10.07)
        #expect(store.snapshot.count == 1)
        #expect(abs((store.snapshot.latest?.keyDownToFirstBufferSeconds ?? -1) - 0.05) < 0.0001)
    }

    @Test func bufferWithoutAnAttemptRecordsNothing() {
        let store = RecordingLatencyStore()
        store.firstBufferReceived(at: 5)
        #expect(store.snapshot.count == 0)
    }

    /// Lượt huỷ (Esc, lỗi quyền, không phải lượt ghi) KHÔNG tạo mẫu: không phải một lần đo độ trễ, và nếu
    /// tạo mẫu "—" thì số mẫu hiện ở Cài đặt sẽ phình lên bởi cả những lần không ghi được gì.
    @Test func cancelBeforeAudioCreatesNoSample() {
        let store = RecordingLatencyStore()
        store.begin(keyDownAt: 1)
        store.recorderStartCalled(at: 1.01)
        store.cancel()
        #expect(store.snapshot.count == 0)
        store.firstBufferReceived(at: 1.2) // khung muộn sau khi huỷ: không có lượt đang đo ⇒ vô hại
        #expect(store.snapshot.count == 0)
        store.cancel() // huỷ lần nữa khi không có lượt: vô hại
        #expect(store.snapshot.count == 0)
    }

    @Test func newAttemptDropsTheUnfinishedOneWithoutASample() {
        let store = RecordingLatencyStore()
        store.begin(keyDownAt: 1)
        store.begin(keyDownAt: 2)
        store.firstBufferReceived(at: 2.1)
        #expect(store.snapshot.count == 1)
        #expect(store.snapshot.medianKeyDownToFirstBufferSeconds.map { abs($0 - 0.1) < 0.0001 } == true)
    }

    @Test func storeOverflowDropsOldestAtCapacity() {
        let store = RecordingLatencyStore(capacity: 2)
        for i in 0..<5 {
            store.begin(keyDownAt: Double(i))
            store.firstBufferReceived(at: Double(i) + 0.01 * Double(i + 1))
        }
        #expect(store.snapshot.count == 2)
        #expect(abs((store.snapshot.latest?.keyDownToFirstBufferSeconds ?? -1) - 0.05) < 0.0001)
    }
}
