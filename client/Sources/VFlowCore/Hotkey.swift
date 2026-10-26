import Foundation

/// Sự kiện bàn phím/chuột đã phân loại (độc lập AppKit/CGEvent).
public enum KeyInput: Equatable, Sendable {
    /// ⌥ trái xuống; `othersHeld` = đang giữ ⌘/⌃/⇧/⌥ phải.
    case leftOptionDown(othersHeld: Bool)
    case leftOptionUp
    /// ⌃ trái xuống/lên — tách riêng khỏi `otherModifierDown/Up` vì dùng làm tổ hợp Command Mode.
    case leftControlDown
    case leftControlUp
    /// ⌥ phải, ⌘, ⌃ phải, ⇧, fn, Caps Lock.
    case otherModifierDown
    case otherModifierUp
    /// Mọi phím thường (kể cả tự lặp).
    case keyDown
    /// Esc — huỷ ghi âm ở bất kỳ chế độ ghi nào (xem `HotkeyStateMachine`), không chặn ở ứng dụng khác.
    case escape
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
    /// Esc trong lúc ghi.
    case escape
    /// Event tap bị tắt/khởi động lại, không chắc người dùng muốn gửi.
    case reset
}

public enum HotkeyAction: Equatable, Sendable {
    case none
    case startRecording
    case stopAndSend(SendReason)
    /// ⌃ trái nhận được trong 400 ms đầu của lần giữ ⌥ ⇒ chuyển sang ghi lệnh (Command Mode).
    case startCommandRecording
    case stopAndSendCommand(SendReason)
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
    /// Ghi "khoá" (hands-free, bắt đầu bằng đúp ⌥): không cần giữ phím; nhả/giữ ⌥ không ảnh hưởng,
    /// chỉ bấm ⌥ một lần nữa (hoặc Esc) mới kết thúc.
    case recordingLocked(since: TimeInterval)
    /// Command Mode: đang ghi lệnh (sau khi ⌃ trái nhận được trong 400 ms đầu giữ ⌥).
    case recordingCommand(since: TimeInterval)
    /// Đã gửi, chờ kết quả; không nhận lần ghi mới.
    case busy(since: TimeInterval)
    /// Đã gửi lệnh Command Mode, chờ kết quả.
    case busyCommand(since: TimeInterval)
}

/// Máy trạng thái phím nóng “giữ ⌥ trái” (+ hands-free đúp ⌥ khoá, + Command Mode ⌥+⌃, + Esc huỷ).
/// Thuần: thời gian truyền vào, không timer. App gọi `tick` định kỳ (khoảng 50 ms) khi không ở `idle`.
public struct HotkeyStateMachine: Sendable {
    public static let defaultHoldThreshold: TimeInterval = 0.2
    public static let defaultMaxRecording: TimeInterval = 120
    public static let defaultBusyTimeout: TimeInterval = 200
    /// Khoảng cách tối đa giữa hai lần chạm ⌥ để tính là đúp (hands-free khoá).
    public static let defaultDoubleTapGap: TimeInterval = 0.35
    /// ⌃ trái phải nhận được trong khoảng này kể từ lúc ⌥ trái xuống để chuyển thành Command Mode.
    public static let defaultCommandWindow: TimeInterval = 0.4

    public let holdThreshold: TimeInterval
    public let maxRecording: TimeInterval
    public let busyTimeout: TimeInterval
    public let doubleTapGap: TimeInterval
    public let commandWindow: TimeInterval
    public private(set) var phase: HotkeyPhase = .idle

    /// Thời điểm nhả của lần chạm ⌥ nhanh gần nhất (chưa tiêu) — để phát hiện đúp.
    private var lastQuickTapUpAt: TimeInterval?
    /// Thời điểm ⌥ trái xuống của lần giữ hiện tại — để tính cửa sổ 400 ms cho ⌃ (độc lập khỏi
    /// `since` của `.recording`, vì `since` đó là lúc ĐÃ qua ngưỡng 200 ms, không phải lúc ⌥ xuống).
    private var optionDownAt: TimeInterval?

    public init(holdThreshold: TimeInterval = defaultHoldThreshold,
                maxRecording: TimeInterval = defaultMaxRecording,
                busyTimeout: TimeInterval = defaultBusyTimeout,
                doubleTapGap: TimeInterval = defaultDoubleTapGap,
                commandWindow: TimeInterval = defaultCommandWindow) {
        self.holdThreshold = holdThreshold
        self.maxRecording = maxRecording
        self.busyTimeout = busyTimeout
        self.doubleTapGap = doubleTapGap
        self.commandWindow = commandWindow
    }

    public var isRecording: Bool {
        switch phase {
        case .recording, .recordingLocked, .recordingCommand: return true
        default: return false
        }
    }

    /// Ghi "khoá" (hands-free) — thanh trạng thái hiện chữ khác với ghi "giữ phím".
    public var isLocked: Bool {
        if case .recordingLocked = phase { return true }
        return false
    }

    public var needsTicks: Bool { phase != .idle }

    /// Giây còn lại trước khi tự gửi (120 s), `nil` khi không đang ghi — dùng để hiện cảnh báo ở
    /// giây thứ 100 (xem `HotkeyStateMachine.defaultMaxRecording`).
    public func secondsRemaining(at now: TimeInterval) -> TimeInterval? {
        switch phase {
        case .recording(let since), .recordingLocked(let since), .recordingCommand(let since):
            return maxRecording - (now - since)
        default:
            return nil
        }
    }

    public mutating func handle(_ input: KeyInput, at now: TimeInterval) -> HotkeyAction {
        switch (phase, input) {
        case (_, .ignored), (_, .otherModifierUp), (_, .leftControlUp):
            return .none

        case (.idle, .leftOptionDown(let othersHeld)):
            optionDownAt = now
            phase = othersHeld ? .suppressed : .armed(since: now)
            return .none
        case (.idle, _):
            return .none

        case (.armed, .leftOptionUp):
            // Chạm nhanh (<200 ms, vì chưa qua ngưỡng mới tới đây): đúp trong `doubleTapGap` ⇒ khoá
            // ghi hands-free; ngược lại bỏ qua hoàn toàn và nhớ lại để so với lần chạm kế tiếp.
            phase = .idle
            if let last = lastQuickTapUpAt, now - last <= doubleTapGap {
                lastQuickTapUpAt = nil
                phase = .recordingLocked(since: now)
                return .startRecording
            }
            lastQuickTapUpAt = now
            return .none
        case (.armed(let since), .leftControlDown):
            if now - (optionDownAt ?? since) < commandWindow {
                phase = .recordingCommand(since: now)
                return .startCommandRecording
            }
            phase = .suppressed // ⌃ tới muộn: huỷ tổ hợp như luật cũ, chưa ghi gì nên không cần cancel
            return .none
        case (.armed, .keyDown), (.armed, .otherModifierDown), (.armed, .mouseDown):
            phase = .suppressed // ⌥ đang làm việc khác (⌥←, ⌥-click, ký tự đặc biệt…)
            return .none
        case (.armed, .leftOptionDown):
            return .none
        case (.armed, .escape):
            phase = .suppressed
            return .none

        case (.suppressed, .leftOptionUp):
            phase = .idle
            return .none
        case (.suppressed, _):
            return .none

        case (.recording, .leftOptionUp):
            phase = .busy(since: now)
            return .stopAndSend(.released)
        case (.recording(let since), .leftControlDown):
            if now - (optionDownAt ?? since) < commandWindow {
                phase = .recordingCommand(since: now)
                return .startCommandRecording
            }
            phase = .suppressed // ⌥ vẫn đang giữ: chờ nhả rồi mới về rảnh
            return .cancel(.otherInput)
        case (.recording, .keyDown), (.recording, .otherModifierDown), (.recording, .mouseDown):
            phase = .suppressed // ⌥ vẫn đang giữ: chờ nhả rồi mới về rảnh
            return .cancel(.otherInput)
        case (.recording, .leftOptionDown):
            return .none
        case (.recording, .escape):
            phase = .suppressed // ⌥ vẫn đang giữ (ghi kiểu giữ phím): chờ nhả rồi mới về rảnh
            return .cancel(.escape)

        // Ghi khoá (hands-free): không cần giữ ⌥; nhả/giữ không ảnh hưởng, chỉ bấm ⌥ một lần nữa
        // (down rồi up) mới kết thúc — phản ứng ở sự kiện nhả.
        case (.recordingLocked, .leftOptionDown(let othersHeld)):
            if othersHeld {
                phase = .idle
                return .cancel(.otherInput)
            }
            return .none
        case (.recordingLocked, .leftOptionUp):
            phase = .busy(since: now)
            return .stopAndSend(.released)
        case (.recordingLocked, .keyDown), (.recordingLocked, .otherModifierDown),
             (.recordingLocked, .mouseDown), (.recordingLocked, .leftControlDown):
            phase = .idle // không có phím nào đang giữ để chờ nhả
            return .cancel(.otherInput)
        case (.recordingLocked, .escape):
            phase = .idle
            return .cancel(.escape)

        // Command Mode: ⌃ chỉ là phím khởi động (down edge); nhả ⌃ không kết thúc, chỉ nhả ⌥ mới
        // dừng và gửi (giống ghi kiểu giữ phím) — cho phép nhả ⌃ sớm mà vẫn tiếp tục nói lệnh.
        case (.recordingCommand, .leftOptionUp):
            phase = .busyCommand(since: now)
            return .stopAndSendCommand(.released)
        case (.recordingCommand, .keyDown), (.recordingCommand, .otherModifierDown), (.recordingCommand, .mouseDown):
            phase = .suppressed
            return .cancel(.otherInput)
        case (.recordingCommand, .leftOptionDown), (.recordingCommand, .leftControlDown):
            return .none
        case (.recordingCommand, .escape):
            phase = .suppressed
            return .cancel(.escape)

        case (.busy, _), (.busyCommand, _):
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
        case .recordingLocked(let since):
            // Không kiểm `optionHeld`: ghi khoá không cần giữ phím, chỉ hết giờ mới tự gửi.
            if now - since >= maxRecording {
                phase = .busy(since: now)
                return .stopAndSend(.maxDuration)
            }
            return .none
        case .recordingCommand(let since):
            if now - since >= maxRecording {
                phase = .busyCommand(since: now)
                return .stopAndSendCommand(.maxDuration)
            }
            if !optionHeld {
                phase = .busyCommand(since: now)
                return .stopAndSendCommand(.releaseMissed)
            }
            return .none
        case .busy(let since):
            if now - since >= busyTimeout {
                phase = optionHeld ? .suppressed : .idle
                return .busyTimedOut
            }
            return .none
        case .busyCommand(let since):
            if now - since >= busyTimeout {
                phase = optionHeld ? .suppressed : .idle
                return .busyTimedOut
            }
            return .none
        }
    }

    /// Kết quả (thành công hay lỗi) đã về. Nếu ⌥ vẫn đang giữ thì chờ nhả, không tự ghi lại.
    public mutating func finished(optionHeld: Bool) {
        switch phase {
        case .busy, .busyCommand: phase = optionHeld ? .suppressed : .idle
        default: break
        }
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
        case .recording, .recordingCommand:
            phase = optionHeld ? .suppressed : .idle
            return .cancel(.reset)
        case .recordingLocked:
            phase = .idle
            return .cancel(.reset)
        case .busy, .busyCommand:
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
    public static let keyCodeLeftControl: Int64 = 59
    public static let keyCodeEscape: Int64 = 53
    /// Mã phím ảo của các phím bổ trợ khác (trừ ⌃ trái, ⌥ trái — tách riêng) ⇒ bit nhận biết “đang xuống”.
    static let otherModifierBits: [Int64: UInt64] = [
        54: deviceRightCommand, 55: deviceLeftCommand,
        56: deviceLeftShift, 60: deviceRightShift,
        62: deviceRightControl,
        61: deviceRightOption, 63: maskSecondaryFn, 57: maskAlphaShift,
    ]

    public static func classify(kind: EventKind, keyCode: Int64, flags: UInt64) -> KeyInput {
        switch kind {
        case .keyDown: return keyCode == keyCodeEscape ? .escape : .keyDown
        case .mouseDown: return .mouseDown
        case .keyUp, .other: return .ignored
        case .flagsChanged:
            if keyCode == keyCodeLeftOption {
                guard flags & deviceLeftOption != 0 else { return .leftOptionUp }
                return .leftOptionDown(othersHeld: othersHeld(flags))
            }
            if keyCode == keyCodeLeftControl {
                return flags & deviceLeftControl != 0 ? .leftControlDown : .leftControlUp
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
