import AppKit
import SwiftUI
import VFlowCore

/// Mô hình quan sát được cho SwiftUI, bọc `StatusModel` (mô hình thuần, dùng chung với menu).
@MainActor
final class StatusWindowViewModel: ObservableObject {
    @Published var model: StatusModel
    @Published var selectedTab: MainTab
    unowned let controller: AppController

    init(controller: AppController, selectedTab: MainTab) {
        self.controller = controller
        self.model = controller.statusModel
        self.selectedTab = selectedTab
    }
}

/// Cửa sổ chính "vflow" — chỗ đứng chính của app (Dock, ⌘-Tab), KHÔNG phụ thuộc biểu tượng thanh
/// menu (biểu tượng có thể bị thanh menu chật/notch che, và có công tắc tự ẩn/hiện). Mở khi khởi
/// động (tuỳ công tắc), khi bấm biểu tượng Dock/`open VFlow.app` lại, hoặc từ menu ứng dụng/menu
/// thanh trạng thái. Đóng cửa sổ (nút đỏ) KHÔNG thoát app — ghi âm bằng phím nóng vẫn hoạt động.
@MainActor
final class StatusWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private let viewModel: StatusWindowViewModel
    private let window: NSWindow
    private var permissionTimer: Timer?

    init(controller: AppController, initialTab: MainTab = .overview) {
        self.controller = controller
        self.viewModel = StatusWindowViewModel(controller: controller, selectedTab: initialTab)
        let hosting = NSHostingView(rootView: MainWindowView(viewModel: viewModel))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "vflow"
        w.minSize = NSSize(width: 640, height: 480)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("org.aios.vflow.mainWindow")
        if w.setFrameUsingName("org.aios.vflow.mainWindow") == false { w.center() }
        self.window = w
        super.init()
        w.delegate = self
    }

    /// Luôn cùng dữ liệu với menu (xem `AppController.refreshUI`).
    func update(_ model: StatusModel) { viewModel.model = model }

    func show(tab: MainTab? = nil) {
        if let tab { viewModel.selectedTab = tab }
        window.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    /// ID cửa sổ thật trên màn hình, dùng để `screencapture -l <id>` từng tab riêng (không chụp
    /// toàn màn hình vì có dữ liệu cá nhân khác trên máy).
    var windowNumber: Int { window.windowNumber }

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

/// Cửa sổ chính: thanh bên 4 mục (Tổng quan, Lịch sử, Từ điển, Cài đặt) + nội dung bên phải.
struct MainWindowView: View {
    @ObservedObject var viewModel: StatusWindowViewModel
    private var model: StatusModel { viewModel.model }
    private var controller: AppController { viewModel.controller }

    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, selection: $viewModel.selectedTab) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .font(.system(size: 13))
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    tabContent
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Text("Đóng cửa sổ không thoát vflow; thoát bằng ⌘Q.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder private var tabContent: some View {
        switch viewModel.selectedTab {
        case .overview: OverviewView(model: model, controller: controller)
        case .history: HistoryView(controller: controller)
        case .dictionary: DictionaryView(controller: controller)
        case .settings: SettingsView(model: model, controller: controller)
        }
    }
}
