import AppKit
import Foundation
import Testing

/// Kiểm tài nguyên logo sinh bởi `client/scripts/make-icon.sh` (xem mục "LOGO MỚI" trong task):
/// `AppIcon.icns` đủ kích thước chuẩn, ảnh thanh menu tồn tại ở 3 kích thước và không rỗng.
/// Dùng `#filePath` để tìm `client/` tương đối với vị trí tệp test này (không phụ thuộc CWD).
private let clientDir: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VFlowCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // client
}()

@Suite struct ResourceTests {
    @Test func appIconIcnsExistsAndIsNonEmpty() {
        let path = clientDir.appendingPathComponent("Resources/AppIcon.icns").path
        guard let data = FileManager.default.contents(atPath: path) else {
            Issue.record("thiếu \(path) — chạy client/scripts/make-icon.sh trước"); return
        }
        #expect(!data.isEmpty)
        // Chữ ký tệp .icns bắt đầu bằng "icns" (big-endian magic).
        #expect(data.prefix(4) == Data("icns".utf8))
    }

    /// `iconutil -c iconset` giải ngược .icns rồi kiểm đủ 10 ảnh chuẩn (16…512, @1x/@2x — @2x của
    /// 512 chính là 1024px, macOS không có mục icns riêng cho 1024 ngoài dạng đó).
    @Test func appIconIcnsHasAllStandardSizes() throws {
        let icnsPath = clientDir.appendingPathComponent("Resources/AppIcon.icns").path
        guard FileManager.default.fileExists(atPath: icnsPath) else {
            Issue.record("thiếu \(icnsPath) — chạy client/scripts/make-icon.sh trước"); return
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-icon-check-\(UUID().uuidString)")
        let iconset = tmp.appendingPathComponent("AppIcon.iconset")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "iconset", icnsPath, "-o", iconset.path]
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "iconutil giải .icns lỗi")

        let expected = ["icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png", "icon_32x32@2x.png",
                        "icon_128x128.png", "icon_128x128@2x.png", "icon_256x256.png", "icon_256x256@2x.png",
                        "icon_512x512.png", "icon_512x512@2x.png"]
        for name in expected {
            let f = iconset.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: f.path), "thiếu kích thước \(name) trong AppIcon.icns")
        }
    }

    @Test(arguments: ["menubar-mark-18.png", "menubar-mark-18@2x.png", "menubar-mark-18@3x.png"])
    func menuBarMarkExistsNonEmptyAndLoadable(name: String) {
        let path = clientDir.appendingPathComponent("Resources/\(name)").path
        guard let data = FileManager.default.contents(atPath: path) else {
            Issue.record("thiếu \(path) — chạy client/scripts/make-icon.sh trước"); return
        }
        #expect(!data.isEmpty)
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "\(name) không phải PNG hợp lệ")
    }

    /// Biểu tượng thanh menu TEMPLATE (đơn sắc, `make-icon-template.swift`): tồn tại ở 3 kích
    /// thước, và mọi điểm ảnh có alpha>0 phải là đen tuyệt đối (R=G=B=0) — đúng yêu cầu "template"
    /// của AppKit (`NSImage.isTemplate = true` ở `BrandIcon.swift` vẽ lại thành trắng/đen theo nền
    /// thanh menu dựa trên alpha, KHÔNG dựa trên RGB gốc — nhưng nếu RGB gốc không phải đen tuyệt
    /// đối thì không còn là ảnh "đơn sắc" đúng nghĩa và dễ lộ màu lạ ở công cụ khác đọc file trực
    /// tiếp, vd. Finder preview/Icon Composer).
    @Test(arguments: ["menubar-mark-18-template.png", "menubar-mark-18-template@2x.png", "menubar-mark-18-template@3x.png"])
    func menuBarTemplateMarkIsMonochromeBlack(name: String) throws {
        let path = clientDir.appendingPathComponent("Resources/\(name)").path
        guard let img = NSImage(contentsOfFile: path),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("thiếu hoặc không đọc được \(path) — chạy client/scripts/make-icon.sh trước"); return
        }
        let w = cg.width, h = cg.height
        #expect(w > 0 && h > 0)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            Issue.record("không tạo được context đọc pixel cho \(name)"); return
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var opaqueCount = 0
        var nonBlackCount = 0
        for i in 0..<(w * h) {
            let o = i * 4
            guard pixels[o + 3] > 0 else { continue }
            opaqueCount += 1
            if pixels[o] != 0 || pixels[o + 1] != 0 || pixels[o + 2] != 0 { nonBlackCount += 1 }
        }
        #expect(opaqueCount > 0, "\(name) hoàn toàn trong suốt — không có hình gì để làm template")
        #expect(nonBlackCount == 0, "\(name) có \(nonBlackCount)/\(opaqueCount) điểm ảnh có alpha>0 nhưng KHÔNG phải đen — không phải ảnh template đơn sắc hợp lệ")
    }

    /// Hai tệp gốc do chủ dự án cung cấp KHÔNG được bị script đổi/nén lại.
    @Test func originalBrandingFilesAreUntouchedAndFullSize() {
        for name in ["logo-main.png", "logo-mark.png"] {
            let path = clientDir.appendingPathComponent("Resources/branding/\(name)").path
            guard let data = FileManager.default.contents(atPath: path) else {
                Issue.record("thiếu \(path)"); return
            }
            #expect(data.count > 10_000, "\(name) có vẻ bị nén/ghi đè nhỏ bất thường")
        }
    }

    /// Giải .icns ra ảnh 1024px (icon_512x512@2x) rồi đọc trực tiếp pixel: góc canvas phải trong
    /// suốt (biểu tượng lấp đầy ô bo góc, không full-bleed vuông), vùng giữa (lệch khỏi chữ V) phải
    /// là màu cam (không phải trắng/xám/trong suốt), và phải có điểm đen ở vị trí chữ V — bắt lỗi
    /// nếu make-icon.swift sinh ra icon rỗng, lộn màu, hoặc không có chữ V/nền cam thật.
    private static func load1024Pixels() -> (pixels: [UInt8], width: Int)? {
        let icnsPath = clientDir.appendingPathComponent("Resources/AppIcon.icns").path
        guard FileManager.default.fileExists(atPath: icnsPath) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-icon-pixels-\(UUID().uuidString)")
        let iconset = tmp.appendingPathComponent("AppIcon.iconset")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "iconset", icnsPath, "-o", iconset.path]
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let pngPath = iconset.appendingPathComponent("icon_512x512@2x.png").path
        guard let img = NSImage(contentsOfFile: pngPath),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (pixels, w)
    }

    @Test func appIconCornersAreTransparent() throws {
        guard let (pixels, w) = Self.load1024Pixels() else {
            Issue.record("không giải được AppIcon.icns — chạy client/scripts/make-icon.sh trước"); return
        }
        for (x, y) in [(8, 8), (w - 8, 8), (8, w - 8), (w - 8, w - 8)] {
            let a = pixels[(y * w + x) * 4 + 3]
            #expect(a < 30, "góc (\(x),\(y)) không trong suốt (alpha=\(a)) — biểu tượng có vẻ full-bleed vuông thay vì ô bo góc")
        }
    }

    @Test func appIconCenterAreaIsOrange() throws {
        guard let (pixels, w) = Self.load1024Pixels() else {
            Issue.record("không giải được AppIcon.icns — chạy client/scripts/make-icon.sh trước"); return
        }
        // (512,400): bên trong nền cam, phía trên đỉnh chữ V — xem ghi chú đo đạc trong báo cáo C4.
        let i = (400 * w + 512) * 4
        let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2], a = pixels[i + 3]
        #expect(a == 255, "điểm nền không đặc (alpha=\(a))")
        #expect(r > 180 && g > 50 && g < 160 && b < 40, "điểm nền không phải màu cam (r=\(r) g=\(g) b=\(b))")
    }

    @Test func appIconHasBlackGlyphPoint() throws {
        guard let (pixels, w) = Self.load1024Pixels() else {
            Issue.record("không giải được AppIcon.icns — chạy client/scripts/make-icon.sh trước"); return
        }
        // (512,600): đỉnh chữ V — xem ghi chú đo đạc trong báo cáo C4.
        let i = (600 * w + 512) * 4
        let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2], a = pixels[i + 3]
        #expect(a == 255, "điểm chữ V không đặc (alpha=\(a))")
        #expect(r < 40 && g < 40 && b < 40, "điểm chữ V không phải màu đen (r=\(r) g=\(g) b=\(b))")
    }
}
