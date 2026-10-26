import Testing
@testable import VFlowCore

/// Giữ ⌥ trái tại `t0`, đi qua ngưỡng, trả máy đang ghi.
private func recording(at t0: Double = 0) -> HotkeyStateMachine {
    var m = HotkeyStateMachine()
    _ = m.handle(.leftOptionDown(othersHeld: false), at: t0)
    #expect(m.tick(at: t0 + 0.25, optionHeld: true) == .startRecording)
    return m
}

@Suite struct HotkeyStateMachineTests {
    @Test func quickTapIsIgnoredCompletely() {
        var m = HotkeyStateMachine()
        #expect(m.handle(.leftOptionDown(othersHeld: false), at: 10) == .none)
        #expect(m.tick(at: 10.1, optionHeld: true) == .none)
        #expect(m.tick(at: 10.19, optionHeld: true) == .none)
        #expect(m.handle(.leftOptionUp, at: 10.199) == .none)
        #expect(m.phase == .idle)
        // Sau khi nhả, các tick muộn không được bắt đầu ghi.
        #expect(m.tick(at: 11, optionHeld: false) == .none)
    }

    @Test func holdAtThresholdStartsThenReleaseSends() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.tick(at: 0.199, optionHeld: true) == .none)
        #expect(m.tick(at: 0.2, optionHeld: true) == .startRecording)
        #expect(m.tick(at: 1, optionHeld: true) == .none)
        #expect(m.handle(.leftOptionUp, at: 3) == .stopAndSend(.released))
        if case .busy = m.phase {} else { Issue.record("phải ở busy, đang \(m.phase)") }
    }

    @Test func otherKeyWhileRecordingCancelsAndNeverSends() {
        var m = recording()
        #expect(m.handle(.keyDown, at: 1) == .cancel(.otherInput))
        #expect(m.phase == .suppressed)
        #expect(m.tick(at: 2, optionHeld: true) == .none)
        #expect(m.handle(.leftOptionUp, at: 2.5) == .none) // nhả sau khi huỷ: không gửi
        #expect(m.phase == .idle)
    }

    @Test(arguments: [KeyInput.otherModifierDown, .mouseDown])
    func otherModifierOrClickWhileRecordingCancels(_ input: KeyInput) {
        var m = recording()
        #expect(m.handle(input, at: 1) == .cancel(.otherInput))
        #expect(m.handle(.leftOptionUp, at: 2) == .none)
    }

    @Test func comboDuringArmingNeverStartsRecording() {
        // ⌥← trong terminal, ⌥+e gõ ký tự đặc biệt…: không được ghi.
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.keyDown, at: 0.05)
        #expect(m.tick(at: 0.5, optionHeld: true) == .none)
        #expect(m.tick(at: 5, optionHeld: true) == .none)
        #expect(m.handle(.leftOptionUp, at: 5.1) == .none)
        #expect(m.phase == .idle)
    }

    @Test func optionPressedWithOtherModifierHeldIsIgnored() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: true), at: 0) // ⌘⌥…
        #expect(m.tick(at: 1, optionHeld: true) == .none)
        #expect(m.phase == .suppressed)
    }

    @Test func autoSendsAt120SecondsExactlyOnce() {
        var m = recording(at: 0) // bắt đầu ghi ở 0.25
        #expect(m.tick(at: 120.2, optionHeld: true) == .none)
        #expect(m.tick(at: 120.25, optionHeld: true) == .stopAndSend(.maxDuration))
        #expect(m.handle(.leftOptionUp, at: 125) == .none) // nhả sau đó: không gửi lần hai
        #expect(m.tick(at: 126, optionHeld: false) == .none)
    }

    @Test func neverOverlapsWhileBusy() {
        var m = recording()
        _ = m.handle(.leftOptionUp, at: 1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 1.1)
        #expect(m.tick(at: 3, optionHeld: true) == .none)
        #expect(!m.isRecording)
        let accepted = m.beginExternalJob(at: 3)
        #expect(!accepted) // “thử lại” cũng không chen vào
        m.finished(optionHeld: true) // ⌥ vẫn giữ ⇒ phải nhả rồi bấm lại
        #expect(m.tick(at: 4, optionHeld: true) == .none)
        _ = m.handle(.leftOptionUp, at: 4.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 5)
        #expect(m.tick(at: 5.3, optionHeld: true) == .startRecording)
    }

    @Test func lostReleaseEventIsRecovered() {
        var m = recording()
        // Sự kiện nhả bị mất; phím thật đã nhả ⇒ gửi (người dùng đã nhả).
        #expect(m.tick(at: 2, optionHeld: false) == .stopAndSend(.releaseMissed))

        var a = HotkeyStateMachine()
        _ = a.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(a.tick(at: 0.1, optionHeld: false) == .none)
        #expect(a.phase == .idle)
        #expect(a.tick(at: 0.3, optionHeld: true) == .none) // không ghi “ma”

        var s = HotkeyStateMachine()
        _ = s.handle(.leftOptionDown(othersHeld: true), at: 0)
        _ = s.tick(at: 1, optionHeld: false)
        #expect(s.phase == .idle)
    }

    @Test func stuckBusyTimesOut() {
        var m = recording()
        _ = m.handle(.leftOptionUp, at: 1)
        #expect(m.tick(at: 1 + 199, optionHeld: false) == .none)
        #expect(m.tick(at: 1 + 200, optionHeld: false) == .busyTimedOut)
        #expect(m.phase == .idle)
    }

    @Test func tapResetCancelsRecording() {
        var m = recording()
        #expect(m.reset(optionHeld: true) == .cancel(.reset))
        #expect(m.phase == .suppressed)
    }

    @Test func externalJobOnlyWhenIdle() {
        var m = HotkeyStateMachine()
        let accepted = m.beginExternalJob(at: 0)
        #expect(accepted)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 1)
        #expect(m.tick(at: 2, optionHeld: true) == .none)
        m.finished(optionHeld: false)
        #expect(m.phase == .idle)
    }
}

@Suite struct HandsFreeLockTests {
    /// Chạm nhanh (<200 ms) hai lần, cách nhau ≤350 ms ⇒ ghi khoá, không cần giữ phím.
    @Test func doubleTapLocksRecording() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.leftOptionUp, at: 0.1) == .none) // tap 1: bỏ qua, chỉ nhớ lại
        #expect(m.phase == .idle)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        #expect(m.handle(.leftOptionUp, at: 0.35) == .startRecording) // tap 2 trong 0.35s ⇒ khoá
        #expect(m.isLocked)
        #expect(m.isRecording)
    }

    /// Hai lần chạm cách nhau > 350 ms ⇒ không tính là đúp (mỗi lần vẫn bị bỏ qua hoàn toàn).
    @Test func tapsTooFarApartDoNotLock() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.leftOptionUp, at: 0.1) == .none)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.5) // cách lần 1 0.4s > 0.35s
        #expect(m.handle(.leftOptionUp, at: 0.55) == .none)
        #expect(m.phase == .idle)
        #expect(!m.isRecording)
    }

    /// Lần "chạm" thứ hai thực ra là GIỮ (qua ngưỡng 200 ms) ⇒ ghi kiểu giữ phím như cũ, không khoá.
    @Test func secondPressHeldPastThresholdStartsNormalRecordingNotLocked() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.leftOptionUp, at: 0.1) == .none)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.2)
        #expect(m.tick(at: 0.41, optionHeld: true) == .startRecording) // giữ quá 200ms ⇒ ghi thường
        #expect(m.isRecording && !m.isLocked)
    }

    /// Ghi khoá: nhả/giữ ⌥ không ảnh hưởng (không có sự kiện nào) — chỉ hết 120s mới tự gửi.
    @Test func lockedRecordingIgnoresOptionHeldDuringTick() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftOptionUp, at: 0.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        _ = m.handle(.leftOptionUp, at: 0.35)
        #expect(m.isLocked)
        // ⌥ không được giữ (tay đã rời phím) — KHÔNG được tự dừng như "mất sự kiện nhả" ở ghi thường.
        #expect(m.tick(at: 1, optionHeld: false) == .none)
        #expect(m.isLocked)
    }

    /// Bấm ⌥ một lần nữa (down rồi up) ⇒ dừng và gửi.
    @Test func singlePressEndsLockedRecording() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftOptionUp, at: 0.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        _ = m.handle(.leftOptionUp, at: 0.35)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 5)
        #expect(m.handle(.leftOptionUp, at: 5.05) == .stopAndSend(.released))
        if case .busy = m.phase {} else { Issue.record("phải ở busy, đang \(m.phase)") }
    }

    /// Ghi khoá tự gửi sau 120 s.
    @Test func lockedRecordingAutoSendsAt120Seconds() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftOptionUp, at: 0.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        _ = m.handle(.leftOptionUp, at: 0.35)
        #expect(m.tick(at: 0.35 + 119, optionHeld: false) == .none)
        #expect(m.tick(at: 0.35 + 120, optionHeld: false) == .stopAndSend(.maxDuration))
    }

    /// Phím khác trong lúc ghi khoá ⇒ huỷ ngay (không có phím ⌥ nào đang giữ để chờ nhả).
    @Test func otherKeyDuringLockedRecordingCancels() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftOptionUp, at: 0.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        _ = m.handle(.leftOptionUp, at: 0.35)
        #expect(m.handle(.keyDown, at: 1) == .cancel(.otherInput))
        #expect(m.phase == .idle) // không chờ nhả gì cả — khác với ghi kiểu giữ phím
    }
}

@Suite struct EscapeCancelTests {
    /// Esc trong lúc ghi kiểu giữ phím ⇒ huỷ, không gửi; ⌥ coi như vẫn giữ nên chờ nhả.
    @Test func escapeCancelsHoldRecording() {
        var m = recording()
        #expect(m.handle(.escape, at: 1) == .cancel(.escape))
        #expect(m.phase == .suppressed)
        #expect(m.handle(.leftOptionUp, at: 1.1) == .none) // không gửi lần nào
        #expect(m.phase == .idle)
    }

    /// Esc trong lúc ghi khoá ⇒ huỷ ngay, về rảnh (không phím nào đang giữ).
    @Test func escapeCancelsLockedRecording() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftOptionUp, at: 0.1)
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.3)
        _ = m.handle(.leftOptionUp, at: 0.35)
        #expect(m.handle(.escape, at: 1) == .cancel(.escape))
        #expect(m.phase == .idle)
    }

    /// Esc lúc chỉ đang "armed" (chưa ghi gì) ⇒ không có gì để huỷ, không trả cancel action.
    @Test func escapeWhileArmedIsQuiet() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.escape, at: 0.05) == .none)
        #expect(m.phase == .suppressed)
    }

    /// Esc trong lúc "đang dịch" (busy) không có tác dụng — không huỷ được yêu cầu đã gửi.
    @Test func escapeDuringBusyIsIgnored() {
        var m = recording()
        _ = m.handle(.leftOptionUp, at: 1)
        #expect(m.handle(.escape, at: 1.1) == .none)
        if case .busy = m.phase {} else { Issue.record("phải vẫn ở busy") }
    }
}

@Suite struct CommandModeTests {
    /// ⌃ trái trong 400 ms đầu của lần giữ ⌥ (khi còn "armed", chưa qua ngưỡng ghi thường) ⇒ Command Mode.
    @Test func controlWithinWindowWhileArmedStartsCommandMode() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.leftControlDown, at: 0.1) == .startCommandRecording)
        if case .recordingCommand = m.phase {} else { Issue.record("phải ở recordingCommand, đang \(m.phase)") }
    }

    /// ⌃ trái trong 400 ms đầu NHƯNG sau khi ghi thường đã bắt đầu (200 ms < 400 ms) vẫn chuyển
    /// được sang Command Mode (không bị kẹt ở ghi thường).
    @Test func controlWithinWindowWhileNormalRecordingSwitchesToCommandMode() {
        var m = recording(at: 0) // bắt đầu ghi thường ở 0.25
        #expect(m.handle(.leftControlDown, at: 0.35) == .startCommandRecording)
        if case .recordingCommand = m.phase {} else { Issue.record("phải ở recordingCommand, đang \(m.phase)") }
    }

    /// ⌃ trái đến SAU 400 ms ⇒ huỷ như luật cũ (tổ hợp phím khác), không vào Command Mode.
    @Test func controlAfterWindowCancelsLikeOtherCombo() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        #expect(m.handle(.leftControlDown, at: 0.41) == .none)
        #expect(m.phase == .suppressed)
    }

    @Test func controlAfterWindowDuringRecordingCancelsRecording() {
        var m = recording(at: 0) // ghi thường bắt đầu ở 0.25
        #expect(m.handle(.leftControlDown, at: 0.41) == .cancel(.otherInput))
        #expect(m.phase == .suppressed)
    }

    /// Nhả ⌃ trong lúc ghi lệnh KHÔNG kết thúc — chỉ nhả ⌥ mới dừng và gửi.
    @Test func releasingControlDuringCommandRecordingDoesNotEnd() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftControlDown, at: 0.1)
        #expect(m.handle(.leftControlUp, at: 0.5) == .none)
        if case .recordingCommand = m.phase {} else { Issue.record("vẫn phải ở recordingCommand") }
        #expect(m.handle(.leftOptionUp, at: 2) == .stopAndSendCommand(.released))
        if case .busyCommand = m.phase {} else { Issue.record("phải ở busyCommand") }
    }

    /// Phím khác trong lúc ghi lệnh ⇒ huỷ, chờ nhả ⌥.
    @Test func otherKeyDuringCommandRecordingCancels() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftControlDown, at: 0.1)
        #expect(m.handle(.keyDown, at: 0.5) == .cancel(.otherInput))
        #expect(m.phase == .suppressed)
    }

    /// Ghi lệnh tự gửi sau 120 s, giống ghi thường.
    @Test func commandRecordingAutoSendsAt120Seconds() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftControlDown, at: 0.1) // ⇒ recordingCommand(since: 0.1)
        #expect(m.tick(at: 120.05, optionHeld: true) == .none) // chưa đủ 120s kể từ 0.1
        #expect(m.tick(at: 120.2, optionHeld: true) == .stopAndSendCommand(.maxDuration))
    }

    /// Mất sự kiện nhả ⌥ trong lúc ghi lệnh ⇒ phát hiện qua trạng thái phím thật, vẫn gửi.
    @Test func commandRecordingRecoversLostReleaseEvent() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftControlDown, at: 0.1)
        #expect(m.tick(at: 1, optionHeld: false) == .stopAndSendCommand(.releaseMissed))
    }

    /// Không bao giờ ghi lệnh chồng lên khi đang bận (busyCommand).
    @Test func commandNeverOverlapsWhileBusy() {
        var m = HotkeyStateMachine()
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0)
        _ = m.handle(.leftControlDown, at: 0.1)
        _ = m.handle(.leftOptionUp, at: 0.5) // ⇒ busyCommand
        _ = m.handle(.leftOptionDown(othersHeld: false), at: 0.6)
        #expect(m.tick(at: 1, optionHeld: true) == .none) // vẫn busyCommand, không ghi chồng
        #expect(!m.isRecording)
    }
}

@Suite struct KeyClassifierTests {
    typealias K = KeyClassifier

    @Test func leftOptionDownAndUpUseDeviceBits() {
        let down = K.maskAlternate | K.deviceLeftOption
        #expect(K.classify(kind: .flagsChanged, keyCode: 58, flags: down) == .leftOptionDown(othersHeld: false))
        #expect(K.classify(kind: .flagsChanged, keyCode: 58, flags: 0) == .leftOptionUp)
        // ⌥ phải vẫn giữ (cờ chung alt còn) nhưng ⌥ trái đã nhả.
        #expect(K.classify(kind: .flagsChanged, keyCode: 58, flags: K.maskAlternate | K.deviceRightOption) == .leftOptionUp)
    }

    @Test func leftOptionWithCommandHeld() {
        let f = K.maskAlternate | K.deviceLeftOption | K.maskCommand | K.deviceLeftCommand
        #expect(K.classify(kind: .flagsChanged, keyCode: 58, flags: f) == .leftOptionDown(othersHeld: true))
        // Caps Lock bật sẵn không chặn.
        let caps = K.maskAlternate | K.deviceLeftOption | K.maskAlphaShift
        #expect(K.classify(kind: .flagsChanged, keyCode: 58, flags: caps) == .leftOptionDown(othersHeld: false))
    }

    @Test func rightOptionAndOtherModifiers() {
        let rightDown = K.maskAlternate | K.deviceRightOption | K.deviceLeftOption
        #expect(K.classify(kind: .flagsChanged, keyCode: 61, flags: rightDown) == .otherModifierDown)
        #expect(K.classify(kind: .flagsChanged, keyCode: 61, flags: K.maskAlternate | K.deviceLeftOption) == .otherModifierUp)
        #expect(K.classify(kind: .flagsChanged, keyCode: 55, flags: K.maskCommand | K.deviceLeftCommand) == .otherModifierDown)
        #expect(K.classify(kind: .flagsChanged, keyCode: 56, flags: K.maskShift | K.deviceLeftShift) == .otherModifierDown)
        #expect(K.classify(kind: .flagsChanged, keyCode: 62, flags: K.maskControl | K.deviceRightControl) == .otherModifierDown)
        #expect(K.classify(kind: .flagsChanged, keyCode: 57, flags: 0) == .otherModifierDown) // Caps Lock tắt cũng là “phím khác”
        #expect(K.classify(kind: .keyDown, keyCode: 0, flags: K.maskAlternate) == .keyDown)
        #expect(K.classify(kind: .keyUp, keyCode: 0, flags: 0) == .ignored)
        #expect(K.classify(kind: .mouseDown, keyCode: 0, flags: 0) == .mouseDown)
    }

    @Test func leftControlIsSeparateFromOtherModifiers() {
        #expect(K.classify(kind: .flagsChanged, keyCode: 59, flags: K.maskControl | K.deviceLeftControl) == .leftControlDown)
        #expect(K.classify(kind: .flagsChanged, keyCode: 59, flags: 0) == .leftControlUp)
        // ⌃ phải vẫn là tổ hợp chung, không phải Command Mode.
        #expect(K.classify(kind: .flagsChanged, keyCode: 62, flags: K.maskControl | K.deviceRightControl) == .otherModifierDown)
    }

    @Test func escapeKeyIsClassifiedSeparatelyFromOtherKeys() {
        #expect(K.classify(kind: .keyDown, keyCode: 53, flags: 0) == .escape)
        #expect(K.classify(kind: .keyDown, keyCode: 1, flags: 0) == .keyDown)
    }
}
