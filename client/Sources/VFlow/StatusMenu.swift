import AppKit
import VFlowCore

/// Biểu tượng menu bar và menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let controller: AppController
    private let menu = NSMenu()
    private var model = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                          permissions: PermissionKind.allCases.map { PermissionItem(kind: $0, granted: false) },
                                          mode: .auto, canRetryLast: false, launchAtLogin: false, conflictWarning: nil,
                                          hotkeysActive: false)

    init(controller: AppController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh(model)
    }

    /// Công tắc "Hiện biểu tượng trên thanh menu" (Cài đặt). Biểu tượng vẫn tồn tại, chỉ ẩn/hiện —
    /// app luôn có chỗ đứng chính ở cửa sổ chính + Dock.
    func setVisible(_ visible: Bool) { item.isVisible = visible }

    /// Cùng một `StatusModel` với `StatusWindow`: menu và cửa sổ không bao giờ nói khác nhau.
    func refresh(_ model: StatusModel) {
        self.model = model
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
        if model.conflictWarning != nil { return ("exclamationmark.triangle", "vflow: xung đột phím ⌥") }
        if model.missingPermissions.isEmpty == false || !model.hotkeysActive { return ("exclamationmark.triangle", "vflow: cần xử lý lỗi") }
        if model.models.contains(where: \.loaded) { return ("mic", "vflow: sẵn sàng") }
        if model.engineHasFailed { return ("exclamationmark.triangle", "vflow: engine lỗi") }
        if !model.models.isEmpty { return ("mic.badge.xmark", "vflow: engine chạy nhưng chưa có model sẵn sàng") }
        return ("mic.slash", "vflow: engine chưa sẵn sàng")
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(action("Mở cửa sổ vflow", symbol: "macwindow") { [weak controller] in controller?.openStatusWindow() })
        menu.addItem(.separator())
        menu.addItem(disabled("vflow — \(model.engineSummary)"))
        if let w = model.conflictWarning { menu.addItem(disabled(w, symbol: "exclamationmark.triangle.fill")) }
        if let e = model.lastError { menu.addItem(disabled("Lỗi gần nhất: \(e)", symbol: "exclamationmark.triangle")) }

        let missing = model.missingPermissions
        for p in missing {
            menu.addItem(action("Thiếu quyền \(p.kind.title) — mở Cài đặt…", symbol: "lock") { p.kind.request(); p.kind.openSettings() })
        }
        if missing.isEmpty && !model.hotkeysActive {
            menu.addItem(disabled("Chưa nghe được phím ⌥ (thử thoát và mở lại app sau khi cấp quyền)"))
        }
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for m in DictationMode.allCases {
            let it = action(m.title) { [weak controller] in controller?.mode = m }
            it.state = model.mode == m ? .on : .off
            modeMenu.addItem(it)
        }
        let modeItem = NSMenuItem(title: "Chế độ: \(model.mode.title)", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let modelMenu = NSMenu()
        modelMenu.addItem(disabled("Model do engine chọn (cấu hình default_model)"))
        if model.models.isEmpty {
            modelMenu.addItem(disabled("Chưa đọc được /healthz"))
        } else {
            for m in model.models {
                modelMenu.addItem(disabled(EngineAPI.menuLine(m), symbol: m.loaded ? "checkmark.circle" : "xmark.circle"))
            }
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let retry = action("Thử lại lần cuối") { [weak controller] in controller?.retryLast() }
        retry.isEnabled = model.canRetryLast
        menu.addItem(retry)
        if model.engineHasFailed {
            menu.addItem(action("Khởi động lại engine") { [weak controller] in controller?.restartEngine() })
        }
        menu.addItem(.separator())

        let login = action("Bật khi đăng nhập") { [weak controller] in controller?.toggleLaunchAtLogin() }
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Mở thư mục dữ liệu (~/.vflow)") { [weak controller] in controller?.openDataFolder() })
        menu.addItem(action("Hướng dẫn cấp quyền…") { [weak controller] in controller?.openStatusWindow() })
        menu.addItem(.separator())
        menu.addItem(action("Thoát vflow", key: "q") { NSApp.terminate(nil) })
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
