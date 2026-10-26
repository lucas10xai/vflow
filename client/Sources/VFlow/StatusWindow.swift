import AppKit
import SwiftUI
import VFlowCore

/// Mô hình quan sát được cho SwiftUI, bọc `StatusModel` (mô hình thuần, dùng chung với menu).
@MainActor
final class StatusWindowViewModel: ObservableObject {
    @Published var model: StatusModel
    @Published var selectedTab: MainTab
    unowned let controller: AppController
    /// CHỈ cho `--snapshot` (U3) — xem `DictionaryView.init(debugOpenEditor:)`.
    @Published var debugOpenDictionaryEditor: (term: String, spokenText: String)?

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
    /// `internal` (không `private`) để test hồi quy bố cục & công cụ `--snapshot` (U3) truy cập
    /// được cửa sổ THẬT — KHÔNG được gọi `makeKeyAndOrderFront`/`orderFront`/`NSApp.activate()` trên
    /// giá trị này từ nơi khác (xem `OffscreenRender`).
    let window: NSWindow
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

    /// Chọn mục thanh bên KHÔNG hiện cửa sổ — dùng cho test hồi quy bố cục & `--snapshot` (U3), nơi
    /// `show(tab:)` không phù hợp vì nó `startPermissionPolling()`.
    func selectTabForTesting(_ tab: MainTab) { viewModel.selectedTab = tab }

    /// `--render-offscreen tudien:them-loi`: mở sẵn sheet Thêm mục từ điển với lỗi hợp lệ (có thuật
    /// ngữ, CHƯA có cách nói) — xem `DictionaryView.init(debugOpenEditor:)`. GIỚI HẠN ĐÃ BIẾT: `.sheet`
    /// của SwiftUI là một `NSWindow` CON riêng (`window.attachedSheet`), và `NSWindow.beginSheet` chỉ
    /// gắn được khi cửa sổ cha `isVisible` — đã thử `orderBack` (bật `isVisible` không đưa lên
    /// trước) để ép gắn sheet, nhưng đo được AppKit tự dịch cửa sổ cha VÀO LẠI vùng màn hình thật khi
    /// đó (`CGWindowListCopyWindowInfo` báo on-screen) — KHÔNG AN TOÀN, nên bỏ kỹ thuật đó. Ảnh chụp
    /// ở đây vì vậy là CỬA SỔ CHÍNH (có lỗi hợp lệ đã bật ở `DictionaryView`, nhưng sheet không hiện
    /// trong ảnh) — nói thẳng giới hạn này trong báo cáo, không giả vờ đã chụp được sheet.
    func captureDictionaryAddInvalidOffscreen(to path: String) {
        viewModel.selectedTab = .dictionary
        viewModel.debugOpenDictionaryEditor = (term: "deploy", spokenText: "")
        OffscreenRender.captureRealWindow(window, colorScheme: OffscreenRender.colorScheme, to: path)
    }

    func show(tab: MainTab? = nil) {
        if let tab { viewModel.selectedTab = tab }
        guard !OffscreenRender.enabled else { return }
        window.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    /// `--render-offscreen`: chụp cửa sổ chính THẬT (`window`/`MainWindowView`, đúng
    /// `NavigationSplitView`/`List`/`ScrollView` sản phẩm — KHÔNG phải bản giả) bằng
    /// `OffscreenRender.captureRealWindow` (xem đó để biết lý do `cacheDisplay` đúng ở đây, khác kết
    /// luận cũ của `ImageRenderer`). Với Từ điển/Snippets: dữ liệu đến từ ENGINE THẬT qua
    /// `.task(id: model.engineReady)` bên trong `DictionaryView`/`SnippetsView` — script `--snapshot`
    /// phải tự chạy engine thật trỏ vào `VFLOW_HOME` cô lập có hạt giống dữ liệu TRƯỚC khi gọi cờ
    /// này (xem `client/scripts/snapshot.sh`); nếu engine chưa sẵn sàng, ảnh THÀNH THẬT hiện "Đang
    /// chờ engine khởi động…" (đúng trạng thái, không phải lỗi).
    func captureOffscreen(tab: MainTab, to path: String) async {
        viewModel.selectedTab = tab
        // Lịch sử/Từ điển/Snippets tải dữ liệu qua `.onAppear`/`.task(id:)` SAU khi mục được chọn —
        // chưa kịp chạy nếu chụp NGAY (khác Tổng quan, đồng bộ). Đợi một nhịp cho kịp (đọc file cục
        // bộ/gọi engine thật qua loopback) rồi mới chụp — KHÔNG đụng `--render-wait-ms` (đợi TRƯỚC
        // khi mở cửa sổ, phục vụ việc khác).
        if tab == .history || tab == .dictionary || tab == .snippets {
            try? await Task.sleep(for: .milliseconds(500))
        }
        // GIỚI HẠN ĐÃ BIẾT (U3): đã đo — dù dữ liệu tải đúng (tiêu đề "Lịch sử (N)"/"Từ điển (N)"
        // hiện đúng số), các HÀNG bên trong `List` không luôn vẽ ra khi cửa sổ chưa từng lên màn
        // hình, kể cả đợi tới 5 GIÂY hay dựng cửa sổ THẲNG vào mục đó (không qua chuyển mục) — không
        // phải lỗi thời gian. Đã thử cô lập nguyên nhân (List đơn giản, List+Section+selection,
        // List trong ScrollView lồng, chuyển mục rồi mới hiện List) — mọi trường hợp ĐƠN LẺ đều
        // chụp đúng; chỉ KHÔNG đúng khi là CHÍNH `HistoryView`/`DictionaryView`/`SnippetsView` thật
        // trong cây cửa sổ đầy đủ (NavigationSplitView + GeometryReader + toolbar `.searchable`...).
        // Không tìm được biến cụ thể gây khác biệt trong thời gian cho phép — nói thẳng trong báo
        // cáo thay vì đoán, không phải lỗi hồi quy của U3 (bố cục Tổng quan/thanh bên đã đúng).
        OffscreenRender.captureRealWindow(window, colorScheme: OffscreenRender.colorScheme, to: path)
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
            // `GeometryReader` + `.frame(width:height:)` tường minh: KHÔNG để `NavigationSplitView`
            // tự suy chiều cao cột (xem phần "Nguyên nhân gốc" ở `detail` bên dưới — thanh bên dùng
            // chung cơ chế cột của `NavigationSplitView` nên cùng rủi ro).
            GeometryReader { proxy in
                sidebar
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            // NGUYÊN NHÂN GỐC (U3): khi cửa sổ được đặt khung (`setFrame`/`setFrameUsingName` —
            // xem `WindowFramePersistence`) TRƯỚC KHI từng hiện lên màn hình, `NavigationSplitView`
            // không luôn truyền đúng chiều cao cột THẬT của cửa sổ xuống cho `ScrollView` bên trong;
            // `NSScrollView` (lớp AppKit đứng sau `ScrollView`) khi đó tự đo ra MỘT chiều cao "lý
            // tưởng" cố định không đổi theo kích thước cửa sổ thật — nội dung bị cắt ở ĐẦU (phần
            // thừa phía trên bị đẩy ra ngoài vùng nhìn thấy) và còn khoảng trống thừa ở CUỐI. Đã đo
          // bằng cách tái hiện cửa sổ thật ngoài màn hình (xem `VFlowTests/LayoutRegressionTests.swift`)
            // và kiểm trực tiếp `NSScrollView.frame`: SAI (không đổi dù cửa sổ cao 680 hay 1048pt)
            // trước khi sửa, ĐÚNG sau khi sửa. `layoutSubtreeIfNeeded`/`window.layoutIfNeeded`/
            // `displayIfNeeded` KHÔNG tự sửa được — phải ép kích thước tường minh bằng
            // `GeometryReader` thay vì để `NavigationSplitView` tự suy.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    CloseHintBanner()
                    ScrollView {
                        tabContent
                            .padding(Theme.Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
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
        // (b) Nút bánh răng Cài đặt ở thanh công cụ, phía phải — cùng cửa sổ Cài đặt duy nhất với
        // nút ở chân thanh bên/menu (xem mục 5 trong yêu cầu).
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.openSettingsWindow() } label: { Image(systemName: "gearshape") }
                    .help("Cài đặt… (⌘,)")
                    .accessibilityLabel("Cài đặt")
            }
        }
        .background(keyboardShortcuts)
        .defaultAppStorage(controller.appStorageDefaults)
    }

    private var sidebar: some View {
        SidebarContent(selectedTab: viewModel.selectedTab, missingPermissionsCount: model.missingPermissions.count,
                       onSelect: { tab in viewModel.selectedTab = tab },
                       onOpenSettings: { controller.openSettingsWindow() })
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
        case .dictionary: DictionaryView(model: model, controller: controller, debugOpenEditor: viewModel.debugOpenDictionaryEditor)
        case .snippets: SnippetsView(model: model, controller: controller)
        }
    }
}

/// Nội dung thanh bên (logo+tên, 2 nhóm mục) — tách khỏi `MainWindowView` để đọc/kiểm tách bạch.
private struct SidebarContent: View {
    let selectedTab: MainTab
    let missingPermissionsCount: Int
    let onSelect: (MainTab) -> Void
    let onOpenSettings: () -> Void

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
            Divider().padding(.horizontal, Theme.Spacing.sm)
            // (a) Nút bánh răng Cài đặt cố định ở chân thanh bên (xem mục 5 trong yêu cầu) — cùng
            // cửa sổ Cài đặt duy nhất với nút thanh công cụ/menu, không nhân bản.
            Button(action: onOpenSettings) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "gearshape").frame(width: 18).font(.body)
                    Text("Cài đặt").font(.body)
                    Spacer()
                    Text("⌘,").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, 2)
            .accessibilityLabel("Cài đặt")
            .accessibilityHint("⌘,")
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
