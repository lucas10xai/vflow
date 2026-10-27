import Testing
@testable import VFlowCore

@Suite struct PasteTargetPolicyTests {
    private let own = "org.aios.vflow"
    private let terminal = "com.apple.Terminal"

    private func decide(target: String?, frontmost: String?) -> String? {
        PasteTargetPolicy.bundleIdToReactivate(target: target, frontmost: frontmost, ownBundleId: own)
    }

    /// vflow chiếm focus trong lúc dịch (người dùng bấm vào cửa sổ vflow) ⇒ ⌘V sẽ rơi vào vflow:
    /// phải đưa app đích về trước.
    @Test func reactivatesTargetWhenVFlowItselfIsFrontmost() {
        #expect(decide(target: terminal, frontmost: own) == terminal)
    }

    @Test func reactivatesTargetWhenNoAppIsFrontmost() {
        #expect(decide(target: terminal, frontmost: nil) == terminal)
    }

    @Test func leavesFocusAloneWhenTargetStillFrontmost() {
        #expect(decide(target: terminal, frontmost: terminal) == nil)
    }

    /// Người dùng chủ động chuyển sang app khác ⇒ tôn trọng, không giật focus về app cũ.
    @Test func doesNotYankFocusBackFromAnotherApp() {
        #expect(decide(target: terminal, frontmost: "com.apple.Safari") == nil)
    }

    @Test func neverTriesToActivateVFlowOrAnUnknownTarget() {
        #expect(decide(target: nil, frontmost: own) == nil)
        #expect(decide(target: "", frontmost: own) == nil)
        #expect(decide(target: own, frontmost: nil) == nil)
    }
}
