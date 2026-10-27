import Testing
@testable import VFlowCore

@Suite struct SettingsPaneTests {
    /// 8 tab cũ chen một hàng ⇒ 6/8 nhãn bị cắt chữ. Giữ tối đa 5 mục cấp một.
    @Test func atMostFivePanes() {
        #expect(SettingsPane.allCases.count <= 5)
        #expect(Set(SettingsPane.allCases.map(\.title)).count == SettingsPane.allCases.count, "tiêu đề không trùng")
        #expect(Set(SettingsPane.allCases.map(\.rawValue)).count == SettingsPane.allCases.count)
    }

    @Test func rawValueRoundTrips() {
        for pane in SettingsPane.allCases {
            #expect(SettingsPane(rawValue: pane.rawValue) == pane)
        }
    }

    /// MỌI tên mục của bản 8 tab cũ (cờ `--open-settings-tab`, `caidat:<mục>`, `openSettingsWindow(tab:)`)
    /// vẫn phải mở đúng mục chứa chức năng đó sau khi gộp.
    @Test(arguments: [
        ("general", SettingsPane.general),
        ("voice", .voice),
        ("apps", .apps),
        ("data", .data),
        ("advanced", .advanced),
        ("hotkeys", .voice), // "Phím tắt" cũ ⇒ Giọng nói
        ("cloud", .advanced), // "Đám mây" cũ ⇒ Nâng cao (9Router)
        ("historyPrivacy", .data), // "Lịch sử & riêng tư" cũ ⇒ Dữ liệu & Riêng tư
    ])
    func legacyAndCurrentNamesResolve(name: String, expected: SettingsPane) {
        #expect(SettingsPane.resolve(name) == expected)
        #expect(SettingsPane(rawValue: name) == expected)
    }

    @Test func unknownNamesDoNotResolve() {
        for name in ["", "Hotkeys", "settings", "tudien", "cloud "] {
            #expect(SettingsPane.resolve(name) == nil, "\(name)")
            #expect(SettingsPane(rawValue: name) == nil)
        }
    }

    /// Nút "Mở Cài đặt › Dữ liệu" ở tab Thống kê và "Mở Cài đặt › Chung" ở thẻ biểu tượng bị che vẫn tới
    /// đúng mục (chức năng thống kê nằm trong Dữ liệu & Riêng tư; micro/giao diện trong Chung).
    @Test func existingCallSitesStillLandOnTheirFeature() {
        #expect(SettingsPane.data.title == "Dữ liệu & Riêng tư")
        #expect(SettingsPane.general.title == "Chung")
    }

    /// Heuristic thô: bản 8 mục cũ có tổng 69 ký tự nhãn và bị cắt ở 560 pt; bản 5 mục đo thật (ảnh chụp
    /// ngoài màn hình) dùng ~435 pt cho 48 ký tự. Giữ tổng ≤ 55 để còn dư chỗ ở cỡ tối thiểu 720 pt.
    @Test func titlesAreShortEnoughForOneRow() {
        let total = SettingsPane.allCases.map { $0.title.count }.reduce(0, +)
        #expect(total <= 55, "tổng \(total) ký tự — quá dài sẽ bị cắt ở 720 pt")
        #expect(SettingsPane.allCases.allSatisfy { $0.title.count <= 20 })
    }
}
