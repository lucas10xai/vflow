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
    private var framePersistence: WindowFramePersistence?

    init(controller: AppController, initialTab: MainTab = .overview) {
        self.controller = controller
        self.viewModel = StatusWindowViewModel(controller: controller, selectedTab: initialTab)
        let hosting = NSHostingView(rootView: MainWindowView(viewModel: viewModel))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "vflow"
        w.minSize = NSSize(width: 800, height: 560)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        self.window = w
        super.init()
        w.delegate = self
        framePersistence = WindowFramePersistence(window: w, name: "org.aios.vflow.mainWindow")
    }

    /// Luôn cùng dữ liệu với menu (xem `AppController.refreshUI`).
    func update(_ model: StatusModel) { viewModel.model = model }

    func show(tab: MainTab? = nil) {
        if let tab { viewModel.selectedTab = tab }
        guard !OffscreenRender.enabled else { return }
        window.makeKeyAndOrderFront(nil)
        startPermissionPolling()
        WindowRectDebug.printIfRequested(window, label: "main-\(viewModel.selectedTab.rawValue)", forceHeight: 680)
    }

    /// `--render-offscreen`: chụp nội dung mà KHÔNG lên màn hình — xem `OffscreenRender`. Dựng lại
    /// nội dung TRỰC TIẾP bằng `MainWindowOffscreenPreview` (HStack thanh bên + nội dung, KHÔNG qua
    /// `NavigationSplitView`/`List`/`ScrollView` thật) — đã đo thật: `ImageRenderer` không chụp đúng
    /// các container đó khi cửa sổ chưa từng lên màn hình (ra ảnh hỏng/placeholder). Với Từ
    /// điển/Snippets, tải dữ liệu TRƯỚC (qua `await`, không qua `.task` nội bộ của view — vốn
    /// không kịp hoàn tất trước khi `ImageRenderer` chụp). KHÔNG gồm thanh tiêu đề/toolbar (chrome
    /// AppKit, xem `OffscreenRender.capture`).
    func captureOffscreen(tab: MainTab, to path: String) async {
        viewModel.selectedTab = tab
        var dictionaryEntries: [DictionaryEntry]?
        var snippetEntries: [SnippetEntry]?
        if tab == .dictionary, case .success(let e) = await controller.fetchDictionary() { dictionaryEntries = e }
        if tab == .snippets, case .success(let e) = await controller.fetchSnippets() { snippetEntries = e }
        let preview = MainWindowOffscreenPreview(viewModel: viewModel, dictionaryEntries: dictionaryEntries, snippetEntries: snippetEntries)
        OffscreenRender.capture(preview, size: CGSize(width: 960, height: 680), fixedHeight: false, colorScheme: OffscreenRender.colorScheme, to: path)
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private var model: StatusModel { viewModel.model }
    private var controller: AppController { viewModel.controller }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                CloseHintBanner()
                ScrollView {
                    tabContent
                        .padding(Theme.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.top)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .tint(Theme.accent)
        // Tiêu đề MỘT nơi duy nhất: thanh công cụ cửa sổ (không lặp tiêu đề lớn trong nội dung).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedTab.title).font(.headline)
            }
        }
        .background(keyboardShortcuts)
        .defaultAppStorage(controller.appStorageDefaults)
    }

    private var sidebar: some View {
        SidebarContent(selectedTab: viewModel.selectedTab, missingPermissionsCount: model.missingPermissions.count) { tab in
            viewModel.selectedTab = tab
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
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

/// Nội dung thanh bên (logo+tên, 2 nhóm mục) — tách khỏi `MainWindowView` để dùng lại được cho
/// `MainWindowOffscreenPreview` (chụp ảnh offscreen, không qua `NavigationSplitView` thật).
private struct SidebarContent: View {
    let selectedTab: MainTab
    let missingPermissionsCount: Int
    let onSelect: (MainTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(MainTab.Group.allCases) { group in
                Text(group.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, 2)
                ForEach(MainTab.allCases.filter { $0.group == group }) { tab in
                    SidebarRow(tab: tab, selected: tab == selectedTab, badge: badge(tab)) { onSelect(tab) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let mark = BrandIcon.headerMark(pointSize: 22) {
                Image(nsImage: mark).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            }
            Text("vflow").font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("vflow")
    }

    /// Huy hiệu nhỏ ở Tổng quan khi có việc cần chú ý (quyền thiếu) — chấm cam, không chặn điều hướng.
    private func badge(_ tab: MainTab) -> Int {
        guard tab == .overview else { return 0 }
        return missingPermissionsCount
    }
}

/// `--render-offscreen`: tương tự `MainWindowOffscreenPreview` nhưng dùng cho Lịch sử/Từ
/// điển/Snippets (những mục có `List`/`.task` bất đồng bộ — xem `ListOffscreenPreviews.swift`).
/// `dictionaryEntries`/`snippetEntries`: đã tải TRƯỚC qua `await` (xem
/// `StatusWindowController.captureOffscreen`), `nil` khi không áp dụng cho `tab` hiện tại.
private struct MainWindowOffscreenPreview: View {
    @ObservedObject var viewModel: StatusWindowViewModel
    var dictionaryEntries: [DictionaryEntry]?
    var snippetEntries: [SnippetEntry]?

    var body: some View {
        HStack(spacing: 0) {
            SidebarContent(selectedTab: viewModel.selectedTab, missingPermissionsCount: viewModel.model.missingPermissions.count) { _ in }
                .frame(width: 190)
                .background(.ultraThinMaterial)
            Divider()
            // KHÔNG bọc `ScrollView` ở đây (khác cửa sổ thật) — đã đo: `ImageRenderer` không chụp
            // được nội dung bên trong `ScrollView`/`List` khi cửa sổ chưa từng lên màn hình (ra ảnh
            // "cấm" thay vì nội dung thật); để nội dung tự giãn hết chiều cao thật thay vì cuộn.
            VStack(alignment: .leading, spacing: 0) {
                CloseHintBanner()
                offscreenTabContent
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Theme.accent)
        .defaultAppStorage(viewModel.controller.appStorageDefaults)
    }

    @ViewBuilder private var offscreenTabContent: some View {
        switch viewModel.selectedTab {
        case .overview: OverviewView(model: viewModel.model, controller: viewModel.controller)
        case .history: HistoryOffscreenPreview(controller: viewModel.controller, query: "")
        case .dictionary: DictionaryOffscreenPreview(entries: dictionaryEntries ?? [])
        case .snippets: SnippetsOffscreenPreview(entries: snippetEntries ?? [])
        }
    }
}

/// Mục thanh bên tự vẽ (KHÔNG dùng `List(selection:)`): macOS luôn tô mục `List` đang chọn bằng
/// màu nhấn HỆ THỐNG (xanh/đa sắc theo System Settings, bỏ qua `.tint`) khi `listStyle(.sidebar)` —
/// không có API công khai để đổi màu đó, nên tự vẽ viên thuốc cam thương hiệu ở đây.
private struct SidebarRow: View {
    let tab: MainTab
    let selected: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: tab.symbol).frame(width: 18).font(.body)
                Text(tab.title).font(.body)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.sm)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(badge > 0 ? "\(tab.title), \(badge) việc cần chú ý" : tab.title)
    }
}

/// Nhắc "đóng cửa sổ không thoát vflow" MỘT LẦN (thay dòng chân trang cố định của U1) — đóng được,
/// nhớ bằng UserDefaults (qua `.defaultAppStorage`, cô lập theo VFLOW_HOME — xem `VFlowDefaults`).
private struct CloseHintBanner: View {
    @AppStorage("hasSeenCloseHint") private var hasSeenCloseHint = false

    var body: some View {
        if !hasSeenCloseHint {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                Text("Đóng cửa sổ không thoát vflow — mở lại ở Dock, ⌘-Tab, hoặc menu thanh trạng thái. Thoát hẳn bằng ⌘Q.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { hasSeenCloseHint = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đã hiểu, không hiện lại")
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)
            .accessibilityElement(children: .combine)
        }
    }
}
