import Foundation

/// Sự kiện bàn phím/chuột đã phân loại (độc lập AppKit/CGEvent).
public enum KeyInput: Equatable, Sendable {
    /// ⌥ trái xuống; `othersHeld` = đang giữ ⌘/⌃/⇧/⌥ phải.
    case leftOptionDown(othersHeld: Bool)
    case leftOptionUp
    /// ⌥ phải, ⌘, ⌃, ⇧, fn, Caps Lock.
    case otherModifierDown
    case otherModifierUp
    /// Mọi phím thường (kể cả tự lặp).
    case keyDown
    case mouseDown
    /// Sự kiện không liên quan (keyUp…).
    case ignored
}

public enum SendReason: Equatable, Sendable {
    case released
    /// Đủ 120 s, tự gửi.
    case maxDuration
    /// Mất sự kiện nhả phím; phát hiện qua trạng thái phím thật.
    case releaseMissed
}

public enum CancelReason: Equatable, Sendable {
    case otherInput
    /// Event tap bị tắt/khởi động lại, không chắc người dùng muốn gửi.
    case reset
}

public enum HotkeyAction: Equatable, Sendable {
    case none
    case startRecording
    case stopAndSend(SendReason)
    case cancel(CancelReason)
    /// Đang dịch quá lâu (mất phản hồi) ⇒ trả về rảnh.
    case busyTimedOut
}

public enum HotkeyPhase: Equatable, Sendable {
    case idle
    /// ⌥ trái đang giữ, chưa đủ ngưỡng.
    case armed(since: TimeInterval)
    /// ⌥ đang dùng cho việc khác (tổ hợp phím) ⇒ bỏ qua tới khi nhả.
    case suppressed
    case recording(since: TimeInterval)
    /// Đã gửi, chờ kết quả; không nhận lần ghi mới.
    case busy(since: TimeInterval)
}

/// Máy trạng thái phím nóng “giữ ⌥ trái”. Thuần: thời gian truyền vào, không timer.
/// App gọi `tick` định kỳ (khoảng 50 ms) khi không ở `idle`.
public struct HotkeyStateMachine: Sendable {
    public static let defaultHoldThreshold: TimeInterval = 0.2
    public static let defaultMaxRecording: TimeInterval = 120
    public static let defaultBusyTimeout: TimeInterval = 200

    public let holdThreshold: TimeInterval
    public let maxRecording: TimeInterval
    public let busyTimeout: TimeInterval
    public private(set) var phase: HotkeyPhase = .idle

    public init(holdThreshold: TimeInterval = defaultHoldThreshold,
                maxRecording: TimeInterval = defaultMaxRecording,
                busyTimeout: TimeInterval = defaultBusyTimeout) {
        self.holdThreshold = holdThreshold
        self.maxRecording = maxRecording
        self.busyTimeout = busyTimeout
    }

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    public var needsTicks: Bool { phase != .idle }

    public mutating func handle(_ input: KeyInput, at now: TimeInterval) -> HotkeyAction {
        switch (phase, input) {
        case (_, .ignored), (_, .otherModifierUp):
            return .none

        case (.idle, .leftOptionDown(let othersHeld)):
            phase = othersHeld ? .suppressed : .armed(since: now)
            return .none
        case (.idle, _):
            return .none

        case (.armed, .leftOptionUp):
            phase = .idle // chạm nhanh: bỏ qua hoàn toàn
            return .none
        case (.armed, .keyDown), (.armed, .otherModifierDown), (.armed, .mouseDown):
            phase = .suppressed // ⌥ đang làm việc khác (⌥←, ⌥-click, ký tự đặc biệt…)
            return .none
        case (.armed, .leftOptionDown):
            return .none

        case (.suppressed, .leftOptionUp):
            phase = .idle
            return .none
        case (.suppressed, _):
            return .none

        case (.recording, .leftOptionUp):
            phase = .busy(since: now)
            return .stopAndSend(.released)
        case (.recording, .keyDown), (.recording, .otherModifierDown), (.recording, .mouseDown):
            phase = .suppressed // ⌥ vẫn đang giữ: chờ nhả rồi mới về rảnh
            return .cancel(.otherInput)
        case (.recording, .leftOptionDown):
            return .none

        case (.busy, _):
            return .none // không bao giờ ghi chồng
        }
    }

    /// `optionHeld`: trạng thái thật của ⌥ trái lúc này (để hồi phục khi mất sự kiện).
    public mutating func tick(at now: TimeInterval, optionHeld: Bool) -> HotkeyAction {
        switch phase {
        case .idle:
            return .none
        case .armed(let since):
            if !optionHeld { phase = .idle; return .none }
            if now - since >= holdThreshold {
                phase = .recording(since: now)
                return .startRecording
            }
            return .none
        case .suppressed:
            if !optionHeld { phase = .idle }
            return .none
        case .recording(let since):
            if now - since >= maxRecording {
                phase = .busy(since: now)
                return .stopAndSend(.maxDuration)
            }
            if !optionHeld {
                phase = .busy(since: now)
                return .stopAndSend(.releaseMissed)
            }
            return .none
        case .busy(let since):
            if now - since >= busyTimeout {
                phase = optionHeld ? .suppressed : .idle
                return .busyTimedOut
            }
            return .none
        }
    }

    /// Kết quả (thành công hay lỗi) đã về. Nếu ⌥ vẫn đang giữ thì chờ nhả, không tự ghi lại.
    public mutating func finished(optionHeld: Bool) {
        if case .busy = phase { phase = optionHeld ? .suppressed : .idle }
    }

    /// Việc ngoài phím nóng (menu “Thử lại lần cuối”): chỉ nhận khi đang rảnh.
    public mutating func beginExternalJob(at now: TimeInterval) -> Bool {
        guard phase == .idle else { return false }
        phase = .busy(since: now)
        return true
    }

    /// Event tap bị hệ thống tắt hoặc app mất dấu sự kiện.
    public mutating func reset(optionHeld: Bool) -> HotkeyAction {
        switch phase {
        case .recording:
            phase = optionHeld ? .suppressed : .idle
            return .cancel(.reset)
        case .busy:
            return .none
        default:
            phase = optionHeld ? .suppressed : .idle
            return .none
        }
    }
}

/// Phân loại sự kiện CGEvent thô (mã phím ảo + cờ) thành `KeyInput`. Thuần để test.
public enum KeyClassifier {
    public enum EventKind: Sendable { case flagsChanged, keyDown, keyUp, mouseDown, other }

    // Bit cờ phụ thuộc thiết bị (IOKit NX_DEVICE*KEYMASK) và cờ chung CGEventFlags.
    public static let deviceLeftControl: UInt64 = 0x0000_0001
    public static let deviceLeftShift: UInt64 = 0x0000_0002
    public static let deviceRightShift: UInt64 = 0x0000_0004
    public static let deviceLeftCommand: UInt64 = 0x0000_0008
    public static let deviceRightCommand: UInt64 = 0x0000_0010
    public static let deviceLeftOption: UInt64 = 0x0000_0020
    public static let deviceRightOption: UInt64 = 0x0000_0040
    public static let deviceRightControl: UInt64 = 0x0000_2000
    public static let maskAlphaShift: UInt64 = 0x0001_0000
    public static let maskShift: UInt64 = 0x0002_0000
    public static let maskControl: UInt64 = 0x0004_0000
    public static let maskAlternate: UInt64 = 0x0008_0000
    public static let maskCommand: UInt64 = 0x0010_0000
    public static let maskSecondaryFn: UInt64 = 0x0080_0000

    public static let keyCodeLeftOption: Int64 = 58
    /// Mã phím ảo của các phím bổ trợ khác ⇒ bit nhận biết “đang xuống”.
    static let otherModifierBits: [Int64: UInt64] = [
        54: deviceRightCommand, 55: deviceLeftCommand,
        56: deviceLeftShift, 60: deviceRightShift,
        59: deviceLeftControl, 62: deviceRightControl,
        61: deviceRightOption, 63: maskSecondaryFn, 57: maskAlphaShift,
    ]

    public static func classify(kind: EventKind, keyCode: Int64, flags: UInt64) -> KeyInput {
        switch kind {
        case .keyDown: return .keyDown
        case .mouseDown: return .mouseDown
        case .keyUp, .other: return .ignored
        case .flagsChanged:
            if keyCode == keyCodeLeftOption {
                guard flags & deviceLeftOption != 0 else { return .leftOptionUp }
                return .leftOptionDown(othersHeld: othersHeld(flags))
            }
            if let bit = otherModifierBits[keyCode] {
                if keyCode == 57 { return .otherModifierDown } // Caps Lock: mỗi lần bấm đều là “phím khác”
                return flags & bit != 0 ? .otherModifierDown : .otherModifierUp
            }
            return .ignored
        }
    }

    /// ⌘/⌃/⇧/⌥ phải đang giữ (bỏ qua Caps Lock và fn vì chúng có thể bật sẵn).
    public static func othersHeld(_ flags: UInt64) -> Bool {
        flags & (maskCommand | maskControl | maskShift | deviceRightOption) != 0
    }

    public static func leftOptionHeld(_ flags: UInt64) -> Bool {
        flags & deviceLeftOption != 0
    }
}
