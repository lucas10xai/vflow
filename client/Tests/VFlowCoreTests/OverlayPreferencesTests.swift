import Foundation
import Testing
@testable import VFlowCore

@Suite struct OverlayPreferencesTests {
    /// Suite riêng, xoá sau test — KHÔNG đụng UserDefaults thật của vflow.
    func isolated() -> (UserDefaults, () -> Void) {
        let name = "org.aios.vflow.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    @Test func unsetKeysGiveLegacyBottomMedium() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        #expect(OverlayPreferences.position(from: d) == .bottom)
        #expect(OverlayPreferences.size(from: d) == .medium)
    }

    @Test func savedChoiceRoundTripsForEveryValue() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        for p in OverlayPosition.allCases {
            OverlayPreferences.save(position: p, to: d)
            #expect(OverlayPreferences.position(from: d) == p)
        }
        for s in OverlaySize.allCases {
            OverlayPreferences.save(size: s, to: d)
            #expect(OverlayPreferences.size(from: d) == s)
        }
    }

    @Test func unknownStoredValueFallsBackToDefaultInsteadOfCrashingOrGuessing() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        d.set("huge", forKey: OverlayPreferences.sizeKey)
        d.set("left", forKey: OverlayPreferences.positionKey)
        #expect(OverlayPreferences.size(from: d) == .medium)
        #expect(OverlayPreferences.position(from: d) == .bottom)
    }

    @Test func positionAndSizeAreStoredIndependently() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        OverlayPreferences.save(size: .large, to: d)
        #expect(OverlayPreferences.position(from: d) == .bottom)
        OverlayPreferences.save(position: .topNearNotch, to: d)
        #expect(OverlayPreferences.size(from: d) == .large)
    }
}
