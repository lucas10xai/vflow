import AppKit
import SwiftUI
import VFlowCore

/// Chào mừng lần đầu (U1, mục 5): tờ hướng dẫn 3 bước cấp quyền Micro/Theo dõi đầu vào/Trợ năng,
/// mỗi bước có dấu tích SỐNG (tự cập nhật, poll như `StatusWindowController`), nút "Mở Cài đặt hệ
/// thống", và một ô "Thử nói" tuỳ chọn. Chỉ tự hiện khi CHƯA đủ quyền hoặc chưa từng xem
/// (`VFlowCore.WelcomeDecision`, cờ UserDefaults `hasSeenWelcome`) — luôn mở lại được từ menu Trợ
/// giúp bất kể kết quả đó.
@MainActor
final class WelcomeWindowController: NSWindowController {
    private unowned let controller: AppController
    private let viewModel: WelcomeViewModel
    private var permissionTimer: Timer?

    init(controller: AppController) {
        self.controller = controller
        let vm = WelcomeViewModel(controller: controller)
        self.viewModel = vm
        let hosting = NSHostingView(rootView: WelcomeView(viewModel: vm))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Chào mừng đến với vflow"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("không dùng") }

    func update(_ model: StatusModel) { viewModel.model = model }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startPolling()
        if let window { WindowRectDebug.printIfRequested(window, label: "welcome") }
    }

    private func startPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refreshPermissionsNow() }
        }
    }

    private func stopPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

extension WelcomeWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopPolling()
        controller.markWelcomeSeen()
    }
}

@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published var model: StatusModel
    unowned let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        self.model = controller.statusModel
    }
}

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel
    @State private var tryItText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            Text("Giữ **⌥ Option trái**, nói, nhả phím — chữ hiện ngay ở nơi đang gõ, không cần đăng nhập, không gửi âm thanh ra ngoài máy. vflow cần 3 quyền hệ thống dưới đây để làm việc đó.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(PermissionKind.allCases, id: \.self) { kind in
                    PermissionStepRow(kind: kind, granted: granted(kind))
                }
            }
            tryItSection
            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(minWidth: 480, minHeight: 440)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let mark = BrandIcon.headerMark(pointSize: 36) {
                Image(nsImage: mark).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Chào mừng đến với vflow").font(.title2.weight(.semibold))
                Text("Đọc chính tả tiếng Việt, chạy hoàn toàn trong máy.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func granted(_ kind: PermissionKind) -> Bool {
        viewModel.model.permissions.first { $0.kind == kind }?.granted ?? false
    }

    @ViewBuilder private var tryItSection: some View {
        if PermissionsProgress.allGranted(viewModel.model.permissions) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Đã cấp đủ 3 quyền — sẵn sàng dùng!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Thử: bấm vào ô dưới đây, giữ ⌥ trái, nói một câu, rồi nhả phím.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Thử nói ở đây…", text: $tryItText)
                    .textFieldStyle(.roundedBorder)
            }
            .cardBackground()
        }
    }

    private var footer: some View {
        HStack {
            Button("Mở README") { viewModel.controller.openHelpDocument() }
            Spacer()
            Button("Bắt đầu dùng vflow") { viewModel.controller.closeWelcome() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }
}

private struct PermissionStepRow: View {
    let kind: PermissionKind
    let granted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Label(kind.title, systemImage: kind.symbol).font(.body.weight(.medium))
                Text("Để \(kind.why).").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Đã cấp").font(.footnote.weight(.medium)).foregroundStyle(.green)
            } else {
                Button("Mở Cài đặt hệ thống") { kind.request(); kind.openSettings() }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title): \(granted ? "đã cấp" : "chưa cấp")")
    }
}
