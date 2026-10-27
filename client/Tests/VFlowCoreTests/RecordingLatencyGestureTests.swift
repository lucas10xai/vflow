import Foundation
import Testing
@testable import VFlowCore

/// Mô hình keo dán của `AppController` bằng CHÍNH các khối lõi thật (`HotkeyStateMachine` +
/// `RecordingLatencyGesture` + `RecordingLatencyStore`) và giờ giả: phím vào ⇒ `observe` rồi `handle`;
/// lệnh bắt đầu ghi ⇒ `begin(keyDownAt: mốc cử chỉ)` + `recorderStartCalled`; huỷ ⇒ `cancel`; khung âm
/// thanh đầu tiên ⇒ `firstBufferReceived`. Không có micro/AppKit.
private struct Rig {
    var machine = HotkeyStateMachine()
    var gesture = RecordingLatencyGesture()
    let store = RecordingLatencyStore()

    mutating func input(_ i: KeyInput, at t: TimeInterval) {
        gesture.observe(i, phase: machine.phase, at: t)
        act(machine.handle(i, at: t), at: t)
    }

    mutating func tick(at t: TimeInterval, optionHeld: Bool = true) {
        act(machine.tick(at: t, optionHeld: optionHeld), at: t)
    }

    mutating func act(_ action: HotkeyAction, at t: TimeInterval) {
        switch action {
        case .startRecording, .startCommandRecording:
            store.begin(keyDownAt: gesture.consumeKeyDownAt() ?? t)
            store.recorderStartCalled(at: t)
        case .cancel:
            store.cancel()
        default: break
        }
    }

    func firstBuffer(at t: TimeInterval) { store.firstBufferReceived(at: t) }

    var samples: Int { store.snapshot.count }
    var latest: RecordingLatencySample? { store.snapshot.latest }
}

private func close(_ a: TimeInterval?, _ b: TimeInterval) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }

@Suite struct RecordingLatencyGestureTests {
    @Test func holdMeasuresFromKeyDownNotFromThresholdCrossing() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 10.0)
        r.tick(at: 10.1)
        #expect(r.samples == 0)
        r.tick(at: 10.25) // qua ngưỡng 0,2 s ⇒ máy ra lệnh ghi
        r.firstBuffer(at: 10.32)
        #expect(r.samples == 1)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.32), "phải tính từ lúc phím xuống (10.0), không phải lúc ra lệnh (10.25)")
        #expect(close(r.latest?.keyDownToRecorderStartSeconds, 0.25))
    }

    /// Bấm đúp (hands-free) chỉ là MỘT lượt, mốc là lần chạm THỨ HAI.
    @Test func doubleTapIsOneSampleStartingAtTheSecondTap() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 20.0)
        r.input(.leftOptionUp, at: 20.05)
        #expect(r.samples == 0, "chạm đầu chưa phải lượt ghi")
        r.input(.leftOptionDown(othersHeld: false), at: 20.2)
        r.input(.leftOptionUp, at: 20.25) // đúp ⇒ ghi khoá
        r.firstBuffer(at: 20.3)
        r.firstBuffer(at: 20.4) // khối thứ hai không tính
        #expect(r.samples == 1)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.1), "mốc phải là lần chạm thứ hai (20.2)")
    }

    @Test func quickSingleTapThatNeverRecordsCreatesNoSample() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 40.0)
        r.input(.leftOptionUp, at: 40.05)
        r.tick(at: 41.0, optionHeld: false)
        r.firstBuffer(at: 40.1)
        #expect(r.samples == 0)
    }

    @Test func escapeBeforeFirstBufferCreatesNoSampleAndLateBufferIsIgnored() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 50.0)
        r.tick(at: 50.25)
        r.input(.escape, at: 50.3) // huỷ trước khi có âm thanh
        r.firstBuffer(at: 50.35) // khung muộn của lượt đã huỷ
        #expect(r.samples == 0)
    }

    @Test func twoConsecutiveTurnsGiveTwoIndependentSamples() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 60.0)
        r.tick(at: 60.25)
        r.firstBuffer(at: 60.30)
        r.input(.leftOptionUp, at: 61.0) // kết thúc lượt 1 (gửi)
        r.machine.finished(optionHeld: false)
        r.input(.leftOptionDown(othersHeld: false), at: 70.0)
        r.tick(at: 70.25)
        r.firstBuffer(at: 70.50)
        #expect(r.samples == 2)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.5))
        #expect(close(r.store.snapshot.medianKeyDownToFirstBufferSeconds, 0.4), "trung vị của 0,30 và 0,50")
    }

    /// Lượt đầu chưa có âm thanh thì bị chuyển sang Command Mode (⌃): chỉ còn MỘT lượt, tính từ ⌃.
    @Test func overlappingTurnReplacesTheUnfinishedOneInsteadOfCountingTwice() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 30.0)
        r.tick(at: 30.25) // ghi giữ phím bắt đầu, chưa có khung âm thanh
        r.input(.leftControlDown, at: 30.3) // ⌃ trong cửa sổ 0,4 s? (30.3 - 30.0 < 0,4) ⇒ Command Mode
        r.firstBuffer(at: 30.4)
        #expect(r.samples == 1)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.1), "mốc của lượt Command Mode là lúc ⌃ xuống (30.3)")
    }

    @Test func commandModeStartedWithinWindowIsMeasuredFromControlKeyDown() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 80.0)
        r.input(.leftControlDown, at: 80.1)
        r.firstBuffer(at: 80.18)
        #expect(r.samples == 1)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.08))
    }

    /// Chạm ⌥ để KẾT THÚC ghi khoá không được để lại mốc cho lượt sau dùng nhầm.
    @Test func keyDownThatEndsALockedRecordingIsNotReusedByNextTurn() {
        var r = Rig()
        r.input(.leftOptionDown(othersHeld: false), at: 90.0)
        r.input(.leftOptionUp, at: 90.05)
        r.input(.leftOptionDown(othersHeld: false), at: 90.2)
        r.input(.leftOptionUp, at: 90.25) // ghi khoá bắt đầu
        r.firstBuffer(at: 90.3)
        r.input(.leftOptionDown(othersHeld: false), at: 95.0) // chạm kết thúc ghi khoá
        r.input(.leftOptionUp, at: 95.05)
        r.machine.finished(optionHeld: false)
        r.input(.leftOptionDown(othersHeld: false), at: 100.0) // lượt mới
        r.tick(at: 100.25)
        r.firstBuffer(at: 100.31)
        #expect(r.samples == 2)
        #expect(close(r.latest?.keyDownToFirstBufferSeconds, 0.31), "mốc phải là 100.0, không phải 95.0")
    }
}

@Suite struct RecordingLatencyGestureUnitTests {
    @Test func keyDownIsConsumedOnce() {
        var g = RecordingLatencyGesture()
        g.observe(.leftOptionDown(othersHeld: false), phase: .idle, at: 5)
        #expect(g.consumeKeyDownAt() == 5)
        #expect(g.consumeKeyDownAt() == nil)
    }

    @Test func optionDownWhileNotIdleDoesNotMoveTheMark() {
        var g = RecordingLatencyGesture()
        g.observe(.leftOptionDown(othersHeld: false), phase: .idle, at: 5)
        g.observe(.leftOptionDown(othersHeld: false), phase: .armed(since: 5), at: 5.1) // lặp sự kiện
        g.observe(.keyDown, phase: .armed(since: 5), at: 5.12)
        #expect(g.consumeKeyDownAt() == 5)
    }

    @Test func controlDownOnlyCountsWhileArmedOrRecording() {
        var g = RecordingLatencyGesture()
        g.observe(.leftControlDown, phase: .idle, at: 1)
        #expect(g.consumeKeyDownAt() == nil)
        g.observe(.leftControlDown, phase: .suppressed, at: 2)
        #expect(g.consumeKeyDownAt() == nil)
        g.observe(.leftControlDown, phase: .armed(since: 0), at: 3)
        #expect(g.consumeKeyDownAt() == 3)
    }
}
