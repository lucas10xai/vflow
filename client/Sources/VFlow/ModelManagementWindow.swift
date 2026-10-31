import AppKit
import SwiftUI
import VFlowCore

/// Màn hình "Chọn model nhận dạng giọng nói" (Cài đặt › Nâng cao): liệt kê `GET /v1/models`, cho tải
/// model chưa có (đồng ý giấy phép trước, dùng ĐÚNG `ModelDownloader` đã có), chọn model đang dùng
/// (lựa chọn CỤC BỘ, gửi `?model=` ở từng yêu cầu — xem `AppController.selectedModelID`), xoá model đã
/// tải (có xác nhận, không cho xoá model đang dùng).
@MainActor
final class ModelManagementViewModel: ObservableObject {
    unowned let controller: AppController
    @Published var rows: [ModelPickerRow] = []
    @Published var loaded = false
    @Published var loadError: ClientError?
    /// Model đang "nạp" (activateModel) — disable nút trong lúc chờ.
    @Published var activatingID: String?
    @Published var activationError: [String: String] = [:]
    @Published var deletionError: [String: String] = [:]
    @Published var confirmDeleteID: String?
    /// Model đang xin đồng ý giấy phép trước khi tải (chưa bắt đầu tải).
    @Published var pendingAcceptID: String?
    @Published var downloadingID: String?
    @Published var downloadState: ModelDownloadState = .idle
    private var downloader: ModelDownloader?

    init(controller: AppController) { self.controller = controller }

    func load() async {
        switch await controller.fetchModels() {
        case .success(let models):
            rows = ModelPickerBuilder.rows(models: models, selectedID: controller.selectedModelID)
            loadError = nil
        case .failure(let e):
            loadError = e
        }
        loaded = true
    }

    /// "Dùng model này" — model ĐÃ TẢI: nạp ngay (ping `/v1/teach?model=`) để thấy lỗi sớm, rồi lưu
    /// lựa chọn. Model CHƯA TẢI: mở thẻ xin đồng ý giấy phép trước (xem `requestDownload`).
    func select(_ id: String) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        guard row.availability.isDownloaded else { requestDownload(id); return }
        activationError[id] = nil
        activatingID = id
        Task {
            let result = await controller.activateModel(id)
            activatingID = nil
            switch result {
            case .success:
                controller.selectedModelID = id
                await load()
            case .failure(let e):
                activationError[id] = ErrorText.message(e)
            }
        }
    }

    func requestDownload(_ id: String) { pendingAcceptID = id }
    func cancelDownloadRequest() { pendingAcceptID = nil }

    func confirmDownload(_ id: String) {
        pendingAcceptID = nil
        guard ModelDownloadCoordination.canStart(activeID: downloadingID, requestedID: id) else { return }
        guard let d = controller.makeModelDownloader(modelID: id) else {
            loadError = .configInvalid("Chưa resolve được cấu hình engine nên chưa tải được model.")
            return
        }
        downloadingID = id
        downloadState = .idle
        downloader = d
        d.onState = { [weak self] s in
            guard let self else { return }
            self.downloadState = s
            if case .done = s {
                Task { await self.load() }
            }
        }
        d.start()
    }

    /// Bấm lại "Thử lại" sau khi lỗi — CÙNG id đang hiện lỗi.
    func retryDownload() {
        guard downloadingID != nil else { return }
        downloadState = .idle
        downloader?.start()
    }

    func cancelDownload() { downloader?.cancel() }

    func closeDownloadPanel() {
        if case .downloading = downloadState { return }
        if case .verifying = downloadState { return }
        downloadingID = nil
        downloader = nil
        downloadState = .idle
    }

    func requestDelete(_ id: String) { confirmDeleteID = id }
    func cancelDeleteRequest() { confirmDeleteID = nil }

    func confirmDelete() {
        guard let id = confirmDeleteID else { return }
        confirmDeleteID = nil
        let loadedIDs = Set(rows.filter { $0.availability == .loaded }.map(\.id))
        switch controller.deleteModel(id, loadedIDs: loadedIDs) {
        case .success:
            deletionError[id] = nil
            Task { await load() }
        case .failure(let e):
            deletionError[id] = ModelDeletionText.message(e)
        }
    }
}

struct ModelManagementView: View {
    @ObservedObject var viewModel: ModelManagementViewModel

    var body: some View {
        // TOÀN BỘ nội dung (đầu đề, thẻ giấy phép/tiến độ tải, danh sách model) nằm TRONG MỘT `List`
        // duy nhất — không để `VStack`/`Text` SwiftUI thuần đứng NGOÀI `List` (đã đo thật: khi chụp
        // qua `OffscreenRender.captureRealWindow`/`cacheDisplay`, phần NGOÀI `List` ra trắng trống ở
        // chế độ tối, dù đặt `window.appearance`/`.preferredColorScheme`/chờ thêm run loop — riêng
        // `List`, NSTableView AppKit thuần, luôn ra đúng; mọi màn hình Cài đặt hiện có đều theo đúng
        // mẫu "mọi thứ trong Form/List" nên chưa ai gặp lỗi này trước đây). THẺ XIN GIẤY PHÉP/TIẾN ĐỘ
        // TẢI cũng nằm NGAY TRONG `List` (không phải `.sheet`, vốn là một `NSWindow` CON riêng mà
        // `captureRealWindow` không chụp tới).
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model nhận dạng giọng nói").font(.title2.weight(.semibold))
                    Text("Mỗi model có đánh đổi tốc độ/bộ nhớ/ngôn ngữ khác nhau — xem \u{201C}đo thử\u{201D} trước khi đổi. Chưa chọn model nào ⇒ dùng mặc định hiện có của engine.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            if let id = viewModel.pendingAcceptID {
                Section { LicenseAcceptCard(modelID: id, viewModel: viewModel) }
            } else if let id = viewModel.downloadingID {
                Section { DownloadProgressCard(modelID: id, viewModel: viewModel) }
            }
            if let e = viewModel.loadError {
                Section {
                    Text(ErrorText.message(e)).foregroundStyle(Color.red)
                    Button("Thử lại") { Task { await viewModel.load() } }
                }
            } else if !viewModel.loaded {
                Section { ProgressView("Đang đọc danh sách model…") }
            } else {
                ForEach(viewModel.rows) { row in ModelRow(row: row, viewModel: viewModel) }
            }
        }
        .listStyle(.inset)
        .frame(width: 640, height: 560)
        .tint(Theme.accent)
        .task { if !viewModel.loaded { await viewModel.load() } }
        .alert("Xoá model đã tải?", isPresented: Binding(
            get: { viewModel.confirmDeleteID != nil },
            set: { if !$0 { viewModel.cancelDeleteRequest() } })) {
            Button("Xoá", role: .destructive) { viewModel.confirmDelete() }
            Button("Huỷ", role: .cancel) { viewModel.cancelDeleteRequest() }
        } message: {
            Text("Xoá tệp model khỏi máy để giải phóng đĩa. Tải lại được sau nếu cần.")
        }
    }
}

private struct ModelRow: View {
    let row: ModelPickerRow
    @ObservedObject var viewModel: ModelManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.catalog?.title ?? row.id).font(.headline)
                    Text(languagesText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
            if let catalog = row.catalog {
                Text(catalog.tradeoffLine).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(catalog.measuredCaveat).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Chưa có thông tin đánh đổi cho model này.").font(.footnote).foregroundStyle(.secondary)
            }
            if let err = viewModel.activationError[row.id] {
                Text(err).font(.footnote).foregroundStyle(Color.red)
            }
            if let err = viewModel.deletionError[row.id] {
                Text(err).font(.footnote).foregroundStyle(Color.red)
            }
            actions
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var languagesText: String {
        let names = row.languages.map { TranslationTarget.title(for: $0) }
        let base = names.joined(separator: ", ")
        return row.autoDetect ? "\(base) · tự nhận biết ngôn ngữ" : base
    }

    @ViewBuilder private var statusBadge: some View {
        if row.isSelected {
            Label("Đang dùng", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else {
            Text(row.availability.statusText).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if row.isSelected {
                Text("Đang dùng cho lần đọc chính tả tiếp theo").font(.caption).foregroundStyle(.secondary)
            } else if row.availability.isDownloaded {
                Button(viewModel.activatingID == row.id ? "Đang nạp…" : "Dùng model này") { viewModel.select(row.id) }
                    .disabled(viewModel.activatingID != nil)
            } else if ModelPickerBuilder.canDownload(row) {
                Button("Tải…") { viewModel.requestDownload(row.id) }
                    .disabled(viewModel.downloadingID != nil)
            } else {
                Text("Không tải được: \(row.availability.statusText)").font(.footnote).foregroundStyle(Color.orange)
            }
            if ModelPickerBuilder.canDelete(row) {
                Button("Xoá…", role: .destructive) { viewModel.requestDelete(row.id) }
            }
        }
    }
}

private struct LicenseAcceptCard: View {
    let modelID: String
    @ObservedObject var viewModel: ModelManagementViewModel
    private var catalog: ModelCatalogEntry? { ModelCatalog.entry(for: modelID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Tải \(catalog?.title ?? modelID)").font(.headline)
            if let catalog {
                Text("Dung lượng: \(catalog.downloadSizeText) · Giấy phép \(catalog.licenseName)").font(.callout)
                Text(catalog.licenseSummary).fixedSize(horizontal: false, vertical: true)
                if let url = catalog.licenseURL {
                    Button("Mở trang giấy phép") { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
                }
                Text(catalog.measuredCaveat).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Chưa có thông tin giấy phép sẵn cho model này trong vflow — kiểm tra nguồn trước khi tải.")
                    .foregroundStyle(Theme.warningText).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Huỷ") { viewModel.cancelDownloadRequest() }
                Spacer()
                Button("Đồng ý và tải") { viewModel.confirmDownload(modelID) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Color.primary.opacity(0.04))
    }
}

private struct DownloadProgressCard: View {
    let modelID: String
    @ObservedObject var viewModel: ModelManagementViewModel
    private var catalog: ModelCatalogEntry? { ModelCatalog.entry(for: modelID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Đang tải \(catalog?.title ?? modelID)").font(.headline)
            stateSection
            buttons
        }
        .padding(Theme.Spacing.lg)
        .background(Color.primary.opacity(0.04))
    }

    @ViewBuilder private var stateSection: some View {
        switch viewModel.downloadState {
        case .idle:
            ProgressView()
        case .downloading(let p):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let f = p?.fraction { ProgressView(value: f) } else { ProgressView() }
                Text(progressText(p)).font(.footnote).foregroundStyle(.secondary)
            }
        case .verifying:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Đang kiểm mã băm SHA-256…").font(.footnote).foregroundStyle(.secondary)
            }
        case .done:
            Label("Đã tải xong, đã kiểm mã băm khớp.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .cancelled:
            Label("Đã huỷ tải.", systemImage: "xmark.circle").foregroundStyle(Theme.warningText)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressText(_ p: ModelPullOutput.Progress?) -> String {
        guard let p else { return "Đang kết nối tới nguồn tải…" }
        let done = String(format: "%.1f", p.doneMB)
        if let t = p.totalMB { return "Đã tải \(done) / \(String(format: "%.1f", t)) MB" }
        return "Đã tải \(done) MB"
    }

    @ViewBuilder private var buttons: some View {
        switch viewModel.downloadState {
        case .idle, .downloading, .verifying:
            HStack {
                Spacer()
                Button("Huỷ tải") { viewModel.cancelDownload() }
                    .disabled({ if case .verifying = viewModel.downloadState { return true } else { return false } }())
            }
        case .done:
            HStack { Spacer(); Button("Xong") { viewModel.closeDownloadPanel() }.keyboardShortcut(.defaultAction) }
        case .cancelled, .failed:
            HStack {
                Button("Đóng") { viewModel.closeDownloadPanel() }
                Spacer()
                Button("Thử lại") { viewModel.retryDownload() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
    }
}

@MainActor
final class ModelManagementWindowController: NSWindowController, NSWindowDelegate {
    let viewModel: ModelManagementViewModel

    init(viewModel: ModelManagementViewModel) {
        self.viewModel = viewModel
        let hosting = NSHostingView(rootView: ModelManagementView(viewModel: viewModel))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Chọn model nhận dạng giọng nói"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("không dùng") }

    func show() {
        guard !OffscreenRender.enabled else { return }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// `--render-offscreen models[:dangtai]`: chụp cửa sổ THẬT bằng `cacheDisplay` (xem
    /// `OffscreenRender.captureRealWindow`) — màn hình này có `List`, mà `ImageRenderer` ra ảnh
    /// placeholder/kích thước sai cho `List` khi cửa sổ chưa từng lên màn hình (đã đo thật, xem
    /// doc comment `OffscreenRender`; `ModelDownloadWindowController` dùng `ImageRenderer` được vì
    /// KHÔNG có `List`).
    func captureOffscreen(to path: String) {
        guard let window else { return }
        OffscreenRender.captureRealWindow(window, colorScheme: OffscreenRender.colorScheme, to: path)
    }
}
