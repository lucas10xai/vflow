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
    /// Ghi khoá (hands-free) có thể dài hơn giữ-phím-thường tuỳ engine báo (xem contract mục 7c,
    /// `VFlowCore.RecordingLimit`) — vì vậy KHÔNG còn `let`: `AppController` đổi giá trị này MỖI
    /// LẦN bắt đầu một lượt ghi mới (lúc máy đang `.idle`, không ảnh hưởng lượt đang chạy).
    public var maxRecording: TimeInterval
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

/// Một trong 4 phím bổ trợ ĐƠN an toàn chọn được cho "giữ để nói"/Command Mode (Cài đặt › Phím
/// tắt). CỐ Ý loại ⇧ và ⌘ (dễ gõ nhầm khi dùng bình thường) và Fn (không đọc được ổn định trên mọi
/// loại bàn phím/máy qua CGEvent — chưa kiểm được trong môi trường này, xem README).
public enum HoldModifierKey: String, CaseIterable, Codable, Sendable {
    case leftOption, rightOption, leftControl, rightControl

    public var title: String {
        switch self {
        case .leftOption: return "⌥ trái"
        case .rightOption: return "⌥ phải"
        case .leftControl: return "⌃ trái"
        case .rightControl: return "⌃ phải"
        }
    }

    public var keyCode: Int64 {
        switch self {
        case .leftOption: return KeyClassifier.keyCodeLeftOption
        case .rightOption: return 61
        case .leftControl: return KeyClassifier.keyCodeLeftControl
        case .rightControl: return 62
        }
    }

    public var deviceBit: UInt64 {
        switch self {
        case .leftOption: return KeyClassifier.deviceLeftOption
        case .rightOption: return KeyClassifier.deviceRightOption
        case .leftControl: return KeyClassifier.deviceLeftControl
        case .rightControl: return KeyClassifier.deviceRightControl
        }
    }
}

/// Cấu hình phím "giữ để nói" + phím thứ hai bật Command Mode — hai phím PHẢI khác nhau (xem
/// `HotkeyConfigValidation`). Mặc định giữ ĐÚNG hành vi cũ (⌥ trái / ⌃ trái).
public struct HotkeyKeyConfig: Equatable, Sendable, Codable {
    public var holdKey: HoldModifierKey
    public var commandKey: HoldModifierKey

    public init(holdKey: HoldModifierKey = .leftOption, commandKey: HoldModifierKey = .leftControl) {
        self.holdKey = holdKey
        self.commandKey = commandKey
    }

    public static let defaultConfig = HotkeyKeyConfig()
}

/// Áp dụng cấu hình phím nóng mới NGAY khi máy trạng thái đang RẢNH; đổi cài đặt giữa lúc đang ghi
/// KHÔNG được làm hỏng cử chỉ đang chạy — cử chỉ hiện tại tiếp tục dùng `active` cho tới khi về rảnh
/// (xem contract mục Phím tắt tuỳ chỉnh, test "giữ khi đổi phím lúc đang ghi âm").
public struct ActiveHotkeyConfig: Sendable {
    public private(set) var active: HotkeyKeyConfig
    public var desired: HotkeyKeyConfig

    public init(_ config: HotkeyKeyConfig = .defaultConfig) {
        self.active = config
        self.desired = config
    }

    /// Gọi mỗi khi có dịp (mỗi sự kiện phím) kèm biết máy đang rảnh hay không; chỉ copy
    /// `desired` sang `active` khi đang rảnh.
    public mutating func refresh(isIdle: Bool) {
        if isIdle { active = desired }
    }
}

/// Kiểm hợp lệ cấu hình phím tắt (Cài đặt › Phím tắt) — thuần, test được.
public enum HotkeyConfigValidation {
    /// Hai phím (giữ để nói, Command Mode) không được giống nhau.
    public static func keysConflict(_ config: HotkeyKeyConfig) -> Bool {
        config.holdKey == config.commandKey
    }

    /// Thông điệp tiếng Việt khi trùng phím, `nil` khi hợp lệ.
    public static func conflictMessage(_ config: HotkeyKeyConfig) -> String? {
        guard keysConflict(config) else { return nil }
        return "Phím \"giữ để nói\" và phím Command Mode đang trùng nhau (\(config.holdKey.title)) — chọn hai phím khác nhau."
    }
}

/// Một tổ hợp phím bổ trợ + một phím chữ/số thường (vd. ⌥⌘V) — dùng cho "Chèn lại câu vừa rồi",
/// khác hẳn kiểu "giữ phím đơn" ở trên (đây là tổ hợp bấm-nhả một lần, không phải giữ).
public struct HotkeyChord: Equatable, Sendable, Codable {
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    /// Mã phím ảo (virtual keycode) của phím chữ/số chính, vd. 9 = "V".
    public var keyCode: Int64

    public init(command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false, keyCode: Int64) {
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.keyCode = keyCode
    }

    /// Mặc định ⌥⌘V cho "Chèn lại câu vừa rồi".
    public static let reinsertDefault = HotkeyChord(command: true, option: true, keyCode: 9)

    /// Có khớp một sự kiện keyDown (mã phím ảo + cờ CGEventFlags thô) không — so khớp CHÍNH XÁC
    /// bộ phím bổ trợ (không khớp nếu có thêm phím bổ trợ khác đang giữ, tránh bắt nhầm).
    public func matches(keyCode: Int64, flags: UInt64) -> Bool {
        guard keyCode == self.keyCode else { return false }
        let hasCommand = flags & KeyClassifier.maskCommand != 0
        let hasOption = flags & KeyClassifier.maskAlternate != 0
        let hasControl = flags & KeyClassifier.maskControl != 0
        let hasShift = flags & KeyClassifier.maskShift != 0
        return hasCommand == command && hasOption == option && hasControl == control && hasShift == shift
    }
}

/// Hai tổ hợp phím tắt (vd. Command Mode dạng tổ hợp + Chèn lại câu vừa rồi) trùng nhau không —
/// dùng ở Cài đặt › Phím tắt để cảnh báo.
public enum HotkeyChordValidation {
    public static func conflict(_ a: HotkeyChord, _ b: HotkeyChord) -> Bool { a == b }
}

/// Vài tổ hợp cố định chọn được cho "Chèn lại câu vừa rồi" ở Cài đặt › Phím tắt — KHÔNG phải một ô
/// ghi phím tự do (an toàn hơn: không có nguy cơ ghi nhầm/ghi phím không hợp lệ khi không kiểm thử
/// được bàn phím thật trong môi trường này).
public enum ReinsertChordPreset: String, CaseIterable, Sendable {
    case optionCommandV, controlCommandV, optionCommandR

    public var chord: HotkeyChord {
        switch self {
        case .optionCommandV: return .reinsertDefault
        case .controlCommandV: return HotkeyChord(command: true, control: true, keyCode: 9)
        case .optionCommandR: return HotkeyChord(command: true, option: true, keyCode: 15)
        }
    }

    public var title: String {
        switch self {
        case .optionCommandV: return "⌥⌘V (mặc định)"
        case .controlCommandV: return "⌃⌘V"
        case .optionCommandR: return "⌥⌘R"
        }
    }

    /// `nil` khi `chord` không khớp preset nào (vd. dữ liệu cũ/hỏng) — Cài đặt rơi về mặc định.
    public static func matching(_ chord: HotkeyChord) -> ReinsertChordPreset? {
        allCases.first { $0.chord == chord }
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
    /// Mã phím ảo ⇒ bit nhận biết “đang xuống” của MỌI phím bổ trợ (kể cả 4 phím chọn được ở
    /// `HoldModifierKey`) — dùng làm phương án dự phòng khi một phím KHÔNG được chọn làm vai trò
    /// giữ/Command Mode hiện tại (vd. đổi phím giữ sang ⌃ trái ⇒ ⌥ trái rơi về "phím khác" bình thường).
    static let allModifierBits: [Int64: UInt64] = [
        54: deviceRightCommand, 55: deviceLeftCommand,
        56: deviceLeftShift, 60: deviceRightShift,
        58: deviceLeftOption, 61: deviceRightOption,
        59: deviceLeftControl, 62: deviceRightControl,
        63: maskSecondaryFn, 57: maskAlphaShift,
    ]
    /// Bit của 4 phím CHỌN ĐƯỢC (xem `HoldModifierKey`) — dùng để tính `othersHeld` tổng quát.
    private static let candidateBits: UInt64 = HoldModifierKey.allCases.reduce(0) { $0 | $1.deviceBit }

    public static func classify(kind: EventKind, keyCode: Int64, flags: UInt64,
                                config: HotkeyKeyConfig = .defaultConfig) -> KeyInput {
        switch kind {
        case .keyDown: return keyCode == keyCodeEscape ? .escape : .keyDown
        case .mouseDown: return .mouseDown
        case .keyUp, .other: return .ignored
        case .flagsChanged:
            let hold = config.holdKey
            let cmd = config.commandKey
            if keyCode == hold.keyCode {
                guard flags & hold.deviceBit != 0 else { return .leftOptionUp }
                return .leftOptionDown(othersHeld: othersHeld(flags, holdBit: hold.deviceBit))
            }
            if keyCode == cmd.keyCode {
                return flags & cmd.deviceBit != 0 ? .leftControlDown : .leftControlUp
            }
            if keyCode == 57 { return .otherModifierDown } // Caps Lock: mỗi lần bấm đều là “phím khác”
            if let bit = allModifierBits[keyCode] {
                return flags & bit != 0 ? .otherModifierDown : .otherModifierUp
            }
            return .ignored
        }
    }

    /// Có phím bổ trợ KHÁC (⌘/⇧ luôn, hoặc bất kỳ phím nào trong 4 phím chọn được trừ chính phím
    /// giữ) đang giữ SẴN tại thời điểm phím giữ vừa xuống không — combo như vậy huỷ cử chỉ ngay
    /// (vd. ⌥-click, ⌥←, hoặc ⌃ đã giữ trước ⌥ thì không tính là khởi động Command Mode đúng thứ tự).
    public static func othersHeld(_ flags: UInt64, holdBit: UInt64 = deviceLeftOption) -> Bool {
        flags & (maskCommand | maskShift | (candidateBits & ~holdBit)) != 0
    }

    public static func leftOptionHeld(_ flags: UInt64, holdBit: UInt64 = deviceLeftOption) -> Bool {
        flags & holdBit != 0
    }
}
