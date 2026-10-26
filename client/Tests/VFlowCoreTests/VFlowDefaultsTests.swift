import Foundation
import Testing
@testable import VFlowCore

@Suite struct VFlowDefaultsTests {
    @Test func noHomeUsesStandard() {
        #expect(VFlowDefaults.resolve(environment: [:]) === UserDefaults.standard)
    }

    @Test func emptyHomeUsesStandard() {
        #expect(VFlowDefaults.resolve(environment: ["VFLOW_HOME": ""]) === UserDefaults.standard)
    }

    @Test func sameHomeAlwaysGivesSameSuiteName() {
        let a = VFlowDefaults.suiteName(forHome: "/tmp/vflow-sandbox-1")
        let b = VFlowDefaults.suiteName(forHome: "/tmp/vflow-sandbox-1")
        #expect(a == b)
    }

    @Test func differentHomesGiveDifferentSuiteNames() {
        let a = VFlowDefaults.suiteName(forHome: "/tmp/vflow-sandbox-1")
        let b = VFlowDefaults.suiteName(forHome: "/tmp/vflow-sandbox-2")
        #expect(a != b)
    }

    /// Phá nhánh: nếu lớp truy cập quay lại dùng `.standard` bất chấp `VFLOW_HOME` (lỗi dễ mắc khi
    /// thêm một chỗ gọi `UserDefaults.standard` trực tiếp), hai home khác nhau sẽ THẤY khoá của
    /// nhau — test này phải đỏ nếu điều đó xảy ra.
    @Test func twoDifferentHomesDoNotSeeEachOthersKeys() {
        let home1 = "/tmp/vflow-sandbox-isolation-1-\(UUID().uuidString)"
        let home2 = "/tmp/vflow-sandbox-isolation-2-\(UUID().uuidString)"
        let d1 = VFlowDefaults.resolve(environment: ["VFLOW_HOME": home1])
        let d2 = VFlowDefaults.resolve(environment: ["VFLOW_HOME": home2])
        defer {
            d1.removePersistentDomain(forName: VFlowDefaults.suiteName(forHome: home1))
            d2.removePersistentDomain(forName: VFlowDefaults.suiteName(forHome: home2))
        }
        d1.set("clean", forKey: "mode")
        #expect(d2.string(forKey: "mode") == nil)
        #expect(d1.string(forKey: "mode") == "clean")
    }

    /// Cùng `VFLOW_HOME` ⇒ cùng suite thật (không chỉ cùng TÊN) — đọc lại ra giá trị vừa ghi.
    @Test func sameHomeSharesSameUnderlyingSuite() {
        let home = "/tmp/vflow-sandbox-reuse-\(UUID().uuidString)"
        let first = VFlowDefaults.resolve(environment: ["VFLOW_HOME": home])
        first.set(true, forKey: "hasSeenWelcome")
        let second = VFlowDefaults.resolve(environment: ["VFLOW_HOME": home])
        defer { second.removePersistentDomain(forName: VFlowDefaults.suiteName(forHome: home)) }
        #expect(second.bool(forKey: "hasSeenWelcome") == true)
    }
}
