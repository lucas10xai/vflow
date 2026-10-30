import SwiftUI
import VFlowCore

/// Tab "Tổng quan": bảng điều khiển U1 — thẻ trạng thái lớn, thẻ phím tắt, thẻ chế độ, thẻ quyền,
/// thẻ "Hôm nay", và mục "Hệ thống" thu gọn. Dùng CHUNG `StatusModel` với menu thanh trạng thái nên
/// hai nơi không bao giờ nói khác nhau. Quyết định NỘI DUNG (trạng thái thẻ, ánh xạ mã→chữ, tổng
/// hợp "Hôm nay") nằm ở `VFlowCore.DesignSystem` (hàm thuần, có test) — view chỉ hiển thị.
struct OverviewView: View {
    let model: StatusModel
    let controller: AppController
    /// Mở tab Thống kê khi bấm thẻ "Hôm nay" — `nil` chỉ khi hiện trong ngữ cảnh không có thanh bên
    /// (không có trường hợp này trong app thật, nhưng tránh áp đặt phụ thuộc không cần cho preview/test).
    var onOpenStats: (() -> Void)?
    @State private var lastErrorDismissed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let warning = model.conflictWarning {
                ConflictBanner(text: warning)
            }
            if let error = model.lastError, !lastErrorDismissed {
                DismissableErrorCard(text: error) { lastErrorDismissed = true }
            }
            if let reminder = model.menuBarIconReminder {
                MenuBarOcclusionCard(text: reminder, controller: controller)
            }

            HeroCard(model: model, controller: controller)
            ShortcutsCard()
            ModeCard(mode: model.mode, controller: controller) { controller.mode = $0 }
            PermissionsCard(permissions: model.permissions)
            TodayCard(controller: controller, historyEnabled: controller.historyEnabled, onOpenStats: onOpenStats)
            SystemDisclosure(model: model, controller: controller)
        }
        .onChange(of: model.lastError) { _, _ in lastErrorDismissed = false }
    }
}

// MARK: - Thẻ trạng thái lớn

private struct HeroCard: View {
    let model: StatusModel
    let controller: AppController

    private var status: HeroStatus { HeroStatusDecision.decide(model) }

    /// Màu nhấn theo trạng thái — sẵn sàng (cam thương hiệu), thiếu quyền (cam cảnh báo), lỗi (đỏ),
    /// đang khởi động (trung tính) — một nguồn duy nhất cho cả biểu tượng và nền nhấn nhẹ.
    private var tint: Color {
        switch status {
        case .ready: Theme.accent
        case .startingEngine: .secondary
        case .missingPermissions: .orange
        case .problem: .red
        }
    }

    private var symbol: String {
        switch status {
        case .ready: "checkmark.circle.fill"
        case .startingEngine: "hourglass"
        case .missingPermissions: "exclamationmark.shield.fill"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subtitle {
                    Text(sub).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline)\(subtitle.map { ". \($0)" } ?? "")")
    }

    private var headline: String {
        switch status {
        case .ready: "Sẵn sàng. Giữ ⌥ trái để nói"
        case .startingEngine: "Đang khởi động engine…"
        case .missingPermissions(let count): "Thiếu \(count) quyền macOS"
        case .problem: "Có vấn đề cần xử lý"
        }
    }

    private var subtitle: String? {
        switch status {
        case .ready: nil
        case .startingEngine: "vflow sẽ sẵn sàng trong giây lát."
        case .missingPermissions: "Cấp đủ quyền để ghi âm, nghe phím ⌥, và dán chữ."
        case .problem(let message): message
        }
    }

    private struct CardAction { let title: String; let run: () -> Void }

    private var action: CardAction? {
        switch status {
        case .ready, .startingEngine: return nil
        case .missingPermissions:
            guard let first = model.missingPermissions.first else { return nil }
            return CardAction(title: "Cấp quyền…") { first.kind.request(); first.kind.openSettings() }
        case .problem:
            if model.engineHasFailed { return CardAction(title: "Khởi động lại engine") { controller.restartEngine() } }
            if model.canRetryLast { return CardAction(title: "Thử lại lần cuối") { controller.retryLast() } }
            return nil
        }
    }
}

private struct DismissableErrorCard: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lỗi gần nhất").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng thông báo lỗi")
        }
        .padding(Theme.Spacing.md)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

/// Thẻ nhắc "biểu tượng thanh menu bị che" (notch/thanh menu đầy, xem `VFlowCore.MenuBarOcclusion`)
/// — đóng được, nhớ theo NGÀY (không đóng vĩnh viễn, xem `AppController.dismissMenuBarOcclusionReminder`).
private struct MenuBarOcclusionCard: View {
    let text: String
    let controller: AppController

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "eye.slash").foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Biểu tượng thanh menu có thể đang bị che").font(.callout.weight(.semibold))
                // Ảnh chụp NGOÀI MÀN HÌNH ở giao diện TỐI vẽ dòng này mờ gần như vô hình dù đã thử cả
                // `.secondary` LẪN ép tường minh `Color.primary` (không đổi gì cả) — cùng dạng giới
                // hạn offscreen render đã biết với `List` (xem README mục "Công cụ chụp ảnh ngoài màn
                // hình › Giới hạn đã biết"), KHÔNG PHẢI lỗi màu trong code này; `Color.primary` vẫn
                // giữ vì đúng ý định hiển thị, chỉ chưa chắc khớp ảnh chụp.
                Text(text).font(.footnote).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                Button("Mở Cài đặt › Chung") { controller.openSettingsWindow(tab: .general) }
                    .buttonStyle(.link)
            }
            Spacer()
            Button { controller.dismissMenuBarOcclusionReminder() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng thẻ nhắc biểu tượng bị che")
        }
        .padding(Theme.Spacing.md)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

struct ConflictBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            Text(text).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.headline).foregroundStyle(.secondary) }
}

// MARK: - Thẻ phím tắt

private struct ShortcutsCard: View {
    private let rows: [(keys: [String], text: String)] = [
        (["⌥"], "Giữ để nói"),
        (["⌥", "⌥"], "Bấm đúp để khoá ghi âm (hands-free)"),
        (["esc"], "Để huỷ"),
        (["⌥", "⌃"], "Giữ để ra lệnh (Command Mode)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(text: "Phím tắt")
            ForEach(rows, id: \.text) { row in
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in Keycap(symbol: key) }
                    Text(row.text).font(.callout)
                    Spacer()
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "waveform").foregroundStyle(.secondary)
                Text("Nói \u{201C}nhấn enter\u{201D} ở cuối câu để tự động gửi phím Return.").font(.callout)
                Spacer()
            }
        }
        .cardBackground()
    }
}

private struct Keycap: View {
    let symbol: String
    var body: some View {
        Text(symbol)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .frame(minWidth: 28, minHeight: 24)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.secondary.opacity(0.3)))
            .accessibilityHidden(true)
    }
}

// MARK: - Thẻ chế độ

private struct ModeCard: View {
    let mode: DictationMode
    let controller: AppController
    let onChange: @MainActor (DictationMode) -> Void
    @State private var settings: AppSettings?

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible(), spacing: Theme.Spacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(text: "Chế độ")
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(DictationMode.allCases, id: \.self) { m in
                    ModeRow(mode: m, selected: m == mode, disabled: ModeAvailability.isDisabled(m, cloudLlm: settings?.cloudLlm ?? true)) { onChange(m) }
                }
            }
            if mode == .translate {
                TranslationControls(settings: settings, controller: controller)
            }
            if settings?.cloudLlm == false {
                HStack { Text("Dịch cần gửi chữ qua máy chủ của bạn. Đám mây đang tắt.").font(.footnote).foregroundStyle(Theme.warningText); Spacer(); Button("Mở Cài đặt") { controller.openSettingsWindow(tab: .advanced) } }
            }
        }
        .cardBackground()
        .task { if case .success(let value) = await controller.fetchSettings() { settings = value } }
    }
}

/// Thẻ chọn chế độ dạng LƯỚI 2 cột (gọn hơn danh sách dọc 6 dòng) — biểu tượng + tên + nhãn
/// Trong máy/Gửi chữ + mô tả ngắn, viền cam rõ khi đang chọn.
private struct ModeRow: View {
    let mode: DictationMode
    let selected: Bool
    let disabled: Bool
    let onSelect: () -> Void

    private var symbol: String {
        switch mode {
        case .auto: "sparkles"
        case .normal: "mic"
        case .clean: "wand.and.sparkles"
        case .email: "envelope"
        case .tidy: "text.badge.checkmark"
        case .dev: "chevron.left.forwardslash.chevron.right"
        case .translate: "translate"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(selected ? Theme.accent : .secondary)
                    Text(mode.title).font(.callout.weight(.medium))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.callout)
                    }
                }
                Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                CloudBadge(cloud: mode.sendsTextToCloud)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.title), \(ModeCloudLabel.text(mode)), \(mode.subtitle)\(selected ? ", đang chọn" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TranslationControls: View {
    let settings: AppSettings?
    let controller: AppController
    @State private var target = "en"
    @State private var formality: Tone = .neutral
    @State private var custom = ""

    var body: some View {
        HStack {
            Picker("Ngôn ngữ đích", selection: $target) {
                ForEach(TranslationTarget.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                Text("Khác…").tag("custom")
            }.onChange(of: target) { _, value in if value != "custom" { save(target: value) } }
            if target == "custom" { TextField("Mã ISO", text: $custom).frame(width: 75).onSubmit { if TranslationValidation.isValidISOCode(custom) { save(target: custom.lowercased()) } } }
            Picker("Mức trang trọng", selection: $formality) { ForEach(Tone.allCases, id: \.self) { Text($0.title).tag($0) } }
                .onChange(of: formality) { _, value in Task { _ = await controller.applySettingsPatch(.init(translateFormality: value)) } }
        }
        .font(.footnote)
        .onAppear { target = settings?.translateTarget ?? "en"; formality = settings?.translateFormality ?? .neutral }
    }
    private func save(target: String) { guard TranslationValidation.isValidISOCode(target) else { return }; Task { _ = await controller.applySettingsPatch(.init(translateTarget: target)) } }
}

private struct CloudBadge: View {
    let cloud: Bool
    var body: some View {
        Label(ModeCloudLabel.text(DictationModeProxy.forCloud(cloud)), systemImage: cloud ? "cloud" : "lock.fill")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// `CloudBadge` chỉ cần nhãn đúng với `cloud`, không cần đúng `DictationMode` thật — tránh phải
/// truyền cả `DictationMode` chỉ để lấy một nhãn hai giá trị.
private enum DictationModeProxy {
    static func forCloud(_ cloud: Bool) -> DictationMode { cloud ? .tidy : .normal }
}

// MARK: - Thẻ quyền

private struct PermissionsCard: View {
    let permissions: [PermissionItem]

    private var allGranted: Bool { PermissionsProgress.allGranted(permissions) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionTitle(text: "Quyền macOS")
                Spacer()
                if allGranted {
                    Label(PermissionsProgress.text(permissions), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.callout.weight(.medium))
                } else {
                    Text(PermissionsProgress.text(permissions)).font(.callout).foregroundStyle(.orange)
                }
            }
            if !allGranted {
                ForEach(permissions, id: \.kind) { p in
                    HStack {
                        Label(p.kind.title, systemImage: p.kind.symbol).font(.callout)
                        Spacer()
                        Text(p.statusText).font(.callout.weight(.medium))
                            .foregroundStyle(p.granted ? Color.green : Color.orange)
                        if !p.granted {
                            Button("Cấp quyền…") { p.kind.request(); p.kind.openSettings() }
                                .accessibilityLabel("Cấp quyền \(p.kind.title)")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(p.kind.title): \(p.statusText)")
                }
            }
        }
        .cardBackground()
    }
}

// MARK: - Thẻ "Hôm nay"

private struct TodayCard: View {
    let controller: AppController
    let historyEnabled: Bool
    var onOpenStats: (() -> Void)?
    @State private var summary: TodaySummary = .disabled

    var body: some View {
        Group {
            if let onOpenStats {
                Button(action: onOpenStats) { cardBody }
                    .buttonStyle(.plain)
                    .help("Mở tab Thống kê")
            } else {
                cardBody
            }
        }
        .onAppear(perform: reload)
        .onChange(of: historyEnabled) { _, _ in reload() }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionTitle(text: "Hôm nay")
                if onOpenStats != nil {
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            content
        }
        .cardBackground()
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        switch summary {
        case .disabled:
            Text("Lịch sử đang tắt.").font(.callout).foregroundStyle(.secondary)
        case .data(let sentences, let words, let speakingMs):
            HStack(spacing: Theme.Spacing.xl) {
                StatColumn(value: "\(sentences)", label: "câu")
                StatColumn(value: "\(words)", label: "từ")
                StatColumn(value: durationText(speakingMs), label: "thời gian nói")
            }
        }
    }

    private func durationText(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let m = totalSeconds / 60, s = totalSeconds % 60
        return m > 0 ? "\(m) phút \(s) giây" : "\(s) giây"
    }

    private func reload() {
        guard let entries = try? controller.listHistory(query: nil).entries else {
            summary = historyEnabled ? .data(sentences: 0, words: 0, speakingMs: 0) : .disabled
            return
        }
        summary = TodayStats.summarize(entries: entries, historyEnabled: historyEnabled, now: Date())
    }
}

private struct StatColumn: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Hệ thống (thu gọn)

private struct SystemDisclosure: View {
    let model: StatusModel
    let controller: AppController
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Hệ thống", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let status = model.modelBootstrapStatus {
                    Text(status).font(.callout)
                        .foregroundStyle(status.hasPrefix("Chép model lần đầu lỗi") || status.hasPrefix("Tải model lỗi") ? Color.red : Color.secondary)
                    if controller.canOpenModelDownload {
                        Button("Tải model…") { controller.openModelDownload() }
                    }
                }
                Text(model.engineSummary).font(.callout)
                if model.models.isEmpty {
                    Text("Chưa đọc được /healthz").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(model.models, id: \.id) { m in
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: m.loaded ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(m.loaded ? Color.green : Color.orange)
                            Text(m.id).font(.callout)
                            Text("(\(m.kind))").font(.caption).foregroundStyle(.secondary)
                            Text(m.loaded ? "Sẵn sàng" : ModelReasonText.friendly(m.reason ?? "không rõ"))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(spacing: Theme.Spacing.md) {
                    Button("Thử lại lần cuối") { controller.retryLast() }.disabled(!model.canRetryLast)
                    Button("Khởi động lại engine") { controller.restartEngine() }
                    Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .font(.headline)
        .cardBackground()
    }
}
