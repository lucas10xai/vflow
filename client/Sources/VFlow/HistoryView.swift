import AppKit
import SwiftUI
import VFlowCore

/// Tab "Lịch sử": các câu đã đọc chính tả, gom theo ngày (Hôm nay/Hôm qua/ngày — xem
/// `VFlowCore.HistoryGrouping`), chỉ văn bản — không có âm thanh. Tìm kiếm (thanh công cụ), menu
/// chuột phải (Sao chép, Sửa…, Thêm vào từ điển, Xoá), ⌘C cho mục đang chọn, trạng thái rỗng bằng
/// `ContentUnavailableView`. Giữ NGUYÊN luồng Sửa → gợi ý từ điển, chỉ lưu văn bản.
struct HistoryView: View {
    let controller: AppController
    @State private var entries: [HistoryEntry] = []
    @State private var corruptCount = 0
    @State private var query = ""
    @State private var loadError: String?
    @State private var confirmClearAll = false
    @State private var editingEntry: HistoryEntry?
    @State private var editedText = ""
    @State private var suggestions: [CorrectionSuggestion] = []
    @State private var suggestionsLoaded = false
    @State private var correctionError: String?
    @State private var acceptedTerms: Set<String> = []
    @State private var selection: String?
    @State private var addDictionaryFor: HistoryEntry?

    private var groups: [HistoryGrouping.DayGroup] {
        HistoryGrouping.grouped(entries: entries, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            status
            list
        }
        .onAppear { load() }
        .onChange(of: query) { _, _ in load() }
        .searchable(text: $query, placement: .toolbar, prompt: "Tìm trong lịch sử…")
        .sheet(item: $editingEntry, onDismiss: {
            suggestions = []; suggestionsLoaded = false; correctionError = nil; acceptedTerms = []
        }) { entry in
            editSheet(for: entry)
        }
        .sheet(item: $addDictionaryFor) { entry in
            AddToDictionarySheet(controller: controller, prefill: entry.text) { addDictionaryFor = nil }
        }
        .alert("Xoá toàn bộ lịch sử?", isPresented: $confirmClearAll) {
            Button("Xoá", role: .destructive) { clearAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không thể hoàn tác. Chỉ xoá văn bản đã lưu trên máy này.")
        }
    }

    private var header: some View {
        HStack {
            SectionTitle(text: "Lịch sử (\(entries.count))")
            Spacer()
            Button("Làm mới") { load() }
            Button("Xoá toàn bộ lịch sử…") { confirmClearAll = true }.disabled(entries.isEmpty)
        }
    }

    @ViewBuilder private var status: some View {
        if let e = loadError {
            Text(e).font(.system(size: 13)).foregroundStyle(Color.red)
        } else if corruptCount > 0 {
            Text("Bỏ qua \(corruptCount) dòng lịch sử hỏng.")
                .font(.system(size: 12)).foregroundStyle(.orange)
        }
        if !controller.historyEnabled {
            Label("Lịch sử đang tắt — các câu đọc chính tả mới sẽ KHÔNG được lưu.", systemImage: "clock.badge.xmark")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var list: some View {
        if entries.isEmpty && loadError == nil {
            if !controller.historyEnabled && query.isEmpty {
                ContentUnavailableView("Lịch sử đang tắt", systemImage: "clock.badge.xmark",
                                       description: Text("Bật \"Lưu lịch sử\" ở Cài đặt › Lịch sử & riêng tư để xem lại các câu đã đọc chính tả."))
            } else if query.isEmpty {
                ContentUnavailableView("Chưa có câu nào", systemImage: "text.bubble",
                                       description: Text("Giữ ⌥ (Option) trái ở bất kỳ đâu, nói, rồi nhả phím — câu sẽ xuất hiện ở đây."))
            } else {
                ContentUnavailableView.search(text: query)
            }
        } else {
            List(selection: $selection) {
                ForEach(groups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.entries) { entry in
                            HistoryRow(entry: entry, onCopy: { copy(entry.text) }, onEdit: { beginEdit(entry) },
                                      onAddToDictionary: { addDictionaryFor = entry }, onDelete: { delete(entry) })
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Sao chép") { copy(entry.text) }
                                    Button("Sửa…") { beginEdit(entry) }
                                    Button("Thêm vào từ điển…") { addDictionaryFor = entry }
                                    Divider()
                                    Button("Xoá", role: .destructive) { delete(entry) }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .background(copyShortcut)
        }
    }

    /// ⌘C cho mục đang chọn — nút ẩn mang phím tắt (giống mẫu ⌘1…⌘4 ở `MainWindowView`), vì
    /// `List` không tự cho ⌘C sao chép NỘI DUNG câu (chỉ sao chép được hàng UI nếu có).
    private var copyShortcut: some View {
        Button("") {
            guard let id = selection, let e = entries.first(where: { $0.id == id }) else { return }
            copy(e.text)
        }
        .keyboardShortcut("c", modifiers: .command)
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func load() {
        do {
            let r = try controller.listHistory(query: query.isEmpty ? nil : query)
            entries = r.entries
            corruptCount = r.corruptLines
            loadError = nil
        } catch {
            loadError = "Không đọc được lịch sử: \(error.localizedDescription)"
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func delete(_ entry: HistoryEntry) {
        do { try controller.deleteHistory(id: entry.id); load() }
        catch { loadError = "Không xoá được mục này: \(error.localizedDescription)" }
    }

    private func clearAll() {
        do { try controller.clearHistory(); load() }
        catch { loadError = "Không xoá được lịch sử: \(error.localizedDescription)" }
    }

    private func beginEdit(_ entry: HistoryEntry) {
        editedText = entry.text
        editingEntry = entry
    }

    @ViewBuilder private func editSheet(for entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sửa văn bản cuối").font(.system(size: 15, weight: .semibold))
            TextEditor(text: $editedText)
                .font(.system(size: 13))
                .frame(minWidth: 420, minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("Văn bản đã sửa")
            HStack {
                Button("Huỷ") { editingEntry = nil }
                Spacer()
                Button("Lưu") { Task { await saveCorrection(entry) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editedText == entry.text)
            }
            if suggestionsLoaded {
                Divider()
                suggestionsBody
            }
            if let e = correctionError {
                Text(e).font(.system(size: 13)).foregroundStyle(Color.red)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    @ViewBuilder private var suggestionsBody: some View {
        if suggestions.isEmpty {
            Text("Không có gợi ý.").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            Text("Gợi ý thêm vào từ điển:").font(.system(size: 13, weight: .semibold))
            ForEach(suggestions, id: \.term) { s in
                HStack {
                    Text("Thêm “\(s.term)” ← “\(s.spoken.joined(separator: ", "))”?").font(.system(size: 13))
                    Spacer()
                    if acceptedTerms.contains(s.term) {
                        Label("Đã thêm", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.system(size: 13))
                    } else {
                        Button("Thêm") { Task { await accept(s) } }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// `POST /v1/corrections`: chỉ gợi ý, KHÔNG tự ghi vào từ điển và KHÔNG dán lại văn bản đã
    /// sửa vào ứng dụng nào — chỉ người dùng bấm "Thêm" ở từng gợi ý mới ghi.
    private func saveCorrection(_ entry: HistoryEntry) async {
        correctionError = nil
        let result = await controller.fetchCorrectionSuggestions(before: entry.text, after: editedText)
        switch result {
        case .success(let s):
            suggestions = s
            suggestionsLoaded = true
        case .failure(let e):
            correctionError = ErrorText.message(e)
            suggestionsLoaded = true
            suggestions = []
        }
    }

    private func accept(_ s: CorrectionSuggestion) async {
        let result = await controller.acceptSuggestion(s)
        switch result {
        case .success: acceptedTerms.insert(s.term)
        case .failure(let e): correctionError = ErrorText.message(e)
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onAddToDictionary: () -> Void
    let onDelete: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleId: entry.appBundleId).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(Self.timeFormatter.string(from: entry.at)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(AppDisplayName.resolve(bundleId: entry.appBundleId)).font(.system(size: 12)).foregroundStyle(.secondary)
                    ModeChip(mode: entry.mode)
                    Spacer()
                    Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).accessibilityLabel("Sao chép")
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.plain).accessibilityLabel("Xoá mục này")
                }
                Text(entry.text).font(.system(size: 13)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ModeChip: View {
    let mode: String
    var body: some View {
        Text(mode)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// Biểu tượng ứng dụng đích thật (`NSWorkspace.icon(forFile:)` theo bundle id) — dự phòng biểu
/// tượng chung khi không rõ bundle id hoặc không tìm được app đã cài (vd. app đã bị xoá).
private struct AppIconView: View {
    let bundleId: String?

    var body: some View {
        if let icon = AppIconResolver.icon(forBundleId: bundleId) {
            Image(nsImage: icon).resizable().accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

enum AppIconResolver {
    static func icon(forBundleId bundleId: String?) -> NSImage? {
        guard let bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum AppDisplayName {
    static func resolve(bundleId: String?) -> String {
        guard let bundleId else { return "?" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Sheet thêm nhanh vào từ điển từ menu chuột phải "Thêm vào từ điển…" ở Lịch sử — tiền điền
/// "cách nói" bằng nội dung đã chọn, người dùng chỉ cần gõ TÊN THUẬT NGỮ đúng. Dùng CHUNG kiểm hợp
/// lệ với `DictionaryView` (`DictionaryValidation`/`controller.applyDictionaryChange`), không có
/// logic đọc-sửa-ghi riêng.
private struct AddToDictionarySheet: View {
    let controller: AppController
    let prefill: String
    let onDone: () -> Void

    @State private var term = ""
    @State private var spoken: String
    @State private var error: String?

    init(controller: AppController, prefill: String, onDone: @escaping () -> Void) {
        self.controller = controller
        self.prefill = prefill
        self.onDone = onDone
        _spoken = State(initialValue: prefill)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thêm vào từ điển").font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Thuật ngữ").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("vd. deploy", text: $term).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Cách nói (mỗi dòng một cách)").font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $spoken)
                    .font(.system(size: 13))
                    .frame(minWidth: 380, minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(Color.red)
            }
            HStack {
                Button("Huỷ") { onDone() }
                Spacer()
                Button("Lưu") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }

    private func save() async {
        let spokenList = spoken.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let t = term.trimmingCharacters(in: .whitespaces)
        let entry = DictionaryEntry(term: t, spoken: spokenList)
        switch await controller.applyDictionaryChange(.add(entry)) {
        case .success: onDone()
        case .failure(let e): error = ErrorText.message(e)
        }
    }
}
