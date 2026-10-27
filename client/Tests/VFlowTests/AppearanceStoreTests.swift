import AppKit
import Foundation
import Testing
@testable import VFlow
@testable import VFlowCore

/// `apply` là closure thử nghiệm — KHÔNG đụng `NSApp.appearance` thật của tiến trình test.
@MainActor
@Suite struct AppearanceStoreTests {
    final class Applied { var calls: [NSAppearance.Name?] = [] }

    func makeStore(defaults: UserDefaults, arguments: [String] = [], applied: Applied) -> AppearanceStore {
        AppearanceStore(defaults: defaults, arguments: arguments) { applied.calls.append($0?.name) }
    }

    func isolated() -> (UserDefaults, () -> Void) {
        let name = "org.aios.vflow.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    @Test func defaultIsSystemAndLaunchAppliesNoForcedAppearance() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        let applied = Applied()
        let store = makeStore(defaults: d, applied: applied)
        #expect(store.preference == .system)
        store.applyAtLaunch()
        #expect(applied.calls == [nil]) // nil = theo hệ thống
    }

    @Test func choosingAppearanceAppliesImmediatelyAndPersists() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        let applied = Applied()
        let store = makeStore(defaults: d, applied: applied)
        store.set(.dark)
        #expect(applied.calls == [.darkAqua])
        #expect(AppearancePreference.load(from: d) == .dark)
        store.set(.light)
        #expect(applied.calls == [.darkAqua, .aqua])
        store.set(.system)
        #expect(applied.calls.last! == nil)
    }

    @Test func nextLaunchRestoresSavedChoice() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        makeStore(defaults: d, applied: Applied()).set(.dark)
        let applied = Applied()
        let relaunched = makeStore(defaults: d, applied: applied)
        #expect(relaunched.preference == .dark)
        relaunched.applyAtLaunch()
        #expect(applied.calls == [.darkAqua])
    }

    /// Công cụ chụp ảnh ép `--appearance dark`; giá trị lưu ("Hệ thống" mặc định) không được xoá nó.
    @Test func commandLineAppearanceFlagWinsOverSavedValueAtLaunchOnly() {
        let (d, cleanup) = isolated(); defer { cleanup() }
        let applied = Applied()
        let store = makeStore(defaults: d, arguments: ["VFlow", "--appearance", "dark"], applied: applied)
        store.applyAtLaunch()
        #expect(applied.calls.isEmpty)
        store.set(.light) // người dùng chủ động chọn thì vẫn được áp dụng
        #expect(applied.calls == [.aqua])
    }
}
