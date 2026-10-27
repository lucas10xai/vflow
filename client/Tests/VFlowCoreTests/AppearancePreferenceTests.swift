import Foundation
import Testing
@testable import VFlowCore

@Suite struct AppearancePreferenceTests {
    func isolated() -> (UserDefaults, () -> Void) {
        let name = "org.aios.vflow.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    @Test func defaultIsSystemWhenNothingSaved() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        #expect(AppearancePreference.load(from: d) == .system)
        #expect(AppearancePreference.default == .system)
    }

    @Test func chosenAppearanceIsPersistedAndReloaded() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        for p in AppearancePreference.allCases {
            p.save(to: d)
            #expect(AppearancePreference.load(from: d) == p)
        }
    }

    @Test func garbageStoredValueMeansSystemNotForcedDark() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        d.set("midnight", forKey: AppearancePreference.defaultsKey)
        #expect(AppearancePreference.load(from: d) == .system)
    }

    @Test func titlesAndSymbolsAreDistinctSoTheMenuIsUnambiguous() {
        let titles = Set(AppearancePreference.allCases.map(\.title))
        let symbols = Set(AppearancePreference.allCases.map(\.symbol))
        #expect(titles.count == 3)
        #expect(symbols.count == 3)
    }
}

@Suite struct WarningTextContrastTests {
    /// Chữ cảnh báo ở giao diện sáng phải đạt WCAG AA (4.5:1) trên cả nền trắng lẫn nền cửa sổ xám nhạt
    /// (~#ECECEC) — cam hệ thống không đạt, đó là lỗi gốc khiến "Chưa đặt model…" gần như không đọc được.
    @Test func lightWarningTextMeetsAAOnWhiteAndWindowGray() throws {
        let text = try #require(ContrastText.relativeLuminance(hex: BrandColor.warningTextOnLightHex))
        for bg in ["FFFFFF", "ECECEC"] {
            let bgL = try #require(ContrastText.relativeLuminance(hex: bg))
            #expect(ContrastText.contrastRatio(text, bgL) >= ContrastText.aaThreshold, "nền \(bg)")
        }
    }

    @Test func systemOrangeWouldFailOnWhite() throws {
        // Chứng minh vì sao cần màu riêng: nếu ai đó "đơn giản hoá" về cam hệ thống thì phép đo trên là đỏ.
        let orange = try #require(ContrastText.relativeLuminance(hex: "FF9500"))
        let white = try #require(ContrastText.relativeLuminance(hex: "FFFFFF"))
        #expect(ContrastText.contrastRatio(orange, white) < ContrastText.aaThreshold)
    }
}
