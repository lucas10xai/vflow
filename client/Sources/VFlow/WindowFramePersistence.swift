import AppKit
import VFlowCore

/// Lưu vị trí/kích thước cửa sổ. `NSWindow.setFrameAutosaveName` LUÔN ghi vào `UserDefaults.standard`
/// (API AppKit không có tham số suite) — dùng nguyên khi KHÔNG có `VFLOW_HOME` (app thật, hành vi
/// cũ, không đổi). CÓ `VFLOW_HOME` ⇒ tự lưu/đọc frame qua `VFlowDefaults.resolve()` (suite riêng),
/// để ảnh chụp/kiểm thử không ghi khoá `NSWindow Frame org.aios.vflow.*` vào domain app thật.
@MainActor
final class WindowFramePersistence: NSObject {
    private weak var window: NSWindow?
    private let key: String
    private let defaults: UserDefaults

    init(window: NSWindow, name: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.window = window
        self.key = "frame.\(name)"
        self.defaults = VFlowDefaults.resolve(environment: environment)
        super.init()
        let isolated = environment["VFLOW_HOME"]?.isEmpty == false
        // CẢ HAI nhánh đọc chuỗi mô tả khung đã lưu rồi tự áp dụng qua `setFrame(_:display:)` (thay
        // vì để `setFrameUsingName` áp thẳng) — để CHUẨN HOÁ (`WindowFrameValidation.normalize`)
        // trước: khung lưu từ lần trước có thể không còn hợp lệ nếu màn hình đã tháo/đổi độ phân
        // giải giữa hai lần mở (U3) — xem `WindowFrameValidationTests`.
        let savedDescriptor = isolated ? defaults.string(forKey: key)
                                       : UserDefaults.standard.string(forKey: "NSWindow Frame \(name)")
        if let savedDescriptor, let saved = WindowFrameValidation.parseLeadingRect(savedDescriptor) {
            let screens = NSScreen.screens.map(\.visibleFrame)
            let normalized = WindowFrameValidation.normalize(frame: saved, minSize: window.minSize,
                                                              screens: screens, mainScreen: NSScreen.main?.visibleFrame)
            window.setFrame(normalized, display: false)
        } else {
            window.center()
        }
        if isolated {
            NotificationCenter.default.addObserver(self, selector: #selector(saveFrame),
                                                    name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(saveFrame),
                                                    name: NSWindow.didResizeNotification, object: window)
        } else {
            // Giữ `setFrameAutosaveName` để AppKit tự LƯU khung mỗi khi kéo/đổi cỡ sau này (hành vi
            // cũ) — chỉ đường KHÔI PHỤC ở trên đổi, để chuẩn hoá được.
            window.setFrameAutosaveName(name)
        }
    }

    @objc private func saveFrame() {
        guard let window else { return }
        defaults.set(String(window.frameDescriptor), forKey: key)
    }
}
