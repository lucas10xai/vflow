import AppKit
import CoreGraphics
import VFlowCore

/// Event tap CHỈ NGHE (listen-only) — cần quyền Input Monitoring, không chặn/sửa phím của người dùng.
@MainActor
final class HotkeyMonitor {
    var onInput: ((KeyInput) -> Void)?
    /// Hệ thống tắt tap (quá thời gian/đầu vào người dùng) — app phải reset máy trạng thái.
    var onTapDisabled: (() -> Void)?
    /// Tổ hợp "Chèn lại câu vừa rồi" (mặc định ⌥⌘V) khớp trên một `keyDown` ⇒ gọi, độc lập hoàn
    /// toàn với máy trạng thái "giữ để nói" (xem `HotkeyChord`).
    var onReinsertChord: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Đổi cài đặt giữa lúc đang ghi KHÔNG được làm hỏng cử chỉ đang chạy — chỉ áp dụng ngay khi máy
    /// trạng thái đang rảnh (xem `VFlowCore.ActiveHotkeyConfig`). `AppController` gán `isIdle`.
    private var keyConfigState = ActiveHotkeyConfig()
    var isIdle: (() -> Bool) = { true }
    var reinsertChord: HotkeyChord = .reinsertDefault

    var keyConfig: HotkeyKeyConfig {
        get { keyConfigState.desired }
        set { keyConfigState.desired = newValue }
    }

    var isRunning: Bool { tap != nil }

    /// false ⇒ không tạo được tap (thường do thiếu quyền Input Monitoring).
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: hotkeyTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        source = src
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: UInt64) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            onTapDisabled?()
            return
        }
        // Cơ hội áp dụng cấu hình phím mới (chỉ khi đang rảnh — xem `ActiveHotkeyConfig`).
        keyConfigState.refresh(isIdle: isIdle())
        if type == .keyDown, reinsertChord.matches(keyCode: keyCode, flags: flags) {
            onReinsertChord?()
        }
        let kind: KeyClassifier.EventKind
        switch type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
        default: kind = .other
        }
        let input = KeyClassifier.classify(kind: kind, keyCode: keyCode, flags: flags, config: keyConfigState.active)
        if input != .ignored { onInput?(input) }
    }

    /// Trạng thái thật của phím giữ ĐANG áp dụng (để hồi phục khi mất sự kiện nhả phím).
    func leftOptionHeldNow() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyConfigState.active.holdKey.keyCode))
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // Nguồn tap gắn vào run loop chính ⇒ callback chạy trên luồng chính.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        MainActor.assumeIsolated { monitor.handle(type: type, keyCode: keyCode, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}
