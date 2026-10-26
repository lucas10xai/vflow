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
        WindowRectDebug.printIfRequested(window, label: "main-\(viewModel.selectedTab.rawValue)", forceHeight: 1100)
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

/// Cửa sổ chính: thanh bên có logo+tên ở đầu, 4 mục xếp theo 2 nhóm ("Sử dụng": Tổng quan/Lịch sử;
/// "Cá nhân hoá": Từ điển/Snippets — Cài đặt KHÔNG còn ở đây, xem `SettingsWindow.swift`) + nội
/// dung bên phải, thanh công cụ thống nhất, phím tắt ⌘1…⌘4 chuyển mục, ⌘, mở Cài đặt.
struct MainWindowView: View {
    @ObservedObject var viewModel: StatusWindowViewModel
    private var model: StatusModel { viewModel.model }
    private var controller: AppController { viewModel.controller }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                HeaderBar(tab: viewModel.selectedTab)
                Divider()
                ScrollView {
                    tabContent
                        .padding(Theme.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Text("Đóng cửa sổ không thoát vflow; thoát bằng ⌘Q.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .help("Ghi âm bằng phím nóng và engine vẫn hoạt động khi cửa sổ đóng. Mở lại ở Dock, ⌘-Tab, hoặc menu thanh trạng thái.")
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedTab.title).font(.headline)
            }
        }
        .background(keyboardShortcuts)
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedTab) {
            sidebarHeader
            ForEach(MainTab.Group.allCases) { group in
                Section(group.rawValue) {
                    ForEach(MainTab.allCases.filter { $0.group == group }) { tab in
                        sidebarRow(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }

    private var sidebarHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let mark = BrandIcon.headerMark(pointSize: 22) {
                Image(nsImage: mark).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            }
            Text("vflow").font(.system(size: 15, weight: .semibold))
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("vflow")
        .listRowSeparator(.hidden)
    }

    private func sidebarRow(_ tab: MainTab) -> some View {
        Label(tab.title, systemImage: tab.symbol)
            .badge(sidebarBadge(tab))
            .tag(tab)
    }

    /// Huy hiệu nhỏ ở Tổng quan khi có việc cần chú ý (quyền thiếu) — chấm cam, không chặn điều hướng.
    private func sidebarBadge(_ tab: MainTab) -> Int {
        guard tab == .overview else { return 0 }
        return model.missingPermissions.count
    }

    /// ⌘1…⌘4 chuyển mục thanh bên (nút ẩn, chỉ mang phím tắt — `MainTab.keyboardShortcutDigit`).
    private var keyboardShortcuts: some View {
        ForEach(MainTab.allCases) { tab in
            Button("") { viewModel.selectedTab = tab }
                .keyboardShortcut(KeyEquivalent(tab.keyboardShortcutDigit), modifiers: .command)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch viewModel.selectedTab {
        case .overview: OverviewView(model: model, controller: controller)
        case .history: HistoryView(controller: controller)
        case .dictionary: DictionaryView(model: model, controller: controller)
        case .snippets: SnippetsView(model: model, controller: controller)
        }
    }
}

/// Đầu nội dung cửa sổ chính: chỉ còn tiêu đề (logo đã chuyển lên đầu thanh bên, xem
/// `sidebarHeader`) — tránh lặp logo hai lần trong cùng cửa sổ.
private struct HeaderBar: View {
    let tab: MainTab

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(tab.title)
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("vflow — \(tab.title)")
    }
}
