import AppKit
import AVFoundation
import ApplicationServices

/// Quyền macOS thật sự cần (xem client/README.md).
enum Permission: CaseIterable {
    case microphone
    /// Event tap nghe phím toàn cục (kTCCServiceListenEvent).
    case inputMonitoring
    /// Gửi ⌘V tổng hợp (kTCCServicePostEvent, hiện ở mục Trợ năng).
    case accessibility

    var title: String {
        switch self {
        case .microphone: "Micro"
        case .inputMonitoring: "Theo dõi đầu vào (Input Monitoring)"
        case .accessibility: "Trợ năng (Accessibility)"
        }
    }

    var why: String {
        switch self {
        case .microphone: "ghi giọng nói khi giữ ⌥ trái"
        case .inputMonitoring: "nhận biết khi giữ/nhả phím ⌥ trái ở mọi ứng dụng"
        case .accessibility: "dán chữ (⌘V) vào ứng dụng đang dùng"
        }
    }

    var settingsURL: URL {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    var granted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: CGPreflightPostEventAccess()
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

    static var missing: [Permission] { allCases.filter { !$0.granted } }
}
