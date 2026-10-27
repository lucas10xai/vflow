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
    @State private var showTeachSheet = false
    /// "Gợi ý từ lần anh sửa" (V2, `GET /v1/dictionary/suggestions`) — chỉ hiện khi có gợi ý.
    @State private var suggestions: [DictionarySuggestion] = []
    @State private var suggestionError: String?

    /// CHỈ dùng cho `--snapshot` (U3, mục "sheet Thêm mục có lỗi hợp lệ") — mở sẵn sheet Thêm mục
    /// với trạng thái cho trước (vd. có thuật ngữ nhưng CHƯA có cách nói ⇒ lỗi hợp lệ thật, không
    /// phải ảnh chụp giả). `nil` ở mọi nơi khác (hành vi cũ không đổi).
    init(model: StatusModel, controller: AppController, debugOpenEditor: (term: String, spokenText: String)? = nil) {
        self.model = model
        self.controller = controller
        if let d = debugOpenEditor {
            _showEditor = State(initialValue: true)
            _editorTerm = State(initialValue: d.term)
            _editorSpokenText = State(initialValue: d.spokenText)
        }
    }

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
            if !suggestions.isEmpty {
                SuggestionsSection(suggestions: suggestions, onAdd: beginAddFromSuggestion, onDismiss: { s in Task { await dismiss(s) } })
            }
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
        .sheet(isPresented: $showTeachSheet) {
            TeachWordSheet(model: model, controller: controller, onSaved: { next in
                entries = next
                showTeachSheet = false
            }, onCancel: { showTeachSheet = false })
        }
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
            Button("Dạy từ bằng giọng…") { showTeachSheet = true }
                .disabled(!model.engineReady)
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
        switch await controller.fetchDictionarySuggestions() {
        case .success(let s): suggestions = s; suggestionError = nil
        case .failure(let e): suggestionError = ErrorText.message(e) // không chặn phần còn lại của tab
        }
    }

    private func beginAdd() {
        editorOriginalTerm = nil
        editorTerm = ""
        editorSpokenText = ""
        showEditor = true
    }

    /// "Thêm vào từ điển" trên một gợi ý — mở CÙNG sheet Thêm mục, có sẵn dữ liệu để người dùng
    /// xem/sửa trước khi lưu (không tự lưu thẳng).
    private func beginAddFromSuggestion(_ s: DictionarySuggestion) {
        editorOriginalTerm = nil
        editorTerm = s.term
        editorSpokenText = s.variants.joined(separator: "\n")
        showEditor = true
    }

    private func dismiss(_ s: DictionarySuggestion) async {
        switch await controller.dismissDictionarySuggestion(term: s.term) {
        case .success: suggestions.removeAll { $0.term == s.term }
        case .failure(let e): suggestionError = ErrorText.message(e)
        }
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
            suggestions.removeAll { $0.term == term } // vừa thêm/sửa đúng thuật ngữ này
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

/// "Gợi ý từ lần anh sửa" (V2, `GET /v1/dictionary/suggestions`) — cặp (từ đúng, cách nghe sai) xuất
/// hiện ≥ 2 lần qua sửa tay sau dictation (`learn_from_edits` bật), CHƯA có trong từ điển.
private struct SuggestionsSection: View {
    let suggestions: [DictionarySuggestion]
    let onAdd: (DictionarySuggestion) -> Void
    let onDismiss: (DictionarySuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Gợi ý từ lần anh sửa")
            ForEach(suggestions) { s in
                SuggestionRow(suggestion: s, onAdd: { onAdd(s) }, onDismiss: { onDismiss(s) })
            }
        }
        .padding(10)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

private struct SuggestionRow: View {
    let suggestion: DictionarySuggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.term).font(.system(size: 13, weight: .semibold))
                SpokenChips(spoken: suggestion.variants)
                Text("Gặp \(suggestion.count) lần").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Thêm vào từ điển", action: onAdd).buttonStyle(.bordered).tint(Theme.accent)
            Button("Bỏ qua", action: onDismiss).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gợi ý: \(suggestion.term), gặp \(suggestion.count) lần")
    }
}

/// "Dạy từ bằng giọng…" (V3): nhập từ đúng, nói 3–5 lần (mỗi lần tối đa 10 giây), mỗi lần gọi
/// `POST /v1/teach` và hiện "Nghe ra: …"; gom các cách nghe khác nhau bằng
/// `VFlowCore.TeachWordVariants` (logic thuần, có test) rồi lưu vào từ điển (gộp, không tạo trùng).
/// Âm thanh chỉ nằm trong RAM (`AudioRecorder` riêng của sheet, bỏ khi gửi xong/đóng sheet): KHÔNG
/// ghi đĩa, KHÔNG vào lịch sử/thống kê (engine `/v1/teach` cũng không ghi gì).
struct TeachWordSheet: View {
    let model: StatusModel
    let controller: AppController
    let onSaved: ([DictionaryEntry]) -> Void
    let onCancel: () -> Void

    @State private var term = ""
    @State private var heardList: [TeachWordVariants.Heard] = []
    @State private var nextHeardId = 1
    /// Khoá chuẩn hoá của các cách nói người dùng ĐÃ BỎ CHỌN (mặc định mọi cách nói đều chọn).
    @State private var deselected: Set<String> = []
    @State private var isRecording = false
    @State private var level: Float = 0
    @State private var busy = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var saveError: String?
    @State private var recordTimeoutTimer: Timer?

    private let recorder = AudioRecorder()

    private var trimmedTerm: String { term.trimmingCharacters(in: .whitespaces) }
    private var termError: String? { TeachWordVariants.termError(term) }
    private var candidates: [String] { TeachWordVariants.candidates(from: heardList.map(\.text), correctTerm: trimmedTerm) }
    private var selectedVariants: [String] { TeachWordVariants.selected(candidates: candidates, deselected: deselected) }
    private var attemptsFull: Bool { heardList.count >= TeachWordVariants.maxAttempts }
    private var canRecord: Bool { model.engineReady && !busy && !saving && termError == nil && !attemptsFull }
    private var canSave: Bool { termError == nil && !selectedVariants.isEmpty && !busy && !isRecording && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dạy từ bằng giọng").font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Từ đúng").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("vd. Lan, Supabase, deploy", text: $term).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Từ đúng cần dạy")
                    .disabled(isRecording)
                if !trimmedTerm.isEmpty, let termError {
                    Text(termError).font(.system(size: 12)).foregroundStyle(Color.red)
                }
            }
            recordSection
            if !heardList.isEmpty { heardSection }
            if !model.engineReady {
                Text("Engine chưa sẵn sàng — chờ engine khởi động rồi ghi âm.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(Color.red)
                    .accessibilityLabel("Lỗi: \(errorMessage)")
            }
            if let saveError {
                Text(saveError).font(.system(size: 13)).foregroundStyle(Color.red)
                    .accessibilityLabel("Lỗi khi lưu: \(saveError)")
            }
            HStack {
                Button("Huỷ") { cleanupAndCancel() }
                Spacer()
                Button("Lưu vào từ điển") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        .onDisappear { teardownRecording() }
    }

    @ViewBuilder private var recordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(isRecording ? "Dừng ghi" : "Bắt đầu ghi") { toggleRecording() }
                    .disabled(isRecording ? false : !canRecord)
                    .accessibilityLabel(isRecording ? "Dừng ghi và gửi" : "Bắt đầu ghi lần \(heardList.count + 1)")
                if isRecording {
                    LevelMeter(level: level, animated: true).frame(width: 60)
                        .accessibilityHidden(true)
                    Text("Tối đa \(TeachWordVariants.maxSecondsPerAttempt) giây").font(.caption).foregroundStyle(.secondary)
                } else if busy {
                    ProgressView().controlSize(.small)
                    Text("Đang nghe…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Đã nói \(heardList.count)/\(TeachWordVariants.maxAttempts) lần").font(.caption).foregroundStyle(.secondary)
            }
            if attemptsFull {
                Text("Đã đủ \(TeachWordVariants.maxAttempts) lần — xoá bớt một dòng \"Nghe ra\" nếu muốn ghi lại.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Nói rõ \"\(trimmedTerm.isEmpty ? "từ cần dạy" : trimmedTerm)\" — lặp lại \(TeachWordVariants.minAttempts)–\(TeachWordVariants.maxAttempts) lần để gom đủ cách nghe khác nhau.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var heardSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(heardList) { h in
                        HStack {
                            Text("\(h.id). Nghe ra: \(h.text)").font(.system(size: 13))
                            Spacer()
                            Button(action: { heardList.removeAll { $0.id == h.id } }) { Image(systemName: "xmark.circle") }
                                .buttonStyle(.plain).accessibilityLabel("Xoá dòng nghe ra số \(h.id)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 90)
            if !candidates.isEmpty {
                Text("Cách nói sẽ lưu vào từ điển (bỏ chọn nếu không muốn):").font(.system(size: 12, weight: .semibold))
                ForEach(candidates, id: \.self) { c in
                    Toggle(c, isOn: Binding(
                        get: { !deselected.contains(TeachWordVariants.normalize(c)) },
                        set: { on in
                            let key = TeachWordVariants.normalize(c)
                            if on { deselected.remove(key) } else { deselected.insert(key) }
                        }))
                        .font(.system(size: 13))
                }
            } else {
                Text("Engine nghe ra đúng như từ đã nhập — không có cách nói nào cần dạy thêm.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func toggleRecording() {
        if isRecording { stopRecordingAndSend() } else { startRecording() }
    }

    private func startRecording() {
        errorMessage = nil
        saveError = nil
        switch AudioRecorder.permission() {
        case .authorized: break
        case .notDetermined:
            Task {
                let granted = await AudioRecorder.requestPermission()
                if granted { startRecordingAfterPermission() } else { errorMessage = TeachErrorText.message(.micDenied) }
            }
            return
        default:
            errorMessage = TeachErrorText.message(.micDenied)
            return
        }
        startRecordingAfterPermission()
    }

    private func startRecordingAfterPermission() {
        recorder.onLevel = { l in level = l }
        recorder.onInterrupted = { why in
            teardownRecording()
            errorMessage = "Micro bị ngắt (\(why)) — ghi lại."
        }
        do {
            try recorder.start(deviceUID: controller.micDeviceUID)
        } catch let e as ClientError {
            errorMessage = TeachErrorText.message(e)
            return
        } catch {
            errorMessage = "Không mở được micro: \(error.localizedDescription)"
            return
        }
        isRecording = true
        level = 0
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(TeachWordVariants.maxSecondsPerAttempt), repeats: false) { _ in
            MainActor.assumeIsolated { stopRecordingAndSend() }
        }
    }

    private func stopRecordingAndSend() {
        guard isRecording else { return }
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
        isRecording = false
        let pcm = recorder.stop()
        guard !pcm.isEmpty else {
            errorMessage = "Không thu được âm thanh từ micro — kiểm tra micro rồi ghi lại."
            return
        }
        busy = true
        Task {
            let result = await controller.teach(pcm: pcm)
            busy = false
            switch result {
            case .success(let r):
                if let heard = TeachWordVariants.acceptHeard(r.heard) {
                    heardList.append(.init(id: nextHeardId, text: heard))
                    nextHeardId += 1
                } else {
                    errorMessage = TeachErrorText.nothingHeard
                }
            case .failure(let e):
                errorMessage = TeachErrorText.message(e)
            }
        }
    }

    private func teardownRecording() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
        recorder.onLevel = nil
        recorder.onInterrupted = nil
        if isRecording { _ = recorder.stop() }
        isRecording = false
    }

    private func cleanupAndCancel() {
        teardownRecording()
        onCancel()
    }

    private func save() async {
        saveError = nil
        saving = true
        let result = await controller.applyTeachWord(term: trimmedTerm, selectedVariants: selectedVariants)
        saving = false
        switch result {
        case .success(let next):
            teardownRecording()
            onSaved(next)
        case .failure(let e):
            saveError = ErrorText.message(e)
        }
    }
}
