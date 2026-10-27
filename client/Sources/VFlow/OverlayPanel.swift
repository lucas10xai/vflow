import Combine
import AppKit
import SwiftUI
import VFlowCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .transcribing
    @Published var level: Float = 0
    /// "Xem chữ chạy trực tiếp" (`POST /v1/partial`) — chữ mờ TẠM, KHÔNG BAO GIỜ chèn vào ô đích;
    /// `nil` khi tắt/không áp dụng (xem `AppController`, `VFlowCore.LivePreviewCoordinator`).
    @Published var livePreviewText: String?
    /// Cỡ HUD (Cài đặt › Chung › Thanh ghi âm) — `OverlayController.show` đọc lại mỗi lần hiện, nên đổi
    /// cài đặt có hiệu lực ở lần ghi kế tiếp, không cần khởi động lại.
    @Published var size: OverlaySize = OverlayPreferences.defaultSize
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsLivePreview: Bool {
        guard model.size.livePreviewLineCount > 0, let t = model.livePreviewText, !t.isEmpty else { return false }
        switch model.state {
        case .listening, .listeningLocked: return true
        default: return false
        }
    }

    /// "Lớn" (4 dòng chữ) dùng khối bo góc thay vì viên thuốc tròn đầu — Capsule cắt chữ ở hai đầu khi cao.
    private var backgroundShape: RoundedRectangle {
        // Bán kính lớn hơn nửa chiều cao bị kẹp về nửa chiều cao ⇒ viên thuốc (như Capsule) với cỡ ≤ "Vừa".
        RoundedRectangle(cornerRadius: model.size == .large ? 22 : 1000, style: .continuous)
    }

    /// Độ rộng khung chữ trực tiếp: vừa bằng chữ một dòng, tối đa `maxPreviewWidth` của cỡ. Phải là
    /// CHIỀU RỘNG XÁC ĐỊNH — với `.frame(maxWidth:)` thì `NSHostingView.fittingSize` (đề xuất bề rộng
    /// "không giới hạn") đo chữ thành MỘT dòng, panel quá thấp và các dòng sau bị cắt.
    private func previewWidth(for text: String) -> CGFloat {
        let natural = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        return min(ceil(natural) + 2, model.size.maxPreviewWidth)
    }

    var body: some View {
        let p = OverlayText.present(model.state)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let mark = BrandIcon.headerMark(pointSize: 16) {
                    Image(nsImage: mark).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                if p.showsSpinner {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: p.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.isError ? Color.red : (p.showsLevel ? Color.orange : Color.primary))
                }
                Text(p.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if p.showsLevel {
                    LevelMeter(level: model.level, animated: !reduceMotion)
                }
            }
            if showsLivePreview, let text = model.livePreviewText {
                let shown = LivePreviewDisplay.capToTail(text)
                Text(shown)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(model.size.livePreviewLineCount)
                    .truncationMode(.head)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: previewWidth(for: shown), alignment: .leading)
                    .accessibilityHidden(true) // chữ tạm — VoiceOver không cần đọc liên tục khi đang gõ
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: model.size.maxContainerWidth)
        .background(backgroundShape.fill(.regularMaterial))
        .overlay(backgroundShape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityLabel)
        .fixedSize()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.state)
        .animation(.easeOut(duration: 0.15), value: model.livePreviewText)
    }
}

/// Thanh sóng âm 6 vạch (xem `VFlowCore.WaveformMeter`) — vạch giữa cao nhất, lệch dần hai bên;
/// mượt theo mức âm khi hoạt ảnh được phép, TĨNH (không hoạt ảnh nhưng vẫn đổi theo mức) khi Reduce
/// Motion bật.
struct LevelMeter: View {
    let level: Float
    let animated: Bool
    private let maxHeight: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<WaveformMeter.defaultBarCount, id: \.self) { i in
                let heightRatio = WaveformMeter.barHeight(level: level, barIndex: i, barCount: WaveformMeter.defaultBarCount)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: maxHeight * heightRatio)
            }
        }
        .frame(height: maxHeight)
        .animation(animated ? .easeOut(duration: 0.08) : nil, value: level)
        .accessibilityHidden(true)
    }
}

/// Panel không viền, không lấy focus, nổi trên mọi Space, giữa đáy màn hình phía trên Dock.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private let panel: OverlayWindow
    private let hosting: NSHostingView<OverlayView>
    private let defaults: UserDefaults
    private var hideTimer: Timer?
    private var previewObserver: AnyCancellable?
    /// Màn hình đã chọn ở lần `show` gần nhất (màn hình đang có con trỏ) — đổi cỡ khi chữ trực tiếp
    /// dài ra phải đặt lại khung trên CÙNG màn hình, không nhảy sang màn hình khác.
    private var placementScreen: NSScreen?
    /// Chế độ chụp ảnh: không tự ẩn.
    var sticky = false

    /// `defaults`: lớp UserDefaults của app (cô lập theo `VFLOW_HOME`) — nơi lưu Vị trí/Cỡ HUD.
    init(defaults: UserDefaults = VFlowDefaults.resolve()) {
        self.defaults = defaults
        hosting = NSHostingView(rootView: OverlayView(model: model))
        panel = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        // Chữ trực tiếp dài ra/ngắn lại làm viên HUD đổi chiều cao — đặt lại khung (neo theo mép đáy
        // hoặc mép trên tuỳ Vị trí). `dropFirst` bỏ giá trị khởi tạo; `async` đợi SwiftUI cập nhật cây
        // view xong rồi mới đo `fittingSize`.
        previewObserver = model.$livePreviewText.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.replaceIfVisible() } }
        }
    }

    /// Khung hiện tại của panel — chỉ để test/kiểm tra (panel chưa chắc đã lên màn hình).
    var panelFrameForTesting: NSRect { panel.frame }
    var placementScreenForTesting: NSScreen? { placementScreen }

    /// `thenRestore`: sau khi `state` tự ẩn (vd. cảnh báo "còn ~20s" trong lúc vẫn đang ghi), hiện
    /// lại trạng thái này thay vì ẩn hẳn thanh — tránh thanh "Đang nghe" biến mất giữa chừng.
    func show(_ state: OverlayState, thenRestore: OverlayState? = nil) {
        // Đọc lại cài đặt mỗi lần hiện: đổi Vị trí/Cỡ ở Cài đặt có hiệu lực ngay lần ghi kế tiếp.
        model.size = OverlayPreferences.size(from: defaults)
        model.state = state
        let p = OverlayText.present(state)
        placementScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        place()
        // `fittingSize` ngay sau khi đổi state/cỡ có thể còn là của cây view cũ (SwiftUI cập nhật trễ một
        // nhịp) — đo lại sau khi run loop xử lý xong để khung luôn khớp nội dung.
        DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.replaceIfVisible() } }
        panel.setAccessibilityLabel(p.accessibilityLabel)
        if !OffscreenRender.enabled {
            panel.orderFrontRegardless()
            announce(state, label: p.accessibilityLabel)
        }
        hideTimer?.invalidate()
        hideTimer = nil
        if let after = p.autoHide, !sticky {
            hideTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let thenRestore { self?.show(thenRestore) } else { self?.hide() }
                }
            }
        }
    }

    /// Đo nội dung rồi đặt khung panel theo Vị trí đã lưu (`OverlayLayout.frame`, hàm thuần có test).
    private func place() {
        hosting.layoutSubtreeIfNeeded()
        let content = hosting.fittingSize
        guard let screen = placementScreen ?? NSScreen.main else { return }
        panel.setFrame(Self.frame(content: content, on: screen, position: OverlayPreferences.position(from: defaults)),
                       display: true)
    }

    private func replaceIfVisible() {
        guard panel.isVisible else { return }
        place()
    }

    /// Cầu nối AppKit → `OverlayLayout`: đổi `NSScreen`/kích thước nội dung sang `OverlayLayout.Rect` rồi
    /// đổi ngược. Dải hai bên notch chỉ lấy CHIỀU RỘNG (xem `OverlayLayout.auxiliaryAreas`) nên đúng cả
    /// màn hình phụ có gốc toạ độ khác 0.
    static func frame(content: CGSize, on screen: NSScreen, position: OverlayPosition) -> NSRect {
        let sf = screen.frame, vf = screen.visibleFrame
        let screenRect = OverlayLayout.Rect(minX: sf.minX, minY: sf.minY, width: sf.width, height: sf.height)
        let aux = OverlayLayout.auxiliaryAreas(screenFrame: screenRect,
                                               leftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
                                               rightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) },
                                               height: screen.safeAreaInsets.top)
        let r = OverlayLayout.frame(
            contentSize: .init(minX: 0, minY: 0, width: content.width, height: content.height),
            screenFrame: screenRect,
            visibleFrame: .init(minX: vf.minX, minY: vf.minY, width: vf.width, height: vf.height),
            auxiliaryLeft: aux?.left, auxiliaryRight: aux?.right,
            position: position, topInset: screen.safeAreaInsets.top)
        return NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }

    func setLevel(_ level: Float) { model.level = level }

    /// "Xem chữ chạy trực tiếp" — xem `OverlayModel.livePreviewText`.
    func setLivePreviewText(_ text: String?) { model.livePreviewText = text }

    /// `--render-offscreen`: chụp nội dung HUD mà KHÔNG BAO GIỜ hiện lên màn hình.
    func captureOffscreen(to path: String) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        OffscreenRender.capture(OverlayView(model: model), size: size, colorScheme: OffscreenRender.colorScheme, to: path)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }

    private func announce(_ state: OverlayState, label: String) {
        if case .listening = state { return } // không cắt lời người dùng khi đang nói
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
