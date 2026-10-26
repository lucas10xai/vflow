import AppKit
import CoreGraphics
import VFlowCore

/// Event tap CHỈ NGHE (listen-only) — cần quyền Input Monitoring, không chặn/sửa phím của người dùng.
@MainActor
final class HotkeyMonitor {
    var onInput: ((KeyInput) -> Void)?
    /// Hệ thống tắt tap (quá thời gian/đầu vào người dùng) — app phải reset máy trạng thái.
    var onTapDisabled: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

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
        let kind: KeyClassifier.EventKind
        switch type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
        default: kind = .other
        }
        let input = KeyClassifier.classify(kind: kind, keyCode: keyCode, flags: flags)
        if input != .ignored { onInput?(input) }
    }

    /// Trạng thái thật của ⌥ trái (để hồi phục khi mất sự kiện nhả phím).
    static func leftOptionHeldNow() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(KeyClassifier.keyCodeLeftOption))
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
