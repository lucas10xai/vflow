import AppKit
import SwiftUI
import VFlowCore

struct TranslationSheet: View {
    let controller: AppController
    let entry: HistoryEntry
    let dismiss: () -> Void
    @State private var target = "en"
    @State private var formality: Tone = .neutral
    @State private var result = ""
    @State private var error: String?
    @State private var dispatch = SingleFlightTask<Result<TranslationResult, ClientError>>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dịch câu này").font(.headline)
            Text(entry.text).font(.callout).lineLimit(4)
            HStack {
                Picker("Ngôn ngữ đích", selection: $target) {
                    ForEach(TranslationTarget.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Mức trang trọng", selection: $formality) {
                    ForEach(Tone.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button("Dịch") { translate() }.disabled(dispatch.isRunning)
            }
            if !result.isEmpty { Text(result).textSelection(.enabled).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Huỷ") { dispatch.cancel(); dismiss() }
                Spacer()
                Button("Sao chép") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }.disabled(result.isEmpty)
                Button("Chèn vào ô đang gõ") { Task { _ = await controller.insertTranslationText(result); dismiss() } }.disabled(result.isEmpty)
            }
        }.padding(20).frame(minWidth: 460).onDisappear { dispatch.cancel() }
    }

    /// Bấm "Dịch" khi đang có một lượt bay (vd. đổi ngôn ngữ đích rồi bấm lại ngay) ⇒ `SingleFlightTask`
    /// tự huỷ lượt cũ trước khi gửi lượt mới — không bao giờ hai kết quả "đua" nhau ghi đè màn hình.
    private func translate() {
        error = nil
        dispatch.run({ [controller, entry, target, formality] in
            await controller.translateHistory(text: entry.text, target: target, formality: formality)
        }, onResult: { response in
            switch response { case .success(let value): result = value.text; case .failure(let value): error = ErrorText.message(value) }
        })
    }
}
