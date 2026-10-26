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
app.setActivationPolicy(.accessory)
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
