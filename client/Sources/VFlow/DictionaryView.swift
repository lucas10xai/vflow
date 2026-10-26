import SwiftUI
import VFlowCore

/// Sắp xếp danh sách (dùng chung Từ điển/Snippets): A–Z theo tên chính, hoặc "dùng nhiều" (số lần
/// dùng giảm dần, hoà thì theo A–Z để ổn định thứ tự).
enum ListSort: String, CaseIterable, Identifiable {
    case alphabetical, mostUsed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .alphabetical: "A–Z"
        case .mostUsed: "Dùng nhiều"
        }
    }

    var order: ListSortOrder {
        switch self {
        case .alphabetical: .alphabetical
        case .mostUsed: .mostUsed
        }
    }
}

/// Tab "Từ điển": `GET/PUT /v1/dictionary` kiểu đọc-sửa-ghi (đọc lại ngay trước khi ghi, xem
/// `DictionaryOrchestration`). Kiểm hợp lệ phía client giống luật engine TRONG LÚC GÕ (tái dùng
/// CHÍNH `DictionaryValidation.validate` áp lên danh sách sẽ có sau khi lưu, không viết lại luật
/// riêng) trước khi gửi; lỗi `bad_request` của engine hiện nguyên văn (đã là tiếng Việt theo
/// contract), không nuốt.
struct DictionaryView: View {
    let model: StatusModel
    let controller: AppController
    @State private var entries: [DictionaryEntry] = []
    @State private var loadError: ClientError?
    @State private var loaded = false
    @State private var query = ""
    @State private var sort: ListSort = .alphabetical
    @State private var showEditor = false
    @State private var editorOriginalTerm: String?
    @State private var editorTerm = ""
    @State private var editorSpokenText = ""
    @State private var saveError: String?
    @State private var confirmDelete: DictionaryEntry?

    private var visibleEntries: [DictionaryEntry] {
        let filtered = query.isEmpty ? entries : entries.filter {
            $0.term.localizedCaseInsensitiveContains(query) || $0.spoken.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return ListSorting.sorted(filtered, order: sort.order, name: { $0.term }, uses: { $0.uses })
    }

    private var liveValidationError: String? {
        let lines = editorSpokenText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return DictionaryFormValidation.error(term: editorTerm, spokenLines: lines, existing: entries, originalTerm: editorOriginalTerm)
    }

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
        .searchable(text: $query, placement: .toolbar, prompt: "Tìm thuật ngữ hoặc cách nói…")
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
            ContentUnavailableView("Từ điển trống", systemImage: "book.closed",
                                   description: Text("Thêm \"deploy\" với cách nói \"đi plôi\" để vflow luôn gõ đúng thuật ngữ bạn hay dùng."))
        } else if visibleEntries.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(visibleEntries, id: \.term) { entry in
                    DictionaryRow(entry: entry, onEdit: { beginEdit(entry) }, onDelete: { confirmDelete = entry })
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
        switch await controller.fetchDictionary() {
        case .success(let e):
            entries = e
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
        showEditor = true
    }

    private func beginEdit(_ entry: DictionaryEntry) {
        editorOriginalTerm = entry.term
        editorTerm = entry.term
        editorSpokenText = entry.spoken.joined(separator: "\n")
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
        let entry = DictionaryEntry(term: term, spoken: spoken)
        let change: DictionaryChange = editorOriginalTerm.map { .update(originalTerm: $0, entry: entry) } ?? .add(entry)
        let result = await controller.applyDictionaryChange(change)
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
            Text(editorOriginalTerm == nil ? "Thêm mục từ điển" : "Sửa mục từ điển")
                .font(.system(size: 15, weight: .semibold))
                .padding([.top, .horizontal], 20)
                .padding(.bottom, 8)
            Form {
                Section {
                    TextField("Thuật ngữ (vd. deploy)", text: $editorTerm)
                        .accessibilityLabel("Tên thuật ngữ")
                } header: { Text("Thuật ngữ") }
                Section {
                    TextEditor(text: $editorSpokenText)
                        .font(.system(size: 13))
                        .frame(minHeight: 100)
                        .accessibilityLabel("Danh sách cách nói, mỗi dòng một cách")
                } header: { Text("Cách nói (mỗi dòng một cách, 1–\(DictionaryValidation.maxSpoken))") }
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
                    .disabled(liveValidationError != nil || editorTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 8)
        }
        .frame(minWidth: 460, minHeight: 320)
        .onAppear { saveError = nil }
    }
}

struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.term).font(.system(size: 13, weight: .semibold))
                SpokenChips(spoken: entry.spoken)
                Text("Dùng \(entry.uses) lần" + (entry.lastUsed.map { " · lần cuối \($0)" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sửa…", action: onEdit).buttonStyle(.plain).foregroundStyle(Theme.accent)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain).accessibilityLabel("Xoá \(entry.term)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Chip cho từng "cách nói" — gọn hơn chuỗi nối bằng " · " khi có nhiều biến thể.
struct SpokenChips: View {
    let spoken: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(spoken, id: \.self) { s in
                Text(s)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
