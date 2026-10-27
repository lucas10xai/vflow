import AppKit
import Foundation
import Testing
@testable import VFlow
@testable import VFlowCore

/// Đặt khung HUD THẬT qua `OverlayController` trên màn hình thật của máy test — KHÔNG BAO GIỜ hiện
/// panel (`OffscreenRender.enabled` chặn `orderFront`), chỉ đọc `panel.frame`. Không có màn hình
/// (CI không đầu) ⇒ các test bỏ qua phần đo.
@MainActor
@Suite struct OverlayControllerTests {
    static let longText = String(repeating: "đây là một câu rất dài để lấp đầy nhiều dòng chữ chạy trực tiếp ", count: 6)

    func isolated() -> (UserDefaults, () -> Void) {
        let name = "org.aios.vflow.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    func place(position: OverlayPosition, size: OverlaySize, previewText: String?) -> (frame: NSRect, screen: NSScreen)? {
        guard !NSScreen.screens.isEmpty else { return nil }
        OffscreenRender.enabled = true
        defer { OffscreenRender.enabled = CommandLine.arguments.contains("--render-offscreen") }
        let (d, cleanup) = isolated(); defer { cleanup() }
        OverlayPreferences.save(position: position, to: d)
        OverlayPreferences.save(size: size, to: d)
        let c = OverlayController(defaults: d)
        c.setLivePreviewText(previewText)
        c.show(.listening(level: 0.5))
        guard let screen = c.placementScreenForTesting else { return nil }
        return (c.panelFrameForTesting, screen)
    }

    @Test func everyPositionAndSizeStaysInsideItsScreenAndRespectsMenuBar() {
        for position in OverlayPosition.allCases {
            for size in OverlaySize.allCases {
                guard let (f, screen) = place(position: position, size: size, previewText: Self.longText) else { return }
                #expect(screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(position) \(size): \(f) ngoài \(screen.frame)")
                if position == .topNearNotch {
                    #expect(f.maxY <= screen.visibleFrame.maxY - OverlayLayout.edgeMargin + 0.5, "\(position) \(size)")
                    #expect(f.maxY <= screen.frame.maxY - screen.safeAreaInsets.top + 0.5)
                } else {
                    #expect(abs(f.minY - (screen.visibleFrame.minY + OverlayLayout.edgeMargin)) < 0.5, "\(position) \(size)")
                }
            }
        }
    }

    @Test func largerSizeGivesTallerAndWiderBarWhenLivePreviewIsLong() {
        guard let compact = place(position: .bottom, size: .compact, previewText: Self.longText),
              let medium = place(position: .bottom, size: .medium, previewText: Self.longText),
              let large = place(position: .bottom, size: .large, previewText: Self.longText) else { return }
        #expect(compact.frame.height < medium.frame.height, "Gọn không có chữ trực tiếp")
        #expect(medium.frame.height < large.frame.height, "Lớn 4 dòng cao hơn Vừa 2 dòng")
        #expect(medium.frame.width < large.frame.width)
        #expect(compact.frame.width < medium.frame.width)
    }

    @Test func compactIgnoresLivePreviewEntirely() {
        guard let without = place(position: .bottom, size: .compact, previewText: nil),
              let with = place(position: .bottom, size: .compact, previewText: Self.longText) else { return }
        #expect(with.frame.size == without.frame.size)
    }

    /// Cùng nội dung, hai Vị trí: "Cạnh notch" ở ĐỈNH, "Dưới màn hình" ở ĐÁY — và cỡ khung không đổi.
    @Test func positionOnlyMovesTheBarNotResizesIt() {
        guard let bottom = place(position: .bottom, size: .medium, previewText: nil),
              let top = place(position: .topNearNotch, size: .medium, previewText: nil) else { return }
        #expect(bottom.frame.size == top.frame.size)
        #expect(top.frame.midY > bottom.frame.midY)
    }
}
