import AppKit
import SwiftUI
import VFlowCore

/// Màn hình xin tải model (O1). CHỈ hiện khi `ModelProvisioning.decide` ra `.needsDownload` — tức là bản
/// dựng KHÔNG kèm model VÀ `<VFLOW_HOME>/models/<id>` chưa có (hoặc hỏng). Bản chủ dự án đang dùng (model
/// đã có ở `~/.vflow/models`) KHÔNG BAO GIỜ thấy màn hình này. Phải bấm "Đồng ý và tải" mới tải.
@MainActor
final class ModelDownloadViewModel: ObservableObject {
    @Published var reason: ModelProvisioning.DownloadReason
    @Published var state: ModelDownloadState
    var onAccept: () -> Void = {}
    var onCancel: () -> Void = {}
    var onClose: () -> Void = {}

    init(reason: ModelProvisioning.DownloadReason, state: ModelDownloadState = .idle) {
        self.reason = reason
        self.state = state
    }
}

struct ModelDownloadView: View {
    @ObservedObject var viewModel: ModelDownloadViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            Text(ModelDownloadInfo.reasonText(viewModel.reason))
                .font(.body).fixedSize(horizontal: false, vertical: true)
            infoCard
            licenseCard
            Spacer(minLength: 0)
            stateSection
            buttons
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 540)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let mark = BrandIcon.headerMark(pointSize: 36) {
                Image(nsImage: mark).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Cần tải model nhận dạng giọng nói").font(.title2.weight(.semibold))
                Text("Chỉ tải một lần. Sau đó vflow chạy hoàn toàn trong máy.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            row("Model", ModelDownloadInfo.title)
            row("Dung lượng", ModelDownloadInfo.downloadSizeText)
            row("Nguồn", ModelDownloadInfo.sourceText)
        }
        .cardBackground()
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Giấy phép \(ModelDownloadInfo.licenseName)", systemImage: "doc.text")
                .font(.headline)
            Text(ModelDownloadInfo.licenseSummary).font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Model này là của tác giả gốc, theo giấy phép riêng của họ — vflow không phân phối nó trong bản phát hành công khai; vflow chỉ tải về máy anh/chị sau khi anh/chị đồng ý.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.md) {
                Button("Mở trang giấy phép") { open(ModelDownloadInfo.licenseURL) }
                Button("Mở trang model") { open(ModelDownloadInfo.modelPageURL) }
            }
        }
        .cardBackground()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(label).font(.callout.weight(.semibold)).frame(width: 84, alignment: .leading)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var stateSection: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .downloading(let p):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let f = p?.fraction { ProgressView(value: f) } else { ProgressView() }
                Text(progressText(p)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .verifying:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Đang kiểm mã băm SHA-256 từng tệp model…").font(.footnote).foregroundStyle(.secondary)
            }
        case .done:
            Label("Đã tải xong và kiểm mã băm khớp. Đang khởi động lại engine để nạp model.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green).font(.callout)
        case .cancelled:
            Label("Đã huỷ tải. Chưa có model nên chưa đọc chính tả được.", systemImage: "xmark.circle")
                .foregroundStyle(Theme.warningText).font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressText(_ p: ModelPullOutput.Progress?) -> String {
        guard let p else { return "Đang kết nối tới nguồn tải…" }
        let done = String(format: "%.1f", p.doneMB)
        if let t = p.totalMB { return "Đã tải \(done) / \(String(format: "%.1f", t)) MB" }
        return "Đã tải \(done) MB"
    }

    private var buttons: some View {
        HStack {
            switch viewModel.state {
            case .idle:
                Button("Để sau") { viewModel.onClose() }
                Spacer()
                Button("Đồng ý và tải (≈ 26 MB)") { viewModel.onAccept() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
            case .downloading, .verifying:
                Spacer()
                Button("Huỷ tải") { viewModel.onCancel() }.disabled({ if case .verifying = viewModel.state { return true } else { return false } }())
            case .done:
                Spacer()
                Button("Xong") { viewModel.onClose() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
            case .cancelled, .failed:
                Button("Đóng") { viewModel.onClose() }
                Spacer()
                Button("Thử lại") { viewModel.onAccept() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

@MainActor
final class ModelDownloadWindowController: NSWindowController, NSWindowDelegate {
    let viewModel: ModelDownloadViewModel

    init(viewModel: ModelDownloadViewModel) {
        self.viewModel = viewModel
        let hosting = NSHostingView(rootView: ModelDownloadView(viewModel: viewModel))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tải model nhận dạng giọng nói"
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


    /// `--render-offscreen modeldownload[:tiendo|:loi]`: chụp nội dung THẬT của màn hình xin tải bằng
    /// `ImageRenderer`, KHÔNG hiện cửa sổ (xem `OffscreenRender.capture`).
    func captureOffscreen(to path: String) {
        OffscreenRender.capture(ModelDownloadView(viewModel: viewModel), size: CGSize(width: 540, height: 560),
                                fixedHeight: false, colorScheme: OffscreenRender.colorScheme, to: path)
    }
}
