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
    @State private var query = ""
    @State private var sort: ListSort = .alphabetical
    @State private var showEditor = false
    @State private var editorOriginalTrigger: String?
    @State private var editorTrigger = ""
    @State private var editorText = ""
    @State private var saveError: String?
    @State private var confirmDelete: SnippetEntry?

    private var visibleEntries: [SnippetEntry] {
        let filtered = query.isEmpty ? entries : entries.filter {
            $0.trigger.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
        }
        return ListSorting.sorted(filtered, order: sort.order, name: { $0.trigger }, uses: { $0.uses })
    }

    private var liveValidationError: String? {
        SnippetFormValidation.error(trigger: editorTrigger, text: editorText, existing: entries, originalTrigger: editorOriginalTrigger)
    }

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
        .searchable(text: $query, placement: .toolbar, prompt: "Tìm trigger hoặc nội dung…")
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
            Picker("Sắp xếp", selection: $sort) {
                ForEach(ListSort.allCases) { s in Text(s.title).tag(s) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Làm mới").disabled(!model.engineReady)
            Button { beginAdd() } label: { Image(systemName: "plus") }
                .help("Thêm mục…").disabled(!model.engineReady)
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
            ContentUnavailableView("Chưa có snippet nào", systemImage: "text.badge.plus",
                                   description: Text("Thêm trigger \"link lịch hẹn\" → nội dung \"https://…\" để nói một câu là chèn nguyên đoạn."))
        } else if visibleEntries.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(visibleEntries, id: \.trigger) { entry in
                    SnippetRow(entry: entry, onEdit: { beginEdit(entry) }, onDelete: { confirmDelete = entry })
                        .contextMenu {
                            Button("Sửa…") { beginEdit(entry) }
                            Button("Xoá", role: .destructive) { confirmDelete = entry }
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        switch await controller.fetchSnippets() {
        case .success(let e):
            entries = e
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
        showEditor = true
    }

    private func beginEdit(_ entry: SnippetEntry) {
        editorOriginalTrigger = entry.trigger
        editorTrigger = entry.trigger
        editorText = entry.text
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
        let entry = SnippetEntry(trigger: trigger, text: editorText)
        let change: SnippetChange = editorOriginalTrigger.map { .update(originalTrigger: $0, entry: entry) } ?? .add(entry)
        let result = await controller.applySnippetChange(change)
        switch result {
        case .success(let next):
            entries = next
            showEditor = false
        case .failure(let e):
            saveError = ErrorText.message(e)
        }
    }

    @ViewBuilder private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editorOriginalTrigger == nil ? "Thêm snippet" : "Sửa snippet")
                .font(.system(size: 15, weight: .semibold))
                .padding([.top, .horizontal], 20)
                .padding(.bottom, 8)
            Form {
                Section {
                    TextField("Trigger (vd. link lịch hẹn)", text: $editorTrigger)
                        .accessibilityLabel("Trigger")
                } header: { Text("Trigger (1–\(SnippetValidation.maxTrigger) ký tự)") }
                Section {
                    TextEditor(text: $editorText)
                        .font(.system(size: 13))
                        .frame(minHeight: 140)
                        .accessibilityLabel("Nội dung snippet")
                } header: { Text("Nội dung (1–\(SnippetValidation.maxText) ký tự, nhiều dòng)") }
                if let liveValidationError {
                    Section {
                        Label(liveValidationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Color.red)
                    }
                }
                if let saveError {
                    Section { Text(saveError).font(.system(size: 13)).foregroundStyle(Color.red) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Huỷ") { showEditor = false }
                Spacer()
                Button("Lưu") { Task { await saveEditor() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(liveValidationError != nil || editorTrigger.trimmingCharacters(in: .whitespaces).isEmpty || editorText.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 8)
        }
        .frame(minWidth: 460, minHeight: 360)
        .onAppear { saveError = nil }
    }
}

struct SnippetRow: View {
    let entry: SnippetEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.trigger).font(.system(size: 13, weight: .semibold))
                Text(entry.text).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("Dùng \(entry.uses) lần" + (entry.lastUsed.map { " · lần cuối \($0)" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sửa…", action: onEdit).buttonStyle(.plain).foregroundStyle(Theme.accent)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain).accessibilityLabel("Xoá \(entry.trigger)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
