import AppKit
import SwiftUI
import VFlowCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .transcribing
    @Published var level: Float = 0
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = OverlayText.present(model.state)
        HStack(spacing: 8) {
            Image(systemName: p.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.isError ? Color.red : (p.showsLevel ? Color.orange : Color.white))
            Text(p.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if p.showsLevel {
                LevelMeter(level: model.level, animated: !reduceMotion)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 460)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityLabel)
        .fixedSize()
    }
}

/// Thanh mức âm 5 vạch; Reduce Motion ⇒ không hoạt ảnh.
struct LevelMeter: View {
    let level: Float
    let animated: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Float(i) / 5
                RoundedRectangle(cornerRadius: 1)
                    .fill(level > threshold ? Color.orange : Color.white.opacity(0.25))
                    .frame(width: 3, height: 6 + CGFloat(i) * 2.5)
            }
        }
        .frame(height: 18)
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
    private var hideTimer: Timer?
    /// Chế độ chụp ảnh: không tự ẩn.
    var sticky = false

    init() {
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
    }

    func show(_ state: OverlayState) {
        model.state = state
        let p = OverlayText.present(state)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let vf = screen?.visibleFrame { // visibleFrame đã trừ Dock và thanh menu
            panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.minY + 18, width: size.width, height: size.height),
                           display: true)
        }
        panel.setAccessibilityLabel(p.accessibilityLabel)
        panel.orderFrontRegardless()
        announce(state, label: p.accessibilityLabel)
        hideTimer?.invalidate()
        hideTimer = nil
        if let after = p.autoHide, !sticky {
            hideTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    func setLevel(_ level: Float) { model.level = level }

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
