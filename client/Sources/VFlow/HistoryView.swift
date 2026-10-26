import AppKit
import SwiftUI
import VFlowCore

/// Tab "Lịch sử": các câu đã đọc chính tả (mới nhất trên cùng), chỉ văn bản — không có âm thanh.
/// Tìm kiếm, Sao chép, "Sửa…" (⇒ gợi ý thêm từ điển), xoá một mục, xoá toàn bộ (có xác nhận).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextField("Tìm trong lịch sử…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .onChange(of: query) { _, _ in load() }
            status
            list
        }
        .onAppear { load() }
        .sheet(item: $editingEntry, onDismiss: {
            suggestions = []; suggestionsLoaded = false; correctionError = nil; acceptedTerms = []
        }) { entry in
            editSheet(for: entry)
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
    }

    @ViewBuilder private var list: some View {
        if entries.isEmpty && loadError == nil {
            Text(query.isEmpty ? "Chưa có câu nào trong lịch sử." : "Không tìm thấy câu phù hợp.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry, onCopy: { copy(entry.text) },
                              onEdit: { beginEdit(entry) }, onDelete: { delete(entry) })
                    Divider()
                }
            }
        }
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

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.timeFormatter.string(from: entry.at)).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(entry.appBundleId ?? "?").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(entry.mode).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(entry.model).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Sao chép")
                Button("Sửa…", action: onEdit)
                Button(action: onDelete) { Image(systemName: "trash") }
                    .accessibilityLabel("Xoá mục này")
            }
            Text(entry.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
