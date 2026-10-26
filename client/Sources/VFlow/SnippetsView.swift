import SwiftUI
import VFlowCore

/// Tab "Snippets": `GET/PUT /v1/snippets` kiểu đọc-sửa-ghi (giống `DictionaryView`/`SnippetOrchestration`).
/// Nói đúng cả câu bằng trigger, hoặc "chèn <trigger>" trong câu, để chèn nội dung đã lưu.
struct SnippetsView: View {
    let model: StatusModel
    let controller: AppController
    @State private var entries: [SnippetEntry] = []
    @State private var loadError: ClientError?
    @State private var loaded = false
    @State private var showEditor = false
    @State private var editorOriginalTrigger: String?
    @State private var editorTrigger = ""
    @State private var editorText = ""
    @State private var editorError: String?
    @State private var confirmDelete: SnippetEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("Nói đúng cả câu bằng trigger, hoặc \"chèn <trigger>\" trong câu, để chèn nội dung đã lưu.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            body_
        }
        .task(id: model.engineReady) {
            guard model.engineReady else { return }
            await load()
        }
        .sheet(isPresented: $showEditor) { editorSheet }
        .confirmationDialog(
            "Xoá snippet \"\(confirmDelete?.trigger ?? "")\"?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) { if let e = confirmDelete { Task { await remove(e) } } }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            SectionTitle(text: "Snippets (\(entries.count))")
            Spacer()
            Button("Làm mới") { Task { await load() } }.disabled(!model.engineReady)
            Button("Thêm mục…") { beginAdd() }.disabled(!model.engineReady)
        }
    }

    @ViewBuilder private var body_: some View {
        if model.engineBlocked {
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
            Text("Đang chờ engine khởi động…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if let e = loadError {
            VStack(alignment: .leading, spacing: 8) {
                Text(ErrorText.message(e)).font(.system(size: 13)).foregroundStyle(Color.red)
                Button("Thử lại") { Task { await load() } }
            }
        } else if !loaded {
            Text("Đang tải…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if entries.isEmpty {
            Text("Chưa có snippet nào.").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries, id: \.trigger) { entry in
                    SnippetRow(entry: entry, onEdit: { beginEdit(entry) }, onDelete: { confirmDelete = entry })
                    Divider()
                }
            }
        }
    }

    private func load() async {
        switch await controller.fetchSnippets() {
        case .success(let e):
            entries = e.sorted { $0.trigger.localizedStandardCompare($1.trigger) == .orderedAscending }
            loadError = nil
        case .failure(let e):
            loadError = e
        }
        loaded = true
    }

    private func beginAdd() {
        editorOriginalTrigger = nil
        editorTrigger = ""
        editorText = ""
        editorError = nil
        showEditor = true
    }

    private func beginEdit(_ entry: SnippetEntry) {
        editorOriginalTrigger = entry.trigger
        editorTrigger = entry.trigger
        editorText = entry.text
        editorError = nil
        showEditor = true
    }

    private func remove(_ entry: SnippetEntry) async {
        switch await controller.applySnippetChange(.remove(trigger: entry.trigger)) {
        case .success(let next): entries = next
        case .failure(let e): loadError = e
        }
    }

    private func saveEditor() async {
        let trigger = editorTrigger.trimmingCharacters(in: .whitespaces)
        if trigger.isEmpty { editorError = "Trigger không được để trống."; return }
        if editorText.isEmpty { editorError = "Nội dung không được để trống."; return }
        let entry = SnippetEntry(trigger: trigger, text: editorText)
        let change: SnippetChange = editorOriginalTrigger.map { .update(originalTrigger: $0, entry: entry) } ?? .add(entry)
        let result = await controller.applySnippetChange(change)
        switch result {
        case .success(let next):
            entries = next.sorted { $0.trigger.localizedStandardCompare($1.trigger) == .orderedAscending }
            showEditor = false
        case .failure(let e):
            editorError = ErrorText.message(e)
        }
    }

    @ViewBuilder private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editorOriginalTrigger == nil ? "Thêm snippet" : "Sửa snippet")
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger (1–\(SnippetValidation.maxTrigger) ký tự)").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("vd. link lịch hẹn", text: $editorTrigger).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Trigger")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Nội dung (1–\(SnippetValidation.maxText) ký tự, nhiều dòng)").font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $editorText)
                    .font(.system(size: 13))
                    .frame(minWidth: 380, minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .accessibilityLabel("Nội dung snippet")
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

private struct SnippetRow: View {
    let entry: SnippetEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trigger).font(.system(size: 13, weight: .semibold))
                Text(preview(entry.text)).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Dùng \(entry.uses) lần" + (entry.lastUsed.map { " · lần cuối \($0)" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sửa…", action: onEdit)
            Button(action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("Xoá \(entry.trigger)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func preview(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 80 ? String(singleLine.prefix(79)) + "…" : singleLine
    }
}
