import AppKit
import VFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var demo: OverlayController?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo-overlay") {
            runDemo(args.count > i + 1 ? args[i + 1] : "", args: args)
            return
        }
        let c = AppController()
        controller = c
        c.start()
        buildMainMenu(controller: c)
        if let i = args.firstIndex(of: "--open-tab") {
            guard args.count > i + 1, let tab = MainTab(flag: args[i + 1]) else {
                FileHandle.standardError.write(Data("dùng: --open-tab tongquan|lichsu|tudien|caidat\n".utf8))
                exit(64)
            }
            c.openStatusWindow(tab: tab)
        }
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
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        main.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    @objc private func openSettings() { controller?.openStatusWindow(tab: .settings) }

    /// "mở README hoặc hướng dẫn quyền": có README cạnh nhị phân (chạy từ repo) ⇒ mở; không có
    /// (bản đóng gói sau này, hoặc chạy ở nơi khác) ⇒ mở cửa sổ chính (đã có hướng dẫn cấp quyền).
    @objc private func openHelp() {
        if let repo = controller?.repoPathForHelp(),
           FileManager.default.fileExists(atPath: repo + "/client/README.md") {
            NSWorkspace.shared.open(URL(fileURLWithPath: repo + "/client/README.md"))
        } else {
            controller?.openStatusWindow(tab: .overview)
        }
    }

    /// `--demo-overlay <ghi|dich|xong|loi> [--demo-seconds N]`: chỉ hiện thanh trạng thái để chụp ảnh.
    private func runDemo(_ which: String, args: [String]) {
        let state: OverlayState
        switch which {
        case "ghi": state = .listening(level: 0.7)
        case "dich": state = .transcribing
        case "xong": state = .done
        case "loi":
            state = .error(ErrorText.message(.engine(status: 503, code: "model_unavailable",
                                                     message: "Model chưa tải được (lý do: tunnel_down)")))
        default:
            FileHandle.standardError.write(Data("dùng: --demo-overlay ghi|dich|xong|loi [--demo-seconds N]\n".utf8))
            exit(64)
        }
        let o = OverlayController()
        o.sticky = true
        demo = o
        o.show(state)
        if case .listening = state { o.setLevel(0.7) }
        var seconds = 20.0
        if let j = args.firstIndex(of: "--demo-seconds"), args.count > j + 1, let s = Double(args[j + 1]) { seconds = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }

    /// `open VFlow.app` lần nữa khi app đang chạy ⇒ không mở tiến trình thứ hai, chỉ đưa cửa sổ
    /// trạng thái lên trước (cách để tìm lại app khi biểu tượng thanh menu bị ẩn).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openStatusWindow()
        return true
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
