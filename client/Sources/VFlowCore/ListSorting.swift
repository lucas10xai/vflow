import Foundation

/// Hai cách sắp xếp dùng CHUNG cho Từ điển/Snippets (U2 mục C) — hàm thuần, test được không cần
/// SwiftUI.
public enum ListSortOrder: Sendable {
    case alphabetical
    /// Số lần dùng giảm dần; hoà thì theo A–Z để thứ tự ổn định giữa các lần tải lại.
    case mostUsed
}

public enum ListSorting {
    public static func sorted<T>(_ items: [T], order: ListSortOrder, name: (T) -> String, uses: (T) -> Int) -> [T] {
        switch order {
        case .alphabetical:
            return items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        case .mostUsed:
            return items.sorted { a, b in
                let ua = uses(a), ub = uses(b)
                if ua != ub { return ua > ub }
                return name(a).localizedStandardCompare(name(b)) == .orderedAscending
            }
        }
    }
}
