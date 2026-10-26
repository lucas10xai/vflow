import Testing
@testable import VFlowCore

@Suite struct ListSortingTests {
    @Test func alphabeticalIgnoresUsesCompletely() {
        let items = [DictionaryEntry(term: "zebra", spoken: ["z"], uses: 99), DictionaryEntry(term: "apple", spoken: ["a"], uses: 0)]
        let sorted = ListSorting.sorted(items, order: .alphabetical, name: { $0.term }, uses: { $0.uses })
        #expect(sorted.map { $0.term } == ["apple", "zebra"])
    }

    @Test func mostUsedOrdersByUsesDescending() {
        let items = [DictionaryEntry(term: "a", spoken: ["a"], uses: 1), DictionaryEntry(term: "b", spoken: ["b"], uses: 10)]
        let sorted = ListSorting.sorted(items, order: .mostUsed, name: { $0.term }, uses: { $0.uses })
        #expect(sorted.map { $0.term } == ["b", "a"])
    }

    /// Phá nhánh: hai mục CÙNG số lần dùng phải hoà về A–Z (ổn định), không phải thứ tự ngẫu
    /// nhiên/thứ tự nhập — nếu bỏ nhánh "hoà" này, kết quả có thể đổi chỗ giữa các lần tải lại.
    @Test func mostUsedTiesFallBackToAlphabetical() {
        let items = [DictionaryEntry(term: "zebra", spoken: ["z"], uses: 5), DictionaryEntry(term: "apple", spoken: ["a"], uses: 5)]
        let sorted = ListSorting.sorted(items, order: .mostUsed, name: { $0.term }, uses: { $0.uses })
        #expect(sorted.map { $0.term } == ["apple", "zebra"])
    }

    @Test func emptyListSortsToEmptyList() {
        let items: [DictionaryEntry] = []
        #expect(ListSorting.sorted(items, order: .alphabetical, name: { $0.term }, uses: { $0.uses }).isEmpty)
        #expect(ListSorting.sorted(items, order: .mostUsed, name: { $0.term }, uses: { $0.uses }).isEmpty)
    }

    @Test func worksWithSnippetEntryToo() {
        let items = [SnippetEntry(trigger: "z", text: "x", uses: 1), SnippetEntry(trigger: "a", text: "y", uses: 5)]
        let sorted = ListSorting.sorted(items, order: .mostUsed, name: { $0.trigger }, uses: { $0.uses })
        #expect(sorted.map { $0.trigger } == ["a", "z"])
    }
}
