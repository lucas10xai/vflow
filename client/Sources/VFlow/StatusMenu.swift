import AppKit
import VFlowCore

/// Biểu tượng menu bar và menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let controller: AppController
    private let menu = NSMenu()

    init(controller: AppController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    func refresh() {
        let (symbol, label) = iconState()
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = label
        item.button?.setAccessibilityLabel(label)
    }

    private func iconState() -> (String, String) {
        switch controller.phase {
        case .recording: return ("mic.fill", "vflow: đang nghe")
        case .busy: return ("waveform", "vflow: đang dịch")
        default: break
        }
        if controller.configError != nil || !controller.hotkeysActive { return ("exclamationmark.triangle", "vflow: cần xử lý lỗi") }
        switch controller.engineState {
        case .running(_, let h) where h.models.contains(where: \.loaded): return ("mic", "vflow: sẵn sàng")
        case .running: return ("mic.badge.xmark", "vflow: engine chạy nhưng chưa có model sẵn sàng")
        case .failed: return ("exclamationmark.triangle", "vflow: engine lỗi")
        default: return ("mic.slash", "vflow: engine chưa sẵn sàng")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(disabled("vflow — \(engineLine())"))
        if let e = controller.lastError { menu.addItem(disabled("Lỗi gần nhất: \(e)", symbol: "exclamationmark.triangle")) }

        let missing = Permission.missing
        for p in missing {
            menu.addItem(action("Thiếu quyền \(p.title) — mở Cài đặt…", symbol: "lock") { p.request(); p.openSettings() })
        }
        if missing.isEmpty && !controller.hotkeysActive {
            menu.addItem(disabled("Chưa nghe được phím ⌥ (thử thoát và mở lại app sau khi cấp quyền)"))
        }
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for m in DictationMode.allCases {
            let it = action(m.title) { [weak controller] in controller?.mode = m }
            it.state = controller.mode == m ? .on : .off
            modeMenu.addItem(it)
        }
        let modeItem = NSMenuItem(title: "Chế độ: \(controller.mode.title)", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let modelMenu = NSMenu()
        modelMenu.addItem(disabled("Model do engine chọn (cấu hình default_model)"))
        if let h = controller.health {
            for m in h.models {
                modelMenu.addItem(disabled(EngineAPI.menuLine(m), symbol: m.loaded ? "checkmark.circle" : "xmark.circle"))
            }
        } else {
            modelMenu.addItem(disabled("Chưa đọc được /healthz"))
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let retry = action("Thử lại lần cuối") { [weak controller] in controller?.retryLast() }
        retry.isEnabled = controller.canRetry
        menu.addItem(retry)
        if case .failed = controller.engineState {
            menu.addItem(action("Khởi động lại engine") { [weak controller] in controller?.restartEngine() })
        }
        menu.addItem(.separator())

        let login = action("Bật khi đăng nhập") { [weak controller] in controller?.toggleLaunchAtLogin() }
        login.state = controller.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Mở thư mục dữ liệu (~/.vflow)") {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vflow"))
        })
        menu.addItem(action("Hướng dẫn cấp quyền…") { PermissionGuide.show() })
        menu.addItem(.separator())
        menu.addItem(action("Thoát vflow", key: "q") { NSApp.terminate(nil) })
    }

    private func engineLine() -> String {
        if let e = controller.configError { return ErrorText.message(e) }
        switch controller.engineState {
        case .stopped: return "engine đã dừng"
        case .starting: return "đang khởi động engine…"
        case .restarting(let a, let d): return "engine chết, khởi động lại lần \(a) sau \(d)"
        case .failed(let e): return ErrorText.message(e)
        case .running(let owned, let h):
            let who = owned ? "engine con" : "dùng engine có sẵn"
            let ready = h.models.filter(\.loaded).map(\.id)
            return ready.isEmpty ? "\(who) v\(h.version), CHƯA có model sẵn sàng" : "\(who) v\(h.version), sẵn sàng"
        }
    }

    private func disabled(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        if let symbol { it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return it
    }

    private func action(_ title: String, symbol: String? = nil, key: String = "", _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let it = ClosureMenuItem(title: title, keyEquivalent: key, run: run)
        if let symbol { it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return it
    }
}

@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void
    init(title: String, keyEquivalent: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError("không dùng") }
    @objc private func fire() { run() }
}

@MainActor
enum PermissionGuide {
    static func show() {
        let alert = NSAlert()
        alert.messageText = "vflow cần 3 quyền"
        let lines = Permission.allCases.map { p in
            "• \(p.title) — \(p.why): \(p.granted ? "ĐÃ CẤP" : "CHƯA CẤP")"
        }
        alert.informativeText = lines.joined(separator: "\n") + """


        Mở System Settings › Quyền riêng tư & Bảo mật, bật vflow ở từng mục. \
        Sau khi bật Theo dõi đầu vào, có thể phải thoát và mở lại vflow. \
        Bản dựng ad-hoc mới (chạy lại build-app.sh) có chữ ký khác nên macOS có thể đòi cấp lại.
        """
        for p in Permission.allCases { alert.addButton(withTitle: "Mở \(p.title)") }
        alert.addButton(withTitle: "Đóng")
        NSApp.activate()
        let r = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if r >= 0 && r < Permission.allCases.count {
            let p = Permission.allCases[r]
            p.request()
            p.openSettings()
        }
    }
}
