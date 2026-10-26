import SwiftUI
import VFlowCore

/// Tab "Từ điển": `GET/PUT /v1/dictionary` kiểu đọc-sửa-ghi (đọc lại ngay trước khi ghi, xem
/// `DictionaryOrchestration`). Kiểm hợp lệ phía client giống luật engine trước khi gửi; lỗi
/// `bad_request` của engine hiện nguyên văn (đã là tiếng Việt theo contract), không nuốt.
struct DictionaryView: View {
    let model: StatusModel
    let controller: AppController
    @State private var entries: [DictionaryEntry] = []
    @State private var loadError: ClientError?
    @State private var loaded = false
    @State private var showEditor = false
    @State private var editorOriginalTerm: String?
    @State private var editorTerm = ""
    @State private var editorSpokenText = ""
    @State private var editorError: String?
    @State private var confirmDelete: DictionaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            body_
        }
        // id = model.engineReady: engine CHƯA sẵn sàng (đang khởi động/khởi động lại) thì không
        // gọi API (tránh lỗi giả); vừa chuyển sang sẵn sàng ⇒ task này được huỷ và chạy lại ⇒ tự
        // tải lại. Không bao giờ tải trong lúc đang chờ.
        .task(id: model.engineReady) {
            guard model.engineReady else { return }
            await load()
        }
        .sheet(isPresented: $showEditor) { editorSheet }
        .confirmationDialog(
            "Xoá mục \"\(confirmDelete?.term ?? "")\"?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) { if let e = confirmDelete { Task { await remove(e) } } }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            SectionTitle(text: "Từ điển (\(entries.count))")
            Spacer()
            Button("Làm mới") { Task { await load() } }.disabled(!model.engineReady)
            Button("Thêm mục…") { beginAdd() }.disabled(!model.engineReady)
        }
    }

    @ViewBuilder private var body_: some View {
        if model.engineBlocked {
            // Lỗi thật (cấu hình lỗi, hoặc engine đã bỏ cuộc) — hiện rõ + nút thử lại, không bao
            // giờ hiện "đang chờ" vô thời hạn khi engine sẽ không bao giờ tự lên.
            VStack(alignment: .leading, spacing: 8) {
                Text(model.engineSummary).font(.system(size: 13)).foregroundStyle(Color.red)
                HStack(spacing: 10) {
                    Button("Thử lại") { Task { await load() } }
                    if model.engineHasFailed {
                        Button("Khởi động lại engine") { controller.restartEngine() }
                    }
                }
            }
        } else if !model.engineReady {
            // Engine đang khởi động/khởi động lại — trạng thái trung thực, KHÔNG phải lỗi; tự tải
            // lại khi engine chuyển sang sẵn sàng (xem `.task(id: model.engineReady)` ở trên).
            Text("Đang chờ engine khởi động…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if let e = loadError {
            // Engine đã sẵn sàng nhưng lần gọi vẫn lỗi (token hỏng, engine từ chối…) ⇒ lỗi thật.
            VStack(alignment: .leading, spacing: 8) {
                Text(ErrorText.message(e)).font(.system(size: 13)).foregroundStyle(Color.red)
                Button("Thử lại") { Task { await load() } }
            }
        } else if !loaded {
            Text("Đang tải…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if entries.isEmpty {
            Text("Từ điển trống.").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries, id: \.term) { entry in
                    DictionaryRow(entry: entry, onEdit: { beginEdit(entry) }, onDelete: { confirmDelete = entry })
                    Divider()
                }
            }
        }
    }

    private func load() async {
        switch await controller.fetchDictionary() {
        case .success(let e):
            entries = e.sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
            loadError = nil
        case .failure(let e):
            loadError = e
        }
        loaded = true
    }

    private func beginAdd() {
        editorOriginalTerm = nil
        editorTerm = ""
        editorSpokenText = ""
        editorError = nil
        showEditor = true
    }

    private func beginEdit(_ entry: DictionaryEntry) {
        editorOriginalTerm = entry.term
        editorTerm = entry.term
        editorSpokenText = entry.spoken.joined(separator: "\n")
        editorError = nil
        showEditor = true
    }

    private func remove(_ entry: DictionaryEntry) async {
        switch await controller.applyDictionaryChange(.remove(term: entry.term)) {
        case .success(let next): entries = next
        case .failure(let e): loadError = e
        }
    }

    private func saveEditor() async {
        let spoken = editorSpokenText.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let term = editorTerm.trimmingCharacters(in: .whitespaces)
        if term.isEmpty { editorError = "Tên thuật ngữ không được để trống."; return }
        if spoken.isEmpty { editorError = "Cần ít nhất một cách nói."; return }
        let entry = DictionaryEntry(term: term, spoken: spoken)
        let change: DictionaryChange = editorOriginalTerm.map { .update(originalTerm: $0, entry: entry) } ?? .add(entry)
        let result = await controller.applyDictionaryChange(change)
        switch result {
        case .success(let next):
            entries = next.sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
            showEditor = false
        case .failure(let e):
            editorError = ErrorText.message(e)
        }
    }

    @ViewBuilder private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editorOriginalTerm == nil ? "Thêm mục từ điển" : "Sửa mục từ điển")
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Thuật ngữ").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("vd. deploy", text: $editorTerm).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tên thuật ngữ")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Cách nói (mỗi dòng một cách, 1–\(DictionaryValidation.maxSpoken))").font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $editorSpokenText)
                    .font(.system(size: 13))
                    .frame(minWidth: 380, minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .accessibilityLabel("Danh sách cách nói, mỗi dòng một cách")
            }
            if let e = editorError {
                Text(e).font(.system(size: 13)).foregroundStyle(Color.red)
            }
            HStack {
                Button("Huỷ") { showEditor = false }
                Spacer()
                Button("Lưu") { Task { await saveEditor() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.term).font(.system(size: 13, weight: .semibold))
                Text(entry.spoken.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Dùng \(entry.uses) lần" + (entry.lastUsed.map { " · lần cuối \($0)" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sửa…", action: onEdit)
            Button(action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("Xoá \(entry.term)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
