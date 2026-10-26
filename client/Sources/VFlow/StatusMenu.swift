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
        setStableAutosaveName()
        refresh(model)
    }

    /// Công tắc "Hiện biểu tượng trên thanh menu" (Cài đặt). Biểu tượng vẫn tồn tại, chỉ ẩn/hiện —
    /// app luôn có chỗ đứng chính ở cửa sổ chính + Dock.
    func setVisible(_ visible: Bool) { item.isVisible = visible }

    /// Khung cửa sổ THẬT của biểu tượng — dùng để dò bị che (notch/thanh menu đầy, xem
    /// `VFlowCore.MenuBarOcclusion`); `nil` khi AppKit chưa gán cửa sổ (vd. mới khởi động).
    var itemWindowFrame: NSRect? { item.button?.window?.frame }

    /// `autosaveName` ổn định để macOS nhớ vị trí biểu tượng qua các lần chạy (cơ chế "Preferred
    /// Position" không công khai, xem README mục Phím tắt/biểu tượng — chỉ đặt tên ổn định, KHÔNG
    /// tự ghi đè vị trí mò vào defaults, vì chưa kiểm chứng được cơ chế đó hoạt động đúng).
    func setStableAutosaveName() { item.autosaveName = "org.aios.vflow.statusItem" }

    /// Cùng một `StatusModel` với `StatusWindow`: menu và cửa sổ không bao giờ nói khác nhau.
    func refresh(_ model: StatusModel) {
        self.model = model
        let (symbol, badge, label) = iconState()
        // Có logo thương hiệu đóng gói ⇒ dùng (logo + chấm trạng thái phủ góc, xem `BrandIcon`);
        // không có (vd. chạy `swift build` không qua `build-app.sh`) ⇒ rơi về SF Symbol cũ.
        let img = BrandIcon.statusImage(badge: badge) ?? {
            let i = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            i?.isTemplate = true
            return i
        }()
        item.button?.image = img
        item.button?.toolTip = label
        item.button?.setAccessibilityLabel(label)
    }

    private func iconState() -> (symbol: String, badge: MenuBarBadge, label: String) {
        switch controller.phase {
        case .recording: return ("mic.fill", .listening, "vflow: đang nghe")
        case .recordingLocked: return ("mic.fill", .listening, "vflow: đang nghe (đã khoá)")
        case .recordingCommand: return ("command", .command, "vflow: đang nghe lệnh")
        case .busy, .busyCommand: return ("waveform", .busy, "vflow: đang dịch")
        default: break
        }
        if model.conflictWarning != nil { return ("exclamationmark.triangle", .warning, "vflow: xung đột phím ⌥") }
        if model.missingPermissions.isEmpty == false || !model.hotkeysActive { return ("exclamationmark.triangle", .warning, "vflow: cần xử lý lỗi") }
        if model.models.contains(where: \.loaded) { return ("mic", .none, "vflow: sẵn sàng") }
        if model.engineHasFailed { return ("exclamationmark.triangle", .warning, "vflow: engine lỗi") }
        if !model.models.isEmpty { return ("mic.badge.xmark", .warning, "vflow: engine chạy nhưng chưa có model sẵn sàng") }
        return ("mic.slash", .warning, "vflow: engine chưa sẵn sàng")
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        Self.populate(menu, model: model, controller: controller)
    }

    /// Nội dung menu — dùng CHUNG cho biểu tượng thanh menu VÀ menu Dock (`applicationDockMenu`,
    /// xem `main.swift`) để hai nơi không bao giờ lệch mục/logic (xem mục 4a trong yêu cầu).
    static func populate(_ menu: NSMenu, model: StatusModel, controller: AppController) {
        // Dòng trạng thái đầu menu — cùng câu với thẻ trạng thái lớn ở Tổng quan (một nguồn duy nhất).
        menu.addItem(disabled("vflow — \(model.engineSummary)", symbol: statusLineSymbol(model)))
        if let w = model.conflictWarning { menu.addItem(disabled(w, symbol: "exclamationmark.triangle.fill")) }
        if let e = model.lastError { menu.addItem(disabled("Lỗi gần nhất: \(e)", symbol: "exclamationmark.triangle")) }
        menu.addItem(.separator())
        menu.addItem(action("Mở cửa sổ vflow", symbol: "macwindow") { [weak controller] in controller?.openStatusWindow() })
        menu.addItem(action("Chèn lại câu vừa rồi", symbol: "arrow.uturn.backward") { [weak controller] in controller?.reinsertLastSentence() })

        let missing = model.missingPermissions
        if !missing.isEmpty || !model.hotkeysActive {
            menu.addItem(sectionHeader("Cần xử lý"))
            for p in missing {
                menu.addItem(action("Thiếu quyền \(p.kind.title) — mở Cài đặt…", symbol: "lock") { p.kind.request(); p.kind.openSettings() })
            }
            if missing.isEmpty && !model.hotkeysActive {
                menu.addItem(disabled("Chưa nghe được phím ⌥ (thử thoát và mở lại app sau khi cấp quyền)"))
            }
        }
        menu.addItem(.separator())

        menu.addItem(sectionHeader("Chế độ"))
        for m in DictationMode.allCases {
            let it = action(m.title, symbol: m.sendsTextToCloud ? "cloud" : "lock.fill") { [weak controller] in controller?.mode = m }
            it.state = model.mode == m ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())

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
        modelItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let retry = action("Thử lại lần cuối", symbol: "arrow.counterclockwise") { [weak controller] in controller?.retryLast() }
        retry.isEnabled = model.canRetryLast
        menu.addItem(retry)
        if model.engineHasFailed {
            menu.addItem(action("Khởi động lại engine", symbol: "arrow.clockwise") { [weak controller] in controller?.restartEngine() })
        }
        menu.addItem(.separator())

        menu.addItem(sectionHeader("Khác"))
        let login = action("Bật khi đăng nhập") { [weak controller] in controller?.toggleLaunchAtLogin() }
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Cài đặt…", symbol: "gearshape") { [weak controller] in controller?.openSettingsWindow() })
        menu.addItem(action("Mở thư mục dữ liệu (~/.vflow)", symbol: "folder") { [weak controller] in controller?.openDataFolder() })
        menu.addItem(action("Hướng dẫn cấp quyền…", symbol: "questionmark.circle") { [weak controller] in controller?.openStatusWindow() })
        menu.addItem(.separator())
        menu.addItem(action("Thoát vflow", symbol: "power", key: "q") { NSApp.terminate(nil) })
    }

    /// Biểu tượng cho dòng trạng thái đầu menu — khớp cảm giác với huy hiệu thanh menu
    /// (`BrandIcon.statusImage`), không dựa vào `controller.phase` để tránh nhập nhằng với trạng
    /// thái đang ghi/dịch (dòng này chỉ nói engine/model, không nói đang ghi âm).
    private static func statusLineSymbol(_ model: StatusModel) -> String {
        if model.engineHasFailed || model.conflictWarning != nil { return "exclamationmark.triangle" }
        if model.models.contains(where: \.loaded) { return "checkmark.circle" }
        return "ellipsis.circle"
    }

    /// Tiêu đề nhóm trong menu (macOS 14+: `NSMenuItem.sectionHeader`, chữ nhỏ không bấm được) —
    /// đỡ phải phân biệt mục nào thuộc mục nào chỉ bằng dấu phân cách.
    private static func sectionHeader(_ title: String) -> NSMenuItem { .sectionHeader(title: title) }

    private static func disabled(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        if let symbol { it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return it
    }

    private static func action(_ title: String, symbol: String? = nil, key: String = "", _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
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
