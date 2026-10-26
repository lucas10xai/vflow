import AppKit
import SwiftUI
import Testing
@testable import VFlow
@testable import VFlowCore

/// Test hồi quy BỐ CỤC cửa sổ chính (U3) — tái hiện đúng đường tạo cửa sổ thật
/// (`StatusWindowController`/`MainWindowView`, KHÔNG phải bản giả) ở nhiều kích thước NGOÀI MÀN
/// HÌNH (`alphaValue = 0`, toạ độ rất xa mọi màn hình thật, KHÔNG BAO GIỜ `orderFront`/`orderBack`/
/// `makeKeyAndOrderFront`/`NSApp.activate()`), rồi đo trực tiếp `NSScrollView` (lớp AppKit đứng sau
/// `ScrollView` của vùng chi tiết) để khẳng định bố cục ĐÚNG bằng SỐ, không chỉ bằng mắt.
///
/// Nguyên nhân gốc đã tìm được (xem báo cáo): khi cửa sổ được đặt khung đã lưu (`setFrame`/
/// `setFrameUsingName`) TRƯỚC KHI từng hiện lên màn hình, `NavigationSplitView` không luôn truyền
/// đúng chiều cao cột thật xuống `ScrollView` bên trong — `NSScrollView` tự đo ra một chiều cao "lý
/// tưởng" KHÔNG đổi theo kích thước cửa sổ thật (đo được: luôn ra cùng một số bất kể cửa sổ cao
/// 680pt hay 1048pt), khiến nội dung bị cắt ở ĐẦU và còn khoảng trống thừa ở CUỐI. Sửa bằng cách ép
/// kích thước tường minh qua `GeometryReader` (xem `StatusWindow.swift`) thay vì để
/// `NavigationSplitView` tự suy — test ở đây khẳng định đúng mối quan hệ đó bằng số.
@MainActor
enum LayoutRegressionHarness {
    struct Measurement {
        var windowFrame: NSRect
        var contentViewBounds: NSRect
        /// `NSScrollView` của vùng chi tiết (trong `detail:` của `NavigationSplitView`) — view DUY
        /// NHẤT khớp trong cây vì Tổng quan không có `List`/`ScrollView` nào khác.
        var detailScrollView: NSRect?
    }

    /// Dựng `StatusWindowController` THẬT (không qua `AppController.start()` — tránh spawn engine
    /// con/`configError`) với `StatusModel` "sẵn sàng" sạch, ở tab Tổng quan, tại `frame` cho trước
    /// (mô phỏng đúng trình tự `WindowFramePersistence` dùng: `setFrame` TRƯỚC khi cửa sổ từng hiện),
    /// đo NGOÀI MÀN HÌNH, rồi dọn dẹp. `VFLOW_HOME` cô lập mỗi lần gọi — không đụng `~/.vflow` thật.
    static func measure(frame: NSRect, colorScheme: ColorScheme = .light) async throws -> Measurement {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-layout-test-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        setenv("VFLOW_HOME", tmp, 1)
        defer {
            unsetenv("VFLOW_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        // Bắt buộc: các `*WindowController.show()` không bao giờ `makeKeyAndOrderFront`/
        // `NSApp.activate()` dù test này không gọi `show()` — đặt cờ để nhất quán với mọi đường khác
        // có thể vô tình kích hoạt (vd. nếu ai đó sau này gọi `c.start()` ở đây).
        OffscreenRender.enabled = true
        defer { OffscreenRender.enabled = CommandLine.arguments.contains("--render-offscreen") }

        let c = AppController()
        let sw = StatusWindowController(controller: c)
        sw.update(StatusModel.build(
            engineState: .running(owned: true, health: Health(version: "0.1.0", models: [
                ModelStatus(id: "zipformer-vi-30m", kind: "local", loaded: true, reason: nil),
            ])),
            configError: nil, lastError: nil,
            permissions: PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) },
            mode: .auto, canRetryLast: false, launchAtLogin: false, conflictWarning: nil, hotkeysActive: true))
        sw.selectTabForTesting(.overview)

        let window = sw.window
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        // Mô phỏng ĐÚNG trình tự thật: cửa sổ vừa tạo ở kích thước mặc định (960x680, xem
        // `StatusWindowController.init`) rồi NGAY LẬP TỨC được đặt khung đã lưu — TRƯỚC khi từng lên
        // màn hình. Đây chính là trình tự `WindowFramePersistence` áp dụng.
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: -50000, y: -50000))

        try? await Task.sleep(for: .milliseconds(200))
        guard let contentView = window.contentView else {
            return Measurement(windowFrame: window.frame, contentViewBounds: .zero, detailScrollView: nil)
        }
        contentView.layoutSubtreeIfNeeded()

        var found: NSRect?
        func walk(_ v: NSView) {
            if let sv = v as? NSScrollView { found = sv.frame }
            for sub in v.subviews { walk(sub) }
        }
        walk(contentView)

        assertNeverOnScreen()
        return Measurement(windowFrame: window.frame, contentViewBounds: contentView.bounds, detailScrollView: found)
    }

    /// Bắt buộc ở MỌI test dựng cửa sổ thật — bằng chứng cho báo cáo (dán nguyên output).
    static func assertNeverOnScreen() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        print("VFLOW_TEST_OFFSCREEN_CHECK pid=\(pid) on-screen-windows=\(mine.count)")
        #expect(mine.isEmpty, "Cửa sổ thử nghiệm KHÔNG được xuất hiện trên màn hình — thấy \(mine.count): \(mine)")
    }
}

@Suite("U3 — bố cục cửa sổ chính")
struct LayoutRegressionTests {
    /// (nhãn, kích thước) theo đúng danh sách acceptance của U3.
    static let sizes: [(String, NSSize)] = [
        ("min-800x560", NSSize(width: 800, height: 560)),
        ("default-960x680", NSSize(width: 960, height: 680)),
        ("large-1200x900", NSSize(width: 1200, height: 900)),
        ("tall-880x1300", NSSize(width: 880, height: 1300)),
    ]

    /// Bất biến cốt lõi: chiều cao `NSScrollView` của vùng chi tiết phải THEO SÁT chiều cao cửa sổ
    /// thật (không phải một hằng số không đổi bất kể cửa sổ cao bao nhiêu — đúng lỗi đã tìm thấy).
    /// So ĐỘ CHÊNH LỆCH giữa hai cỡ khác nhau: nếu `NSScrollView` đo đúng, chênh lệch chiều cao của
    /// nó phải gần bằng chênh lệch chiều cao `contentView` (cùng vùng `CloseHintBanner` cố định phía
    /// trên không đổi). Dung sai 2pt cho sai số làm tròn điểm/pixel.
    @MainActor
    @Test func scrollViewHeightTracksRealWindowHeightNotStaleConstant() async throws {
        let small = try await LayoutRegressionHarness.measure(
            frame: NSRect(x: 100, y: 100, width: 800, height: 560))
        let large = try await LayoutRegressionHarness.measure(
            frame: NSRect(x: 100, y: 100, width: 880, height: 1300))

        let smallSV = try #require(small.detailScrollView, "không tìm thấy NSScrollView ở cỡ 800x560")
        let largeSV = try #require(large.detailScrollView, "không tìm thấy NSScrollView ở cỡ 880x1300")

        let contentHeightDelta = large.contentViewBounds.height - small.contentViewBounds.height
        let scrollViewHeightDelta = largeSV.height - smallSV.height

        print("VFLOW_LAYOUT small: window=\(small.windowFrame) content=\(small.contentViewBounds) scrollView=\(smallSV)")
        print("VFLOW_LAYOUT large: window=\(large.windowFrame) content=\(large.contentViewBounds) scrollView=\(largeSV)")
        print("VFLOW_LAYOUT contentHeightDelta=\(contentHeightDelta) scrollViewHeightDelta=\(scrollViewHeightDelta)")

        // Dung sai 30pt: `CloseHintBanner` phía trên có thể đổi chiều cao vài điểm theo chiều rộng
        // (chữ xuống dòng khác nhau) — không liên quan tới lỗi đang kiểm. Lỗi THẬT (đã đo trước khi
        // sửa): `scrollViewHeightDelta` gần như BẰNG 0 dù `contentHeightDelta` lớn (cửa sổ cao hơn
        // hẳn nhưng `NSScrollView` vẫn đo ra đúng một số cố định) — 30pt vẫn tách biệt rõ với 0.
        #expect(abs(scrollViewHeightDelta - contentHeightDelta) < 30,
                "NSScrollView không theo kịp chiều cao cửa sổ thật (lệch \(abs(scrollViewHeightDelta - contentHeightDelta))pt) — đúng triệu chứng lỗi U3: ScrollView tự đo ra một chiều cao cố định bất kể cửa sổ cao bao nhiêu")
    }

    /// Mép TRÊN của `NSScrollView` (vùng chi tiết) phải nằm NGAY DƯỚI `CloseHintBanner` cố định
    /// (khoảng cách nhỏ, KHÔNG PHỤ THUỘC kích thước cửa sổ) ở MỌI kích thước trong acceptance — lỗi
    /// THẬT (đã đo trước khi sửa) là khoảng cách này PHÌNH TO theo cửa sổ (cửa sổ càng cao,
    /// `NSScrollView` càng bị đẩy xuống xa khỏi đỉnh vì nó tự đo một chiều cao cố định).
    @MainActor
    @Test(arguments: sizes)
    func scrollViewTopGapStaysSmallRegardlessOfWindowHeight(_ sizeCase: (String, NSSize)) async throws {
        let (label, size) = sizeCase
        let m = try await LayoutRegressionHarness.measure(
            frame: NSRect(x: 100, y: 100, width: size.width, height: size.height))
        let sv = try #require(m.detailScrollView, "[\(label)] không tìm thấy NSScrollView")
        // Hệ AppKit: y=0 là ĐÁY; khoảng cách từ mép trên scrollView tới mép trên `contentView` chỉ
        // nên là chiều cao `CloseHintBanner` (~43pt đo thực tế) — không bao giờ lớn hơn 80pt.
        let topGap = m.contentViewBounds.height - (sv.origin.y + sv.height)
        print("VFLOW_LAYOUT[\(label)] contentView.height=\(m.contentViewBounds.height) topGap=\(topGap) scrollView=\(sv)")
        #expect(topGap >= 0 && topGap < 80,
                "[\(label)] khoảng cách phía trên NSScrollView = \(topGap)pt — quá lớn, nội dung bị đẩy lệch/cắt ở đầu (lỗi U3)")
    }

    /// `NSScrollView` không bao giờ cao hơn vùng chứa nó (không tràn ra ngoài phía dưới, để lại
    /// khoảng trống bất thường hay chồng lấn) ở MỌI kích thước trong acceptance.
    @MainActor
    @Test(arguments: sizes)
    func scrollViewNeverTallerThanContainer(_ sizeCase: (String, NSSize)) async throws {
        let (label, size) = sizeCase
        let m = try await LayoutRegressionHarness.measure(
            frame: NSRect(x: 100, y: 100, width: size.width, height: size.height))
        let sv = try #require(m.detailScrollView, "[\(label)] không tìm thấy NSScrollView")
        #expect(sv.height <= m.contentViewBounds.height + 1,
                "[\(label)] NSScrollView (\(sv.height)pt) cao hơn vùng chứa (\(m.contentViewBounds.height)pt)")
    }

    /// Khung đã lưu BẤT HỢP LỆ (nhỏ hơn tối thiểu) phải được chuẩn hoá về đúng kích thước tối thiểu
    /// khi cửa sổ thật mở lên — kiểm tích hợp qua `WindowFramePersistence` (không chỉ hàm thuần).
    @MainActor
    @Test func invalidSavedFrameBelowMinSizeIsNormalizedOnOpen() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-frame-norm-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        setenv("VFLOW_HOME", tmp, 1)
        defer {
            unsetenv("VFLOW_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let defaults = VFlowDefaults.resolve()
        // Khung lưu từ lần trước: nhỏ hơn hẳn tối thiểu (800x560) — vd. do lỗi/khung cũ.
        defaults.set("100 100 300 200 0 0 2056 1210", forKey: "frame.org.aios.vflow.mainWindow")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 800, height: 560)
        _ = WindowFramePersistence(window: window, name: "org.aios.vflow.mainWindow")

        print("VFLOW_LAYOUT normalized frame = \(window.frame)")
        #expect(window.frame.width >= 800)
        #expect(window.frame.height >= 560)
    }

    /// Khung đã lưu nằm HOÀN TOÀN ngoài mọi màn hình hiện có (vd. màn hình ngoài đã tháo) phải được
    /// đưa về vị trí nhìn thấy được, không "biến mất" ngoài tầm với.
    @MainActor
    @Test func invalidSavedFrameOffAllScreensIsNormalizedOnOpen() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-frame-norm-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        setenv("VFLOW_HOME", tmp, 1)
        defer {
            unsetenv("VFLOW_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let defaults = VFlowDefaults.resolve()
        defaults.set("50000 50000 960 680 0 0 2056 1210", forKey: "frame.org.aios.vflow.mainWindow")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 800, height: 560)
        _ = WindowFramePersistence(window: window, name: "org.aios.vflow.mainWindow")

        print("VFLOW_LAYOUT re-centered frame = \(window.frame)")
        let screens = NSScreen.screens.map(\.visibleFrame)
        #expect(WindowFrameValidation.intersectsAnyScreen(window.frame, screens: screens),
                "cửa sổ vẫn ngoài mọi màn hình sau khi mở — không chuẩn hoá được")
    }
}
