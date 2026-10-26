import AppKit
import AVFoundation
import ApplicationServices
import VFlowCore

/// Quyền macOS thật sự cần (dữ liệu thuần — tên, lý do, nơi mở Cài đặt — nằm ở
/// `VFlowCore.PermissionKind`, dùng chung với cửa sổ trạng thái và menu). Ở đây chỉ thêm các API
/// gọi hệ thống thật (AVFoundation/ApplicationServices), không có trong VFlowCore vì VFlowCore
/// không phụ thuộc AppKit để test được không cần chạy trên máy thật.
extension PermissionKind {
    var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
    }

    var granted: Bool {
        // Cờ CHỈ-ĐỂ-CHỤP-ẢNH: giả lập "đủ quyền"/"thiếu quyền" mà không đụng TCC thật (tránh cấp
        // sai hoặc đổi quyền thật của app đang dùng) — chỉ có tác dụng khi biến môi trường được đặt
        // tường minh, nếu không hành vi giống hệt trước (đọc trạng thái hệ thống thật).
        if let override = ProcessInfo.processInfo.environment["VFLOW_DEMO_PERMISSIONS"] {
            return override == "granted"
        }
        switch self {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: return CGPreflightListenEventAccess()
        case .accessibility: return CGPreflightPostEventAccess()
        }
    }

    /// `--no-prompt`: chạy thử tự động, không bật hộp thoại xin quyền (vẫn kiểm trạng thái).
    nonisolated(unsafe) static var promptsEnabled = !CommandLine.arguments.contains("--no-prompt")

    /// Hiện hộp thoại hệ thống (nếu chưa từng hỏi) và thêm app vào danh sách trong System Settings.
    func request() {
        guard Self.promptsEnabled else { return }
        switch self {
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .inputMonitoring: _ = CGRequestListenEventAccess()
        case .accessibility: _ = CGRequestPostEventAccess()
        }
    }

    func openSettings() { NSWorkspace.shared.open(settingsURL) }

    static var missing: [PermissionKind] { allCases.filter { !$0.granted } }

    /// Snapshot thuần cho `StatusModel` (cùng một nguồn dữ liệu cho menu và cửa sổ trạng thái).
    var item: PermissionItem { PermissionItem(kind: self, granted: granted) }
    static var items: [PermissionItem] { allCases.map(\.item) }
}
