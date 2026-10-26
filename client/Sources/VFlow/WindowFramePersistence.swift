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
        if environment["VFLOW_HOME"]?.isEmpty == false {
            if let saved = defaults.string(forKey: key) {
                window.setFrame(from: saved)
            } else {
                window.center()
            }
            NotificationCenter.default.addObserver(self, selector: #selector(saveFrame),
                                                    name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(saveFrame),
                                                    name: NSWindow.didResizeNotification, object: window)
        } else {
            window.setFrameAutosaveName(name)
            if window.setFrameUsingName(name) == false { window.center() }
        }
    }

    @objc private func saveFrame() {
        guard let window else { return }
        defaults.set(String(window.frameDescriptor), forKey: key)
    }
}
