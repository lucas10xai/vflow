import AppKit
import VFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var demo: OverlayController?
    private var terminating = false

    private var iconDemoWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--appearance"), args.count > i + 1 {
            switch args[i + 1] {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default:
                FileHandle.standardError.write(Data("dùng: --appearance light|dark\n".utf8))
                exit(64)
            }
        }
        if args.contains("--demo-icon") {
            runIconDemo(args: args)
            return
        }
        if let i = args.firstIndex(of: "--demo-overlay") {
            runDemo(args.count > i + 1 ? args[i + 1] : "", args: args)
            return
        }
        if let i = args.firstIndex(of: "--render-offscreen"), args.count > i + 1 {
            runOffscreenRender(target: args[i + 1], args: args)
            return
        }
        let c = AppController()
        controller = c
        c.start()
        buildMainMenu(controller: c)
        if let i = args.firstIndex(of: "--open-tab") {
            guard args.count > i + 1 else {
                FileHandle.standardError.write(Data("dùng: --open-tab tongquan|thongke|lichsu|tudien|snippet|caidat\n".utf8))
                exit(64)
            }
            let flag = args[i + 1]
            // "caidat": Cài đặt là CỬA SỔ RIÊNG (không còn mục trong thanh bên chính), mở riêng để
            // chụp ảnh thay vì chọn mục thanh bên.
            if flag == "caidat" {
                c.openSettingsWindow()
            } else if let tab = MainTab(flag: flag) {
                c.openStatusWindow(tab: tab)
            } else {
                FileHandle.standardError.write(Data("dùng: --open-tab tongquan|thongke|lichsu|tudien|snippet|caidat\n".utf8))
                exit(64)
            }
        }
        if let i = args.firstIndex(of: "--open-settings-tab"), args.count > i + 1 {
            guard let cat = SettingsCategory(rawValue: args[i + 1]) else {
                FileHandle.standardError.write(Data("dùng: --open-settings-tab general|cloud|hotkeys|historyPrivacy|advanced\n".utf8))
                exit(64)
            }
            c.openSettingsWindow(tab: cat)
        }
    }

    /// `--demo-icon [--demo-seconds N]`: cửa sổ RIÊNG hiện biểu tượng thanh menu TEMPLATE
    /// (`BrandIcon.statusImage`) trên nền tối và nền sáng, đủ 5 trạng thái huy hiệu — chỉ chụp CỬA
    /// SỔ NÀY theo `windowNumber` (chứng minh trắng/đen tự động + phân biệt bằng HÌNH) thay vì chụp
    /// thanh menu thật (có dữ liệu cá nhân của chủ dự án); KHÔNG BAO GIỜ chụp toàn màn hình.
    private func runIconDemo(args: [String]) {
        let badges: [(String, MenuBarBadge)] = [
            ("khong", .none), ("nghe", .listening), ("lenh", .command), ("dich", .busy), ("loi", .warning),
        ]
        let cellSize: CGFloat = 64
        let rowH: CGFloat = 80
        let colW: CGFloat = 90
        let width = colW * 2 + 40
        let height = rowH * CGFloat(badges.count) + 40
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "vflow — biểu tượng thanh menu (template)"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        for (row, (name, badge)) in badges.enumerated() {
            let y = height - 40 - CGFloat(row + 1) * rowH + (rowH - cellSize) / 2
            for (col, dark) in [(0, true), (1, false)] {
                let bg = NSView(frame: NSRect(x: 20 + CGFloat(col) * colW, y: y, width: cellSize, height: cellSize))
                bg.wantsLayer = true
                bg.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
                bg.layer?.cornerRadius = 8
                if let img = BrandIcon.statusImage(badge: badge) {
                    let iv = NSImageView(frame: NSRect(x: (cellSize - 18) / 2, y: (cellSize - 18) / 2, width: 18, height: 18))
                    iv.image = img
                    iv.imageScaling = .scaleProportionallyUpOrDown
                    // `contentTintColor` là API AppKit chuẩn để tô màu ảnh template (dùng ĐÚNG
                    // alpha của ảnh làm mặt nạ, như `NSImage.isTemplate` yêu cầu) — dùng ở đây để
                    // chụp ảnh xác định được trắng/đen, vì một NSImageView trần (ngoài NSStatusItem
                    // thật) không tự dò nền tối/sáng xung quanh để tô màu.
                    iv.contentTintColor = dark ? .white : .black
                    bg.addSubview(iv)
                }
                content.addSubview(bg)
                _ = name
            }
        }
        win.contentView = content
        win.setFrameOrigin(NSPoint(x: 80, y: 80))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        iconDemoWindow = win
        // In toạ độ vùng cửa sổ theo hệ quy chiếu gốc-trên-trái (x, y, rộng, cao) để công cụ chụp
        // CHỈ VÙNG CỬA SỔ NÀY (không toàn màn hình) dùng đúng khung, không cần CGWindowListCopyWindowInfo
        // (cần quyền Ghi màn hình riêng cho tiến trình gọi, không có sẵn trong môi trường kiểm tự động).
        if let screen = win.screen ?? NSScreen.main {
            let f = win.frame
            let x = Int(f.origin.x.rounded())
            let y = Int((screen.frame.height - f.origin.y - f.height).rounded())
            let w = Int(f.width.rounded())
            let h = Int(f.height.rounded())
            print("VFLOW_DEMO_RECT \(x) \(y) \(w) \(h)")
            fflush(stdout)
        }
        var seconds = 20.0
        if let j = args.firstIndex(of: "--demo-seconds"), args.count > j + 1, let s = Double(args[j + 1]) { seconds = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }

    /// Menu ứng dụng đầy đủ (app thường, không còn `.accessory`): "vflow" (Giới thiệu, Cài đặt…,
    /// Ẩn, Thoát), Cửa sổ, Trợ giúp.
    private func buildMainMenu(controller: AppController) {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Giới thiệu vflow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Cài đặt…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn vflow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Ẩn ứng dụng khác", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Hiện tất cả", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Thoát vflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Đưa tất cả ra trước", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        main.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Trợ giúp")
        let help = NSMenuItem(title: "Trợ giúp vflow", action: #selector(AppDelegate.openHelp), keyEquivalent: "")
        help.target = self
        helpMenu.addItem(help)
        let welcome = NSMenuItem(title: "Xem hướng dẫn chào mừng…", action: #selector(AppDelegate.openWelcome), keyEquivalent: "")
        welcome.target = self
        helpMenu.addItem(welcome)
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        main.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    @objc private func openSettings() { controller?.openSettingsWindow() }

    /// Mở lại Chào mừng lần đầu từ menu Trợ giúp bất kể đã xem/đã cấp đủ quyền hay chưa.
    @objc private func openWelcome() { controller?.openWelcome() }

    /// "mở README hoặc hướng dẫn quyền": có README cạnh nhị phân (chạy từ repo) ⇒ mở; không có
    /// (bản đóng gói sau này, hoặc chạy ở nơi khác) ⇒ mở cửa sổ chính (đã có hướng dẫn cấp quyền).
    @objc private func openHelp() { controller?.openHelpDocument() }

    /// `--demo-overlay <ghi|khoa|dich-nghe|dich|xong|loi> [--demo-seconds N]`: chỉ hiện thanh trạng
    /// thái để chụp ảnh — đủ 6 trạng thái của HUD (xem U2 mục D; `dich-nghe` thêm ở V4/V5 — HUD
    /// trong lúc GHI ở chế độ Dịch, KHÁC `dich` vốn là lúc đang xử lý/chuyển văn bản cho MỌI chế độ).
    private func runDemo(_ which: String, args: [String]) {
        let state: OverlayState
        switch which {
        case "ghi": state = .listening(level: 0.7)
        case "khoa": state = .listeningLocked(level: 0.5)
        case "dich-nghe": state = .listeningTranslate(target: TranslationTarget.title(for: "en"), level: 0.7)
        case "dich": state = .transcribing
        case "xong": state = .done
        case "loi":
            state = .error(ErrorText.message(.engine(status: 503, code: "model_unavailable",
                                                     message: "Model chưa tải được (lý do: tunnel_down)")))
        default:
            FileHandle.standardError.write(Data("dùng: --demo-overlay ghi|khoa|dich-nghe|dich|xong|loi [--demo-seconds N]\n".utf8))
            exit(64)
        }
        let o = OverlayController()
        o.sticky = true
        demo = o
        o.show(state)
        switch state {
        case .listening, .listeningLocked, .listeningCommand, .listeningTranslate: o.setLevel(0.7)
        default: break
        }
        // `--render-offscreen` (U2, sau sự cố chụp màn hình thật): chụp HUD bằng `cacheDisplay`
        // (KHÔNG BAO GIỜ orderFront) rồi thoát ngay, không chờ `--demo-seconds`.
        if OffscreenRender.enabled, let oi = args.firstIndex(of: "--out"), args.count > oi + 1 {
            o.captureOffscreen(to: args[oi + 1])
            OffscreenRender.assertNoOnScreenWindow()
            NSApp.terminate(nil)
            return
        }
        var seconds = 20.0
        if let j = args.firstIndex(of: "--demo-seconds"), args.count > j + 1, let s = Double(args[j + 1]) { seconds = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }

    /// `--render-offscreen <tongquan|thongke|lichsu|tudien|snippet|caidat[:<mục>]|welcome> --out <path.png>
    /// [--render-wait-ms N]`: dựng app THẬT (engine/dữ liệu thật qua VFLOW_HOME) nhưng KHÔNG BAO GIỜ
    /// hiện cửa sổ lên màn hình (xem `OffscreenRender`, sự cố U2 — chủ dự án có thể đang
    /// họp/trình chiếu bất cứ lúc nào). Chờ `--render-wait-ms` (mặc định 500ms) cho dữ liệu bất đồng
    /// bộ (`.task(id:)` ở Từ điển/Snippets) kịp tải trước khi chụp.
    private func runOffscreenRender(target: String, args: [String]) {
        guard let oi = args.firstIndex(of: "--out"), args.count > oi + 1 else {
            FileHandle.standardError.write(Data("dùng: --render-offscreen <target> --out <path.png>\n".utf8))
            exit(64)
        }
        let outPath = args[oi + 1]
        var waitMs = 500.0
        if let wi = args.firstIndex(of: "--render-wait-ms"), args.count > wi + 1, let w = Double(args[wi + 1]) { waitMs = w }

        // Luôn tắt hộp thoại xin quyền (hệ thống, không phải cửa sổ của ta — nhưng vẫn "lên màn
        // hình") bất kể có truyền --no-prompt hay không, để chế độ này KHÔNG BAO GIỜ hiện gì cả.
        PermissionKind.promptsEnabled = false
        NSApp.setActivationPolicy(.prohibited)
        let c = AppController()
        controller = c
        // Dựng THẲNG đúng mục cần chụp (không phải Tổng quan rồi mới chuyển) — xem
        // `AppController.start(initialTab:)` để biết lý do (List không hiện hàng sau khi chuyển mục).
        let initialTab: MainTab = (target == "tudien:them-loi") ? .dictionary
            : (target == "tongquan:dich") ? .overview
            : (MainTab(flag: target) ?? .overview)
        c.start(initialTab: initialTab)

        DispatchQueue.main.asyncAfter(deadline: .now() + waitMs / 1000) { Task { @MainActor in
            if target == "modeldownload" || target.hasPrefix("modeldownload:") {
                let variant = target.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                c.captureModelDownloadOffscreen(variant: variant, to: outPath)
            } else if target == "models" || target.hasPrefix("models:") {
                let variant = target.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                await c.captureModelManagementOffscreen(variant: variant, to: outPath)
            } else if target == "welcome" {
                c.openWelcome()
                c.captureWelcomeOffscreen(to: outPath)
            } else if target.hasPrefix("caidat") {
                let parts = target.split(separator: ":", maxSplits: 1)
                let cat = parts.count > 1 ? (SettingsCategory(rawValue: String(parts[1])) ?? .general) : .general
                c.openSettingsWindow(tab: cat)
                // Các mục đọc `GET /v1/settings` qua `.task(id: model.engineReady)` (Đám mây/Giọng
                // nói/Ứng dụng/Dữ liệu) chưa kịp xong nếu chụp NGAY — cùng lý do/cách xử lý với
                // Lịch sử/Từ điển/Snippets (xem `StatusWindowController.captureOffscreen`).
                try? await Task.sleep(for: .milliseconds(500))
                c.captureSettingsWindowOffscreen(tab: cat, to: outPath)
            } else if target == "tudien:them-loi" {
                c.openStatusWindow(tab: .dictionary)
                c.captureDictionaryAddInvalidOffscreen(to: outPath)
            } else if target == "tongquan:dich" {
                // Chọn thẳng chế độ Dịch TRƯỚC khi chụp — để thấy lưới chế độ đổi viền cam sang
                // Dịch VÀ ô chọn ngôn ngữ đích/mức trang trọng (chỉ hiện khi mode == .translate).
                c.mode = .translate
                c.openStatusWindow(tab: .overview)
                await c.captureStatusWindowOffscreen(tab: .overview, to: outPath)
            } else if target == "dich-sheet" {
                c.captureTranslationSheetOffscreen(to: outPath)
            } else if let tab = MainTab(flag: target) {
                c.openStatusWindow(tab: tab)
                await c.captureStatusWindowOffscreen(tab: tab, to: outPath)
            } else {
                FileHandle.standardError.write(Data("dùng: --render-offscreen tongquan|tongquan:dich|thongke|lichsu|tudien|tudien:them-loi|dich-sheet|snippet|caidat[:general|cloud|hotkeys|historyPrivacy|advanced]|welcome|models[:dangtai]|modeldownload[:tiendo|loi|xong] --out <path.png>\n".utf8))
                exit(64)
            }
            OffscreenRender.assertNoOnScreenWindow()
            // `shutdown()` chờ engine CON (nếu `start()` vừa spawn một cái) thoát hẳn — có thể lâu
            // hơn dự kiến nếu đang giữa chừng khởi động; giới hạn 4s rồi thoát THẲNG bằng `exit(0)`
            // (không qua `NSApp.terminate`, vốn có thể treo vô thời hạn) để script gọi không bị kẹt —
            // script bên ngoài vẫn tự dọn tiến trình mồ côi còn sót (xem báo cáo cuối).
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await c.shutdown() }
                group.addTask { try? await Task.sleep(for: .seconds(4)) }
                await group.next()
                group.cancelAll()
            }
            exit(0)
        } }
    }

    /// `open VFlow.app` lần nữa khi app đang chạy ⇒ không mở tiến trình thứ hai, chỉ đưa cửa sổ
    /// trạng thái lên trước (cách để tìm lại app khi biểu tượng thanh menu bị ẩn).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openStatusWindow()
        return true
    }

    /// Menu Dock (chuột phải biểu tượng Dock) — CÙNG các mục với menu thanh trạng thái, xây từ
    /// CÙNG một hàm (`StatusMenu.populate`) để không nhân đôi logic; lối vào dự phòng chính khi
    /// biểu tượng thanh menu bị notch/thanh menu đầy che mất (xem mục 4a trong yêu cầu).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let c = controller else { return nil }
        let dockMenu = NSMenu()
        StatusMenu.populate(dockMenu, model: c.statusModel, controller: c)
        return dockMenu
    }

    /// Đóng cửa sổ trạng thái không được thoát app (chỉ còn menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let c = controller, !terminating else { return .terminateNow }
        terminating = true
        Task { @MainActor in
            await c.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
// SIGTERM/SIGINT (vd. `kill`, đăng xuất) ⇒ đi qua đường thoát bình thường để đóng engine con.
// Không gọi terminate trong khối main-queue: `.terminateLater` chờ một Task cũng chạy trên main-queue
// ⇒ kẹt. Đẩy qua run loop chính thay vì main-queue.
let signalQueue = DispatchQueue(label: "org.aios.vflow.signals")
let signalSources = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
    src.setEventHandler {
        RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    src.resume()
    return src
}
app.run()
