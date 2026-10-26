import AppKit
import SwiftUI
import VFlowCore

/// Cửa sổ Cài đặt CHUẨN macOS (⌘,; menu "vflow › Cài đặt…") — TÁCH khỏi cửa sổ chính "vflow", có
/// thanh công cụ dạng tab biểu tượng (Chung/Đám mây/Lịch sử & riêng tư/Nâng cao). Một cửa sổ duy
/// nhất (singleton), gọi lại chỉ đưa lên trước + đổi mục thay vì mở cửa sổ mới.
@MainActor
final class SettingsWindowController: NSWindowController {
    private unowned let controller: AppController
    private let viewModel: SettingsWindowViewModel
    private var framePersistence: WindowFramePersistence?

    init(controller: AppController) {
        self.controller = controller
        let vm = SettingsWindowViewModel(controller: controller)
        self.viewModel = vm
        let hosting = NSHostingView(rootView: SettingsRootView(viewModel: vm))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Cài đặt vflow"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        super.init(window: window)
        framePersistence = WindowFramePersistence(window: window, name: "org.aios.vflow.settingsWindow")
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
            CloudSettingsSection(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.cloud.title, systemImage: SettingsCategory.cloud.symbol) }
                .tag(SettingsCategory.cloud)
            DataSettingsTab(model: viewModel.model, controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.data.title, systemImage: SettingsCategory.data.symbol) }
                .tag(SettingsCategory.data)
            HotkeysSettingsTab(controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.hotkeys.title, systemImage: SettingsCategory.hotkeys.symbol) }
                .tag(SettingsCategory.hotkeys)
            HistoryPrivacySettingsTab(controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.historyPrivacy.title, systemImage: SettingsCategory.historyPrivacy.symbol) }
                .tag(SettingsCategory.historyPrivacy)
            AdvancedSettingsTab(controller: viewModel.controller)
                .tabItem { Label(SettingsCategory.advanced.title, systemImage: SettingsCategory.advanced.symbol) }
                .tag(SettingsCategory.advanced)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 380, idealHeight: 420)
        .defaultAppStorage(viewModel.controller.appStorageDefaults)
    }
}
