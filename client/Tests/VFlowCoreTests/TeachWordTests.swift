import Testing
@testable import VFlowCore

@Suite struct TeachWordVariantsTests {
    @Test func normalizeFoldsCaseAndCollapsesSpaces() {
        #expect(TeachWordVariants.normalize("  Đi   Plôi  ") == "đi plôi")
    }

    @Test func normalizeTreatsNFCAndNFDAsEqual() {
        // "tiếng" dựng bằng tổ hợp dấu rời (NFD) phải chuẩn hoá về CÙNG khoá với dạng dựng sẵn (NFC).
        let nfc = "tiếng việt".precomposedStringWithCanonicalMapping
        let nfd = "tiếng việt".decomposedStringWithCanonicalMapping
        // Khác nhau ở MỨC SCALAR Unicode (NFD tách dấu ra khỏi chữ cái) — dù Swift `String ==` (so
        // khớp theo cụm grapheme đã chuẩn hoá) đã coi hai dạng này BẰNG NHAU, nên bài kiểm tra này
        // xác nhận hai đầu vào thật sự khác biểu diễn, không phải hai chuỗi giống hệt từ đầu.
        #expect(nfc.unicodeScalars.count != nfd.unicodeScalars.count)
        #expect(TeachWordVariants.normalize(nfc) == TeachWordVariants.normalize(nfd))
    }

    @Test func candidatesDedupsAcrossNFCAndNFD() {
        let nfc = "tiếng việt".precomposedStringWithCanonicalMapping
        let nfd = "tiếng việt".decomposedStringWithCanonicalMapping
        let result = TeachWordVariants.candidates(from: [nfc, nfd], correctTerm: "Vietnamese")
        #expect(result.count == 1)
    }

    @Test func candidatesDedupsAcrossCaseAndNFDTogether() {
        // Kết hợp khác cả hoa/thường VÀ dạng Unicode (NFD) trong cùng một cặp — vẫn phải gộp thành một.
        let upperNFD = "TIẾNG VIỆT".decomposedStringWithCanonicalMapping
        let lowerNFC = "tiếng việt".precomposedStringWithCanonicalMapping
        let result = TeachWordVariants.candidates(from: [upperNFD, lowerNFC], correctTerm: "x")
        #expect(result.count == 1)
    }

    @Test func candidatesDropsEmptyAfterTrimming() {
        let result = TeachWordVariants.candidates(from: ["   ", "", "đi plôi"], correctTerm: "deploy")
        #expect(result == ["đi plôi"])
    }

    @Test func candidatesDropsTooLong() {
        let tooLong = String(repeating: "a", count: DictionaryValidation.maxLen + 1)
        let result = TeachWordVariants.candidates(from: [tooLong, "ok"], correctTerm: "x")
        #expect(result == ["ok"])
    }

    @Test func candidatesDropsVariantEqualToCorrectTermIgnoringCase() {
        let result = TeachWordVariants.candidates(from: ["Deploy", "đi plôi"], correctTerm: "deploy")
        #expect(result == ["đi plôi"])
    }

    @Test func candidatesPreservesFirstOccurrenceCasing() {
        let result = TeachWordVariants.candidates(from: ["Đi Plôi", "đi plôi", "đì plôi"], correctTerm: "deploy")
        #expect(result == ["Đi Plôi", "đì plôi"])
    }

    @Test func candidatesKeepCaseSensitiveButDedupCaseInsensitive() {
        // Hai lần nghe khác NHAU về viết hoa/thường chỉ nên tính là MỘT cách nói (gộp theo chuẩn hoá).
        let result = TeachWordVariants.candidates(from: ["ABC", "abc"], correctTerm: "xyz")
        #expect(result.count == 1)
    }

    @Test func applyCreatesNewEntryWhenTermAbsent() {
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi", "đì plôi"], to: [])
        guard case .success(let entries) = result else { #expect(Bool(false)); return }
        #expect(entries.count == 1)
        #expect(entries[0].term == "deploy")
        #expect(entries[0].spoken == ["đi plôi", "đì plôi"])
    }

    @Test func applyMergesIntoExistingEntryWithoutDuplicates() {
        let existing = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi", "đì plôi"], to: existing)
        guard case .success(let entries) = result else { #expect(Bool(false)); return }
        #expect(entries.count == 1)
        #expect(entries[0].spoken == ["đi plôi", "đì plôi"])
    }

    /// Mục đã đủ 20 cách nói mà người dùng chọn thêm cách nói mới ⇒ LỖI rõ ràng, danh sách từ điển
    /// gốc không bị đụng — không được "lưu thành công" mà âm thầm bỏ cách nói vừa chọn.
    @Test func applyFailsInsteadOfSilentlyDroppingWhenEntryAlreadyFull() {
        let full = (0..<DictionaryValidation.maxSpoken).map { "cách nói \($0)" }
        let existing = [DictionaryEntry(term: "deploy", spoken: full)]
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi"], to: existing)
        guard case .failure(let e) = result else { Issue.record("phải lỗi khi mục đã đầy"); return }
        #expect(e.message.contains("\(DictionaryValidation.maxSpoken)"))
        #expect(existing[0].spoken == full)
    }

    @Test func applyMergesIntoExistingEntryIgnoringCaseAndUnicodeForm() {
        let existing = [DictionaryEntry(term: "Supabase", spoken: ["xu pa bết"])]
        let nfd = "XU PA BẾT".decomposedStringWithCanonicalMapping
        let result = TeachWordVariants.apply(term: "supabase", selectedVariants: [nfd, "xu pa bây"], to: existing)
        guard case .success(let entries) = result else { Issue.record("phải gộp được"); return }
        #expect(entries.count == 1, "không được tạo mục thứ hai chỉ vì khác hoa/thường")
        #expect(entries[0].term == "Supabase")
        #expect(entries[0].spoken == ["xu pa bết", "xu pa bây"])
    }

    @Test func applyingSameLessonTwiceDoesNotDuplicateAnything() {
        let first = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi", "đì ploi"], to: [])
        guard case .success(let afterFirst) = first,
              case .success(let afterSecond) = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi", "đì ploi"], to: afterFirst)
        else { Issue.record("cả hai lần phải thành công"); return }
        #expect(afterSecond == afterFirst)
    }

    @Test func applyToNewEntryDedupesRepeatedVariants() {
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: ["Đi plôi", "đi plôi"], to: [])
        guard case .success(let entries) = result else { Issue.record("phải thành công"); return }
        #expect(entries[0].spoken == ["Đi plôi"])
    }

    @Test func applyKeepsUnrelatedEntriesUntouched() {
        let other = DictionaryEntry(term: "Orca", spoken: ["oóc ca"], uses: 7)
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: ["đi plôi"], to: [other])
        guard case .success(let entries) = result else { Issue.record("phải thành công"); return }
        #expect(entries.count == 2)
        #expect(entries[0] == other)
    }

    // MARK: ô "Từ đúng", chữ nghe ra, chọn/bỏ chọn

    @Test func termErrorMirrorsAddSheetRules() {
        #expect(TeachWordVariants.termError("deploy") == nil)
        #expect(TeachWordVariants.termError("   ") != nil)
        #expect(TeachWordVariants.termError(String(repeating: "a", count: DictionaryValidation.maxLen + 1)) != nil)
        #expect(TeachWordVariants.termError(String(repeating: "a", count: DictionaryValidation.maxLen)) == nil)
    }

    @Test func acceptHeardRejectsSilenceAndSymbolOnlyText() {
        #expect(TeachWordVariants.acceptHeard("") == nil)
        #expect(TeachWordVariants.acceptHeard("  \n ") == nil)
        #expect(TeachWordVariants.acceptHeard("...") == nil)
        #expect(TeachWordVariants.acceptHeard("  đi plôi \n") == "đi plôi")
    }

    /// Cách nói chỉ có ký hiệu bị `DictionaryValidation` từ chối ⇒ nếu lọt vào ứng viên thì MỘT dòng
    /// "..." làm hỏng cả lần Lưu. Phải bị lọc ngay ở bước gom.
    @Test func candidatesDropSymbolOnlyHeard() {
        let result = TeachWordVariants.candidates(from: ["...", "đi plôi", "?!"], correctTerm: "deploy")
        #expect(result == ["đi plôi"])
        let saved = TeachWordVariants.apply(term: "deploy", selectedVariants: result, to: [])
        if case .failure = saved { Issue.record("ứng viên đã lọc phải lưu được") }
    }

    @Test func deselectedVariantStaysDeselectedWhenMoreHeardLinesArrive() {
        // Người dùng bỏ chọn "đì ploi"; lần nói thứ ba thêm "đi bờ lôi" — "đì ploi" KHÔNG được tự chọn lại.
        let deselected: Set<String> = [TeachWordVariants.normalize("đì ploi")]
        let afterTwo = TeachWordVariants.candidates(from: ["đi plôi", "đì ploi"], correctTerm: "deploy")
        #expect(TeachWordVariants.selected(candidates: afterTwo, deselected: deselected) == ["đi plôi"])
        let afterThree = TeachWordVariants.candidates(from: ["đi plôi", "đì ploi", "đi bờ lôi"], correctTerm: "deploy")
        #expect(TeachWordVariants.selected(candidates: afterThree, deselected: deselected) == ["đi plôi", "đi bờ lôi"])
    }

    @Test func applyRejectsEmptyTerm() {
        let result = TeachWordVariants.apply(term: "   ", selectedVariants: ["a"], to: [])
        #expect(throwsEmpty(result))
    }

    @Test func applyRejectsNoSelectedVariants() {
        let result = TeachWordVariants.apply(term: "deploy", selectedVariants: [], to: [])
        #expect(throwsEmpty(result))
    }

    @Test func deselectingByDifferentCaseOrUnicodeFormStillMatches() {
        let candidates = ["Đi Plôi"]
        let key = TeachWordVariants.normalize("đi plôi".decomposedStringWithCanonicalMapping)
        #expect(TeachWordVariants.selected(candidates: candidates, deselected: [key]).isEmpty)
    }


    private func throwsEmpty(_ r: Result<[DictionaryEntry], DictionaryValidationError>) -> Bool {
        if case .failure = r { return true }
        return false
    }
}
