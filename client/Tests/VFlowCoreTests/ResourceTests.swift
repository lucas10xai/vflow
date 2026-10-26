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
}
