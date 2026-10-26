import AppKit
import SwiftUI
import VFlowCore

/// Mô hình quan sát được cho SwiftUI, bọc `StatusModel` (mô hình thuần, dùng chung với menu).
@MainActor
final class StatusWindowViewModel: ObservableObject {
    @Published var model: StatusModel
    unowned let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        self.model = controller.statusModel
    }
}

/// Cửa sổ trạng thái "vflow" — cách điều khiển CHÍNH, không phụ thuộc biểu tượng thanh menu
/// (biểu tượng có thể bị thanh menu chật/notch che). Mở khi khởi động (tuỳ công tắc), khi mở
/// lại app đang chạy, hoặc từ menu "Mở cửa sổ vflow". Đóng cửa sổ KHÔNG thoát app.
@MainActor
final class StatusWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private let viewModel: StatusWindowViewModel
    private let window: NSWindow
    private var permissionTimer: Timer?

    init(controller: AppController) {
        self.controller = controller
        self.viewModel = StatusWindowViewModel(controller: controller)
        let hosting = NSHostingView(rootView: StatusWindowView(viewModel: viewModel))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "vflow"
        w.minSize = NSSize(width: 420, height: 480)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()
        self.window = w
        super.init()
        w.delegate = self
    }

    /// Luôn cùng dữ liệu với menu (xem `AppController.refreshUI`).
    func update(_ model: StatusModel) { viewModel.model = model }

    func show() {
        window.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopPermissionPolling()
    }

    /// Mỗi 2 giây khi cửa sổ đang hiện: kiểm lại quyền thật (vd. sau khi bật trong System Settings).
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refreshPermissionsNow() }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

struct StatusWindowView: View {
    @ObservedObject var viewModel: StatusWindowViewModel
    private var model: StatusModel { viewModel.model }
    private var controller: AppController { viewModel.controller }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let warning = model.conflictWarning {
                    ConflictBanner(text: warning)
                }
                Label("Giữ ⌥ Option trái để nói, nhả ra để chữ hiện ở chỗ con trỏ", systemImage: "mic.circle")
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityLabel("Giữ Option trái để nói, nhả ra để chữ hiện ở chỗ con trỏ")

                EngineSection(model: model)
                PermissionsSection(permissions: model.permissions)
                ModeSection(mode: model.mode) { controller.mode = $0 }

                if let error = model.lastError {
                    ErrorSection(text: error)
                }

                ActionsSection(model: model, controller: controller)

                Text("Nếu không thấy biểu tượng vflow trên thanh menu (thanh menu chật hoặc bị notch che), hãy mở lại app để hiện cửa sổ này.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

private struct ConflictBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct EngineSection: View {
    let model: StatusModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Engine")
            Text(model.engineSummary).font(.system(size: 13))
            if model.models.isEmpty {
                Text("Chưa đọc được /healthz").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(model.models, id: \.id) { m in
                    HStack(spacing: 6) {
                        Image(systemName: m.loaded ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(m.loaded ? Color.green : Color.orange)
                        Text(EngineAPI.menuLine(m)).font(.system(size: 13))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct PermissionsSection: View {
    let permissions: [PermissionItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Quyền macOS")
            ForEach(permissions, id: \.kind) { p in
                HStack {
                    Label(p.kind.title, systemImage: p.kind.symbol)
                        .font(.system(size: 13))
                    Spacer()
                    Text(p.statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(p.granted ? Color.green : Color.orange)
                    Button("Cấp quyền…") {
                        p.kind.request()
                        p.kind.openSettings()
                    }
                    .accessibilityLabel("Cấp quyền \(p.kind.title)")
                    .disabled(p.granted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.kind.title): \(p.statusText)")
            }
        }
    }
}

private struct ModeSection: View {
    let mode: DictationMode
    let onChange: @MainActor (DictationMode) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Chế độ")
            Picker("Chế độ", selection: Binding(get: { mode }, set: onChange)) {
                ForEach(DictationMode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct ErrorSection: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Lỗi gần nhất")
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct ActionsSection: View {
    let model: StatusModel
    let controller: AppController
    @AppStorage("showWindowOnLaunch") private var showWindowOnLaunch = ShowWindowPreference.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Thao tác")
            HStack(spacing: 10) {
                Button("Thử lại lần cuối") { controller.retryLast() }
                    .disabled(!model.canRetryLast)
                Button("Khởi động lại engine") { controller.restartEngine() }
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
            }
            Toggle("Hiện cửa sổ này khi mở app", isOn: $showWindowOnLaunch)
                .font(.system(size: 13))
            Toggle("Bật khi đăng nhập", isOn: Binding(
                get: { model.launchAtLogin },
                set: { _ in controller.toggleLaunchAtLogin() }))
                .font(.system(size: 13))
            Button("Thoát vflow") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
