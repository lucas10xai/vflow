import Testing
@testable import VFlowCore

@Suite struct DictionaryFormValidationTests {
    @Test func emptyTermProducesNoErrorYet() {
        #expect(DictionaryFormValidation.error(term: "", spokenLines: [], existing: [], originalTerm: nil) == nil)
    }

    @Test func emptySpokenIsReported() {
        let e = DictionaryFormValidation.error(term: "deploy", spokenLines: [], existing: [], originalTerm: nil)
        #expect(e != nil)
    }

    @Test func duplicateTermAgainstExistingEntryIsReported() {
        let existing = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let e = DictionaryFormValidation.error(term: "deploy", spokenLines: ["đi plôi 2"], existing: existing, originalTerm: nil)
        #expect(e != nil && e!.contains("trùng"))
    }

    /// Sửa chính mục đang sửa (originalTerm == term) KHÔNG được báo trùng với CHÍNH NÓ.
    @Test func editingSameEntryIsNotFlaggedAsDuplicate() {
        let existing = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let e = DictionaryFormValidation.error(term: "deploy", spokenLines: ["đi plôi mới"], existing: existing, originalTerm: "deploy")
        #expect(e == nil)
    }

    @Test func termTooLongIsReported() {
        let longTerm = String(repeating: "a", count: DictionaryValidation.maxLen + 1)
        let e = DictionaryFormValidation.error(term: longTerm, spokenLines: ["x"], existing: [], originalTerm: nil)
        #expect(e != nil)
    }

    @Test func validInputHasNoError() {
        let e = DictionaryFormValidation.error(term: "deploy", spokenLines: ["đi plôi"], existing: [], originalTerm: nil)
        #expect(e == nil)
    }
}

@Suite struct SnippetFormValidationTests {
    @Test func emptyTriggerProducesNoErrorYet() {
        #expect(SnippetFormValidation.error(trigger: "", text: "", existing: [], originalTrigger: nil) == nil)
    }

    @Test func emptyTextIsReported() {
        let e = SnippetFormValidation.error(trigger: "link lịch hẹn", text: "", existing: [], originalTrigger: nil)
        #expect(e != nil)
    }

    @Test func duplicateTriggerAfterNormalizationIsReported() {
        let existing = [SnippetEntry(trigger: "link lịch hẹn", text: "https://a")]
        let e = SnippetFormValidation.error(trigger: "Link Lich Hen", text: "https://b", existing: existing, originalTrigger: nil)
        #expect(e != nil)
    }

    @Test func editingSameEntryIsNotFlaggedAsDuplicate() {
        let existing = [SnippetEntry(trigger: "link lịch hẹn", text: "https://a")]
        let e = SnippetFormValidation.error(trigger: "link lịch hẹn", text: "https://b", existing: existing, originalTrigger: "link lịch hẹn")
        #expect(e == nil)
    }

    @Test func triggerTooLongIsReported() {
        let longTrigger = String(repeating: "a", count: SnippetValidation.maxTrigger + 1)
        let e = SnippetFormValidation.error(trigger: longTrigger, text: "x", existing: [], originalTrigger: nil)
        #expect(e != nil)
    }

    @Test func validInputHasNoError() {
        let e = SnippetFormValidation.error(trigger: "link lịch hẹn", text: "https://a", existing: [], originalTrigger: nil)
        #expect(e == nil)
    }
}
