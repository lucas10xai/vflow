import Foundation

/// Ba quyền macOS cần (xem client/README.md). Dữ liệu thuần: tên, lý do, nơi mở Cài đặt.
/// Việc hỏi quyền/kiểm trạng thái thật nằm ở lớp AppKit (`client/Sources/VFlow/Permissions.swift`),
/// vì chỉ có một nguồn dữ liệu nên menu và cửa sổ không bao giờ nói khác nhau.
public enum PermissionKind: String, CaseIterable, Sendable {
    case microphone
    case inputMonitoring
    case accessibility

    public var title: String {
        switch self {
        case .microphone: "Micro"
        case .inputMonitoring: "Theo dõi đầu vào (Input Monitoring)"
        case .accessibility: "Trợ năng (Accessibility)"
        }
    }

    public var why: String {
        switch self {
        case .microphone: "ghi giọng nói khi giữ ⌥ trái"
        case .inputMonitoring: "nhận biết khi giữ/nhả phím ⌥ trái ở mọi ứng dụng"
        case .accessibility: "dán chữ (⌘V) vào ứng dụng đang dùng"
        }
    }

    /// SF Symbol minh họa quyền, dùng cho cửa sổ trạng thái.
    public var symbol: String {
        switch self {
        case .microphone: "mic"
        case .inputMonitoring: "keyboard"
        case .accessibility: "accessibility"
        }
    }

    /// Mỏ neo trang System Settings tương ứng (`x-apple.systempreferences:com.apple.preference.security?<anchor>`).
    public var settingsAnchor: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
    }
}

/// Trạng thái hiện tại của một quyền (snapshot thuần, không gọi API hệ thống).
public struct PermissionItem: Equatable, Sendable {
    public var kind: PermissionKind
    public var granted: Bool

    public init(kind: PermissionKind, granted: Bool) {
        self.kind = kind
        self.granted = granted
    }

    public var statusText: String { granted ? "Đã cấp" : "Chưa cấp" }
}

/// Một ứng dụng đọc chính tả khác có thể dùng chung phím ⌥ trái.
public struct ConflictApp: Equatable, Sendable {
    public var bundleId: String
    public var displayName: String

    public init(bundleId: String, displayName: String) {
        self.bundleId = bundleId
        self.displayName = displayName
    }
}

public enum ConflictConfig {
    /// Danh sách mặc định; đầu tiên là Haynoi (nguồn gốc đặt ra bài toán này).
    public static let defaults: [ConflictApp] = [
        ConflictApp(bundleId: "com.sonpiaz.haynoi", displayName: "Haynoi"),
    ]
}

/// Nguồn danh sách tiến trình đang chạy — để test được bằng bộ cung cấp giả,
/// không gọi `NSWorkspace` trực tiếp trong VFlowCore (thuần, không AppKit).
public protocol RunningAppsProvider: Sendable {
    func runningBundleIDs() -> Set<String>
}

/// Dò ứng dụng đọc chính tả khác đang chạy có thể đụng phím ⌥ trái.
public struct ConflictDetector: Sendable {
    public var candidates: [ConflictApp]

    public init(candidates: [ConflictApp] = ConflictConfig.defaults) {
        self.candidates = candidates
    }

    /// Giữ thứ tự của `candidates`; có thể nhiều hơn 1 nhưng cảnh báo chỉ nói ứng dụng đầu tiên.
    public func detect(runningBundleIDs: Set<String>) -> [ConflictApp] {
        candidates.filter { runningBundleIDs.contains($0.bundleId) }
    }
}

public enum ConflictText {
    public static func warning(for apps: [ConflictApp]) -> String? {
        guard let first = apps.first else { return nil }
        return "\(first.displayName) đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai."
    }
}

/// Công tắc "Hiện cửa sổ này khi mở app" — mặc định bật, lưu trong UserDefaults ở lớp AppKit.
/// Tách hàm quyết định ra đây để test được không cần UserDefaults thật.
public enum ShowWindowPreference {
    public static let defaultValue = true
    public static func resolve(stored: Bool?) -> Bool { stored ?? defaultValue }
}

/// Mô hình thuần dùng CHUNG cho menu thanh trạng thái và cửa sổ `StatusWindow`, để hai nơi
/// không bao giờ hiện thông tin khác nhau. Lớp AppKit (`AppController`) tính ra giá trị này rồi
/// đưa cho cả `StatusMenu` và `StatusWindow`.
public struct StatusModel: Equatable, Sendable {
    public var engineSummary: String
    public var models: [ModelStatus]
    public var permissions: [PermissionItem]
    public var mode: DictationMode
    public var lastError: String?
    /// "Thử lại lần cuối" chỉ bật khi còn âm thanh trong RAM và không đang bận.
    public var canRetryLast: Bool
    public var launchAtLogin: Bool
    public var conflictWarning: String?
    public var hotkeysActive: Bool
    public var engineHasFailed: Bool
    /// `true` CHỈ khi engine đang `.running` và cấu hình không lỗi — các tab dùng engine (vd. Từ
    /// điển) chỉ nên gọi API khi cờ này bật, nếu không sẽ gọi vào cổng/engine chưa có thật.
    public var engineReady: Bool
    /// `true` khi engine sẽ KHÔNG tự chuyển sang sẵn sàng nữa (cấu hình lỗi, hoặc engine đã bỏ
    /// cuộc) — tab dùng engine nên hiện lỗi thật + nút thử lại, KHÔNG hiện "đang chờ" vô thời hạn.
    public var engineBlocked: Bool
    /// Trạng thái chép model lần đầu từ bundle (M4b/Phần 2) — `nil` nghĩa là không có gì đáng nói
    /// (không áp dụng, hoặc đã xong êm từ trước); có giá trị khi đang chép hoặc chép lỗi, hiện ở
    /// tab Tổng quan.
    public var modelBootstrapStatus: String?
    /// Thẻ nhắc "biểu tượng thanh menu bị che" ở Tổng quan — `nil` = không hiện (không bị che, hoặc
    /// đã đóng hôm nay — xem `MenuBarOcclusionReminder`); có giá trị = thông điệp cần hiện.
    public var menuBarIconReminder: String?

    public init(engineSummary: String, models: [ModelStatus], permissions: [PermissionItem], mode: DictationMode,
                lastError: String?, canRetryLast: Bool, launchAtLogin: Bool, conflictWarning: String?,
                hotkeysActive: Bool, engineHasFailed: Bool, engineReady: Bool, engineBlocked: Bool,
                modelBootstrapStatus: String? = nil, menuBarIconReminder: String? = nil) {
        self.engineSummary = engineSummary
        self.models = models
        self.permissions = permissions
        self.mode = mode
        self.lastError = lastError
        self.canRetryLast = canRetryLast
        self.launchAtLogin = launchAtLogin
        self.conflictWarning = conflictWarning
        self.hotkeysActive = hotkeysActive
        self.engineHasFailed = engineHasFailed
        self.engineReady = engineReady
        self.engineBlocked = engineBlocked
        self.modelBootstrapStatus = modelBootstrapStatus
        self.menuBarIconReminder = menuBarIconReminder
    }

    public var missingPermissions: [PermissionItem] { permissions.filter { !$0.granted } }

    public static func build(engineState: EngineState, configError: ClientError?, lastError: String?,
                              permissions: [PermissionItem], mode: DictationMode, canRetryLast: Bool,
                              launchAtLogin: Bool, conflictWarning: String?, hotkeysActive: Bool,
                              modelBootstrapStatus: String? = nil, menuBarIconReminder: String? = nil) -> StatusModel {
        let (summary, models) = engineSummaryAndModels(engineState: engineState, configError: configError)
        let failed: Bool
        if case .failed = engineState { failed = true } else { failed = false }
        let running: Bool
        if case .running = engineState { running = true } else { running = false }
        let ready = configError == nil && running
        let blocked = configError != nil || failed
        return StatusModel(engineSummary: summary, models: models, permissions: permissions, mode: mode,
                            lastError: lastError, canRetryLast: canRetryLast, launchAtLogin: launchAtLogin,
                            conflictWarning: conflictWarning, hotkeysActive: hotkeysActive, engineHasFailed: failed,
                            engineReady: ready, engineBlocked: blocked, modelBootstrapStatus: modelBootstrapStatus,
                            menuBarIconReminder: menuBarIconReminder)
    }

    static func engineSummaryAndModels(engineState: EngineState, configError: ClientError?) -> (String, [ModelStatus]) {
        if let e = configError { return (ErrorText.message(e), []) }
        switch engineState {
        case .stopped: return ("engine đã dừng", [])
        case .starting: return ("đang khởi động engine…", [])
        case .restarting(let a, let d): return ("engine chết, khởi động lại lần \(a) sau \(d)", [])
        case .failed(let e): return (ErrorText.message(e), [])
        case .running(let owned, let h):
            let who = owned ? "engine con" : "dùng engine có sẵn"
            let ready = h.models.filter(\.loaded).map(\.id)
            let line = ready.isEmpty ? "\(who) v\(h.version), CHƯA có model sẵn sàng" : "\(who) v\(h.version), sẵn sàng"
            return (line, h.models)
        }
    }
}
