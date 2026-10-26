import AppKit
import SwiftUI
import VFlowCore

/// Tab "Thống kê" (V2): `GET /v1/stats` — lời chào lớn theo tổng số từ, 4 thẻ số, lưới hoạt động 16
/// tuần, và danh sách ứng dụng đã nói nhiều nhất. Logic thuần (lời chào, mức cường độ, bố cục lưới,
/// định dạng số) nằm ở `VFlowCore.StatsPresentation` (có test) — view ở đây chỉ hiển thị.
struct StatsView: View {
    let model: StatusModel
    let controller: AppController

    private enum Phase {
        case loading
        case loaded(StatsSummary)
        case failed(ClientError)
    }

    @State private var phase: Phase = .loading
    @State private var confirmClear = false
    @State private var clearError: String?
    @State private var enabling = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            content
        }
        // Làm mới khi mở tab (engine vừa sẵn sàng), khi cửa sổ lấy lại focus, và sau mỗi lần
        // dictation xong — MỘT nguồn sự kiện chung (`NotificationCenter`), không poll liên tục.
        .task(id: model.engineReady) {
            guard model.engineReady else { return }
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vflowStatsMayHaveChanged)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .alert("Xoá toàn bộ thống kê?", isPresented: $confirmClear) {
            Button("Xoá", role: .destructive) { Task { await clear() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không thể hoàn tác. Số từ, chuỗi ngày và hoạt động theo ứng dụng sẽ bị xoá — không ảnh hưởng lịch sử.")
        }
    }

    private var header: some View {
        HStack {
            SectionTitle(text: "Thống kê")
            Spacer()
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Làm mới").disabled(!model.engineReady)
        }
    }

    @ViewBuilder private var content: some View {
        if model.engineBlocked {
            engineProblem(text: model.engineSummary, showRestart: model.engineHasFailed)
        } else if !model.engineReady {
            Text("Đang chờ engine khởi động…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            switch phase {
            case .loading:
                Text("Đang tải…").font(.system(size: 13)).foregroundStyle(.secondary)
            case .failed(let e):
                engineProblem(text: ErrorText.message(e), showRestart: false)
            case .loaded(let s):
                loadedBody(s)
            }
        }
    }

    private func engineProblem(text: String, showRestart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 13)).foregroundStyle(Color.red)
            HStack(spacing: 10) {
                Button("Thử lại") { Task { await load() } }
                if showRestart { Button("Khởi động lại engine") { controller.restartEngine() } }
            }
        }
    }

    @ViewBuilder private func loadedBody(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            GreetingHeadline(totalWords: s.totalWords)
            if !s.enabled {
                StatsDisabledCard(enabling: enabling, onEnable: { Task { await enable() } },
                                  onOpenSettings: { controller.openSettingsWindow(tab: .data) })
            } else if s.totalWords == 0 {
                ContentUnavailableView("Chưa có câu nào", systemImage: "waveform",
                                       description: Text("Giữ ⌥ trái và nói thử — thống kê sẽ bắt đầu hiện ở đây."))
            } else {
                StatCardsRow(summary: s)
                HeatmapCard(summary: s)
                TopAppsCard(topApps: s.topApps)
            }
            if let clearError {
                Text(clearError).font(.footnote).foregroundStyle(Color.red)
            }
        }
    }

    private func load() async {
        switch await controller.fetchStats() {
        case .success(let s): phase = .loaded(s)
        case .failure(let e): phase = .failed(e)
        }
    }

    private func enable() async {
        enabling = true
        _ = await controller.applySettingsPatch(SettingsPatch(statsEnabled: true))
        enabling = false
        await load()
    }

    private func clear() async {
        switch await controller.deleteStats() {
        case .success: clearError = nil; await load()
        case .failure(let e): clearError = ErrorText.message(e)
        }
    }
}

/// (a) Lời chào lớn đầu tab — NGƯỠNG theo tổng số từ toàn thời gian (`StatsGreeting`, có test).
private struct GreetingHeadline: View {
    let totalWords: Int
    var body: some View {
        Text(StatsGreeting.text(totalWords: totalWords))
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Thống kê đang tắt" — `enabled=false`: nút Bật (sửa `stats_enabled`) + nút dẫn tới Cài đặt.
private struct StatsDisabledCard: View {
    let enabling: Bool
    let onEnable: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Thống kê đang tắt", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text("Bật lại để vflow tiếp tục đếm số từ, chuỗi ngày nói, và ứng dụng bạn hay dùng. Dữ liệu cũ (nếu có) không bị xoá.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.sm) {
                Button(enabling ? "Đang bật…" : "Bật") { onEnable() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(enabling)
                Button("Mở Cài đặt › Dữ liệu") { onOpenSettings() }
                    .buttonStyle(.link)
            }
        }
        .cardBackground()
    }
}

/// (b) Hàng 4 thẻ số — nhãn chữ hoa nhỏ giãn chữ, số lớn.
private struct StatCardsRow: View {
    let summary: StatsSummary
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            StatCard(label: "TỪ ĐÃ NÓI", value: VFlowNumberFormat.grouped(summary.totalWords), hint: nil)
            StatCard(label: "WPM TRUNG BÌNH", value: AvgWpmText.text(summary.avgWpm),
                    hint: summary.avgWpm == nil ? AvgWpmText.hint : nil)
            StatCard(label: "CHUỖI NGÀY", value: "\(VFlowNumberFormat.grouped(summary.currentStreak))", hint: nil)
            StatCard(label: "CHUỖI DÀI NHẤT", value: "\(VFlowNumberFormat.grouped(summary.bestStreak))", hint: nil)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(hint.map { ", \($0)" } ?? "")")
        .help(hint ?? "")
    }
}

/// (c) "Hoạt động 16 tuần" — lưới 7×`weeks`, tuần bắt đầu Thứ Hai, cột phải nhất là tuần hiện tại.
private struct HeatmapCard: View {
    let summary: StatsSummary
    private let cellSize: CGFloat = 13
    private let cellSpacing: CGFloat = 3

    private var grid: [[HeatmapCell?]] {
        ActivityHeatmap.grid(days: summary.days, today: summary.today, weeks: summary.weeks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(text: "Hoạt động \(summary.weeks) tuần")
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { weekday in
                        Text(ActivityHeatmap.weekdayLabelsFull[weekday])
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 20, height: cellSize, alignment: .leading)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<summary.weeks, id: \.self) { weekIndex in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { weekday in
                                    HeatmapCellView(cell: grid[weekday][weekIndex], size: cellSize)
                                }
                            }
                        }
                    }
                }
            }
            HeatmapLegend(cellSize: cellSize)
        }
        .cardBackground()
    }
}

private struct HeatmapCellView: View {
    let cell: HeatmapCell?
    let size: CGFloat

    var body: some View {
        if let cell {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.accent.opacity(HeatmapIntensity.opacity(cell.level)))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(cell.isToday ? Color.primary : Color.clear, lineWidth: 1.5)
                )
                .help(cell.label)
                .accessibilityLabel(cell.label)
        } else {
            // Ngày tương lai — không vẽ (chỗ trống giữ bố cục lưới đều).
            Rectangle().fill(Color.clear).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

private struct HeatmapLegend: View {
    let cellSize: CGFloat
    var body: some View {
        HStack(spacing: 4) {
            Text("Ít").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(HeatmapIntensity.opacity(level)))
                    .frame(width: cellSize * 0.8, height: cellSize * 0.8)
            }
            Text("Nhiều").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

/// Độ mờ hiện cho từng mức 0–4 — thương hiệu cam (`Theme.accent`), KHÔNG dùng xanh ngọc.
enum HeatmapIntensity {
    static func opacity(_ level: Int) -> Double {
        switch level {
        case 0: 0.08
        case 1: 0.30
        case 2: 0.50
        case 3: 0.72
        default: 1.0
        }
    }
}

/// (d) "Từ của bạn đi đâu" — top ứng dụng, biểu tượng thật + thanh tỷ lệ + số từ.
private struct TopAppsCard: View {
    let topApps: [AppWordStat]

    private var ranked: [AppWordStat] { topApps.sorted { $0.words > $1.words }.prefix(10).map { $0 } }
    private var maxWords: Int { max(ranked.map(\.words).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(text: "Từ của bạn đi đâu")
            if ranked.isEmpty {
                Text("Chưa có dữ liệu theo ứng dụng.").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(ranked) { app in
                        TopAppRow(app: app, ratio: Double(app.words) / Double(maxWords))
                    }
                }
            }
        }
        .cardBackground()
    }
}

private struct TopAppRow: View {
    let app: AppWordStat
    let ratio: Double

    private var displayName: String { StatsAppIdentity.displayName(bundleId: app.app) }
    private var icon: NSImage? { StatsAppIdentity.icon(bundleId: app.app) }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName).font(.callout)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.accent.opacity(0.75))
                        .frame(width: max(proxy.size.width * ratio, 2), height: 6)
                }
                .frame(height: 6)
            }
            Text(VFlowNumberFormat.grouped(app.words))
                .font(.callout.weight(.medium))
                .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName): \(VFlowNumberFormat.grouped(app.words)) từ")
    }
}

/// Biểu tượng/tên ứng dụng thật qua `NSWorkspace` theo bundle id — `"unknown"` hoặc không tìm thấy
/// ⇒ biểu tượng chung + "Không rõ" (khác `AppIconResolver`/`AppDisplayName` ở `HistoryView.swift`,
/// vốn hiện NGUYÊN bundle id khi không tìm thấy — ở đây luôn có nhãn tiếng Việt thân thiện).
enum StatsAppIdentity {
    static func icon(bundleId: String) -> NSImage? {
        guard bundleId != "unknown", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func displayName(bundleId: String) -> String {
        guard bundleId != "unknown", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return "Không rõ" }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
