import SwiftUI
import VFlowCore

/// `--render-offscreen`: thay `List` bằng `VStack` thường cho Lịch sử/Từ điển/Snippets — đã đo
/// thật: `List` (như `ScrollView`) không chụp được qua `ImageRenderer` khi cửa sổ chưa từng lên màn
/// hình (ra hình "cấm" thay vì nội dung). Dùng LẠI chính các hàng (`HistoryRow`/`DictionaryRow`/
/// `SnippetRow`) và cùng logic gom nhóm/sắp xếp với view thật — CHỈ khác container ngoài cùng.
struct HistoryOffscreenPreview: View {
    let controller: AppController
    let query: String

    var body: some View {
        let r = try? controller.listHistory(query: query.isEmpty ? nil : query)
        let entries = r?.entries ?? []
        let groups = HistoryGrouping.grouped(entries: entries, now: Date())
        VStack(alignment: .leading, spacing: 12) {
            Text("Lịch sử (\(entries.count))").font(.headline).foregroundStyle(.secondary)
            if !controller.historyEnabled {
                Label("Lịch sử đang tắt — các câu đọc chính tả mới sẽ KHÔNG được lưu.", systemImage: "clock.badge.xmark")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    controller.historyEnabled ? "Chưa có câu nào" : "Lịch sử đang tắt",
                    systemImage: controller.historyEnabled ? "text.bubble" : "clock.badge.xmark",
                    description: Text(controller.historyEnabled
                        ? "Giữ ⌥ (Option) trái ở bất kỳ đâu, nói, rồi nhả phím — câu sẽ xuất hiện ở đây."
                        : "Bật \"Lưu lịch sử\" ở Cài đặt › Lịch sử & riêng tư để xem lại các câu đã đọc chính tả.")
                )
            } else {
                ForEach(groups, id: \.label) { group in
                    Text(group.label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(group.entries) { entry in
                        HistoryRow(entry: entry, onCopy: {}, onEdit: {}, onAddToDictionary: {}, onDelete: {})
                        Divider()
                    }
                }
            }
        }
    }
}

struct DictionaryOffscreenPreview: View {
    let entries: [DictionaryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Từ điển (\(entries.count))").font(.headline).foregroundStyle(.secondary)
            if entries.isEmpty {
                ContentUnavailableView("Từ điển trống", systemImage: "book.closed",
                                       description: Text("Thêm \"deploy\" với cách nói \"đi plôi\" để vflow luôn gõ đúng thuật ngữ bạn hay dùng."))
            } else {
                ForEach(ListSorting.sorted(entries, order: .alphabetical, name: { $0.term }, uses: { $0.uses }), id: \.term) { entry in
                    DictionaryRow(entry: entry, onEdit: {}, onDelete: {})
                    Divider()
                }
            }
        }
    }
}

struct SnippetsOffscreenPreview: View {
    let entries: [SnippetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snippets (\(entries.count))").font(.headline).foregroundStyle(.secondary)
            if entries.isEmpty {
                ContentUnavailableView("Chưa có snippet nào", systemImage: "text.badge.plus",
                                       description: Text("Thêm trigger \"link lịch hẹn\" → nội dung \"https://…\" để nói một câu là chèn nguyên đoạn."))
            } else {
                ForEach(ListSorting.sorted(entries, order: .alphabetical, name: { $0.trigger }, uses: { $0.uses }), id: \.trigger) { entry in
                    SnippetRow(entry: entry, onEdit: {}, onDelete: {})
                    Divider()
                }
            }
        }
    }
}
