import AppKit
import SwiftUI
import VFlowCore

/// Cửa sổ Cài đặt CHUẨN macOS (⌘,; menu "vflow › Cài đặt…") — TÁCH khỏi cửa sổ chính "vflow", có
/// thanh tab biểu tượng 5 mục (Chung · Giọng nói · Ứng dụng · Dữ liệu & Riêng tư · Nâng cao). Bản 8 mục
/// cũ chen một hàng nên 6/8 nhãn bị cắt chữ; nay 5 mục, cửa sổ rộng tối thiểu 720 pt (kéo giãn được) và
/// mỗi mục là một `Form` cuộn được gồm nhiều `Section` có tiêu đề. Một cửa sổ duy nhất (singleton), gọi
/// lại chỉ đưa lên trước + đổi mục thay vì mở cửa sổ mới.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// Cỡ nội dung mặc định/tối thiểu của cửa sổ Cài đặt (pt).
    static let defaultContentSize = NSSize(width: 780, height: 600)
    static let minContentSize = NSSize(width: 720, height: 460)

    private unowned let controller: AppController
    private let viewModel: SettingsWindowViewModel
    private var framePersistence: WindowFramePersistence?

    init(controller: AppController) {
        self.controller = controller
        let vm = SettingsWindowViewModel(controller: controller)
        self.viewModel = vm
        let hosting = NSHostingView(rootView: SettingsRootView(viewModel: vm))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Cài đặt vflow"
        window.contentView = hosting
        window.contentMinSize = Self.minContentSize
        window.isReleasedWhenClosed = false
        super.init(window: window)
        // Tên khung MỚI (v2): khung 560 pt đã lưu từ bản 8 tab sẽ làm tab bị cắt chữ nếu được khôi phục.
        framePersistence = WindowFramePersistence(window: window, name: "org.aios.vflow.settingsWindow.v2")
    }

    required init?(coder: NSCoder) { fatalError("không dùng") }

    func update(_ model: StatusModel) { viewModel.model = model }

    func show(tab: SettingsCategory? = nil) {
        if let tab { viewModel.selectedTab = tab }
        guard !OffscreenRender.enabled else { return }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// `--render-offscreen`: chụp cửa sổ Cài đặt THẬT (`window`/`SettingsRootView`, đúng `TabView`/
    /// `Form` sản phẩm) bằng `OffscreenRender.captureRealWindow` — xem `StatusWindow.swift` (U3) để
    /// biết vì sao `cacheDisplay` đúng ở đây, khác kết luận cũ của `ImageRenderer`.
    func captureOffscreen(tab: SettingsCategory, to path: String) {
        viewModel.selectedTab = tab
        guard let window else { return }
        OffscreenRender.captureRealWindow(window, colorScheme: OffscreenRender.colorScheme, to: path)
    }
}

@MainActor
final class SettingsWindowViewModel: ObservableObject {
    @Published var model: StatusModel
    @Published var selectedTab: SettingsCategory = .general
    unowned let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        self.model = controller.statusModel
    }
}

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsWindowViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            GeneralSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.general.title, systemImage: SettingsCategory.general.symbol) }
                .tag(SettingsCategory.general)
            VoiceSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.voice.title, systemImage: SettingsCategory.voice.symbol) }
                .tag(SettingsCategory.voice)
            AppsSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.apps.title, systemImage: SettingsCategory.apps.symbol) }
                .tag(SettingsCategory.apps)
            DataSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.data.title, systemImage: SettingsCategory.data.symbol) }
                .tag(SettingsCategory.data)
            AdvancedSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.advanced.title, systemImage: SettingsCategory.advanced.symbol) }
                .tag(SettingsCategory.advanced)
        }
        .frame(minWidth: SettingsWindowController.minContentSize.width, idealWidth: SettingsWindowController.defaultContentSize.width,
               minHeight: SettingsWindowController.minContentSize.height, idealHeight: SettingsWindowController.defaultContentSize.height)
        .defaultAppStorage(viewModel.controller.appStorageDefaults)
    }
}
