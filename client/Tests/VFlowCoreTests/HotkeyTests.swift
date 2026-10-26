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
}
