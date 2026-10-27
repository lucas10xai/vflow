import Foundation
import Testing
@testable import VFlowCore

// Q2: "Micro không dùng được: thiết bị micro thay đổi hoặc bị rút" hiện đỏ và huỷ lượt ghi dù KHÔNG ai
// rút micro. Đo thật: AVAudioEngineConfigurationChange bắn ~0,3 s sau start bình thường, và khi đó
// engine đã tự dừng. Các test dưới đây khoá hành vi đúng bằng backend giả (không cần micro thật).

@MainActor
private final class FakeBackend: MicBackend {
    var running = true
    var format = MicInputFormat(sampleRate: 16000, channels: 1)
    var lastFrame: TimeInterval?
    var now: TimeInterval = 100
    /// Kết quả kịch bản cho từng bước; mặc định thất bại.
    var restartWorks = false
    var rebuildWorks: (String?) -> Bool = { _ in false }
    /// true = engine chạy lại được nhưng micro câm (không có khung mới).
    var mute = false
    private(set) var calls: [String] = []

    var isEngineRunning: Bool { running }
    var inputFormat: MicInputFormat { format }
    var lastFrameUptime: TimeInterval? { lastFrame }
    var uptime: TimeInterval { now }

    func restartSameEngine() -> Bool {
        calls.append("restart")
        guard restartWorks else { return false }
        revive()
        return true
    }

    func rebuildEngine(pinUID: String?) -> Bool {
        calls.append("rebuild(\(pinUID ?? "mặc định"))")
        guard rebuildWorks(pinUID) else { return false }
        revive()
        return true
    }

    private func revive() {
        running = true
        format = MicInputFormat(sampleRate: 16000, channels: 1)
        if !mute { lastFrame = now } // khung mới tới ngay sau khi chạy lại
    }
}

@MainActor
private final class Events {
    var list: [MicRecoverySession.Event] = []
    var failedCount: Int { list.filter { if case .failed = $0 { return true } else { return false } }.count }
}

/// Cho các Task trên MainActor (verify/recovery với sleep tức thì) chạy hết.
@MainActor
private func settle() async {
    for _ in 0..<300 { await Task.yield() }
}

@MainActor
private func makeSession(_ b: FakeBackend, chosen: String? = nil, events: Events, healthyWhileWaiting: Bool = false) -> MicRecoverySession {
    MicRecoverySession(backend: b, chosenUID: chosen, startedAtUptime: b.now - 1, sleepMs: { [weak b] ms in
        await MainActor.run {
            guard let b else { return }
            b.now += Double(ms) / 1000
            if healthyWhileWaiting, b.running { b.lastFrame = b.now } // micro khoẻ: khung vẫn đều đặn
        }
    }, onEvent: { events.list.append($0) })
}

@Suite @MainActor struct MicRecoveryDecisionTests {
    private func state(running: Bool = true, rate: Double = 16000, channels: Int = 1,
                       sinceFrame: Double? = 100, sinceStart: Double = 5000) -> MicRecoveryPolicy.InputState {
        .init(engineRunning: running, format: MicInputFormat(sampleRate: rate, channels: channels),
              msSinceLastFrame: sinceFrame, msSinceStart: sinceStart)
    }

    @Test func thôngBáoKhiĐầuVàoCònTốtBịBỏQua() {
        #expect(MicRecoveryPolicy.decide(state()) == .ignore)
        // đang trong giai đoạn khởi động, engine chạy, chưa có khung đầu (khung đầu thường ~0,5–0,7 s)
        #expect(MicRecoveryPolicy.decide(state(sinceFrame: nil, sinceStart: 300)) == .ignore)
    }

    /// Ca ĐO THẬT: thông báo lúc khởi động, engine đã tự dừng, 0 khung. Chỉ "bỏ qua" thì câu nói ra file rỗng.
    @Test func engineĐãTựDừngThìPhảiDựngLạiDùĐangỞGiaiĐoạnKhởiĐộng() {
        #expect(MicRecoveryPolicy.decide(state(running: false, sinceFrame: nil, sinceStart: 350)) == .recover(.engineStopped))
    }

    @Test func địnhDạngHỏngĐổiTầnSốVàKhungĐứngĐềuPhảiKhôiPhục() {
        #expect(MicRecoveryPolicy.decide(state(rate: 0, channels: 0)) == .recover(.formatInvalid))
        #expect(MicRecoveryPolicy.decide(state(rate: 4000)) == .recover(.formatInvalid))
        #expect(MicRecoveryPolicy.decide(state(sinceFrame: 1400)) == .ignore)
        #expect(MicRecoveryPolicy.decide(state(sinceFrame: 1600)) == .recover(.stalled))
        #expect(MicRecoveryPolicy.decide(state(sinceFrame: nil, sinceStart: 2900)) == .ignore) // micro khởi động chậm vẫn được chờ tới 3 s
        #expect(MicRecoveryPolicy.decide(state(sinceFrame: nil, sinceStart: 3100)) == .recover(.noFirstFrame))
    }

    @Test func thứTựKhôiPhụcThiếtBịĐãChọnThửLạiRồiMớiRơiVềMặcĐịnh() {
        #expect(MicRecoveryPolicy.steps(chosenUID: nil).map(\.step) == [.restartSameEngine, .rebuild(pinUID: nil), .rebuild(pinUID: nil)])
        let chosen = MicRecoveryPolicy.steps(chosenUID: "abc").map(\.step)
        #expect(chosen == [.restartSameEngine, .rebuild(pinUID: "abc"), .rebuild(pinUID: nil), .rebuild(pinUID: nil)])
        #expect(MicRecoveryPolicy.steps(chosenUID: "abc").first?.delayMs == 0)
    }
}

@Suite @MainActor struct MicRecoverySessionTests {
    @Test func thôngBáoCấuHìnhLúcKhởiĐộngKhiEngineĐãDừngKHÔNGHuỷLượtMàKhôiPhụcÊm() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = nil; b.restartWorks = true   // đúng ca đo thật
        let s = makeSession(b, events: ev)
        s.configurationChanged()
        await settle()
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
        #expect(b.calls == ["restart"])
        #expect(ev.failedCount == 0)
    }

    @Test func thôngBáoGiữaLượtKhiĐầuVàoCònTốtKhôngLàmGìCả() async {
        let b = FakeBackend(); let ev = Events()
        b.lastFrame = b.now - 0.1
        let s = makeSession(b, events: ev, healthyWhileWaiting: true)
        s.configurationChanged()
        await settle()
        #expect(ev.list.isEmpty)       // không sự kiện nào (không "recovered", càng không "failed")
        #expect(b.calls.isEmpty)       // không đụng vào engine đang khoẻ
    }

    @Test func thôngBáoKhiEngineBáoChạyNhưngKhungKhôngCònTớiThìSauKhiXácNhậnVẫnDựngLại() async {
        let b = FakeBackend(); let ev = Events()
        b.lastFrame = b.now - 0.1; b.restartWorks = true
        let s = makeSession(b, events: ev, healthyWhileWaiting: false) // không có khung mới sau thông báo
        s.configurationChanged()
        await settle()
        #expect(b.calls == ["restart"])
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
    }

    @Test func đầuVàoMấtRồiKhôiPhụcĐượcBằngEngineMớiThìLượtTiếpTục() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.format = MicInputFormat(sampleRate: 0, channels: 0); b.lastFrame = b.now - 5
        b.restartWorks = false; b.rebuildWorks = { $0 == nil }
        let s = makeSession(b, events: ev)
        s.watchdogTick()
        await settle()
        #expect(b.calls == ["restart", "rebuild(mặc định)"])
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
    }

    @Test func thiếtBịĐãChọnBiếnMấtRơiVềMặcĐịnhVàBáoĐúngUIDĐểNhắcNhẹ() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = b.now - 5
        b.rebuildWorks = { $0 == nil } // ghim thiết bị đã chọn thất bại (đã rút), mặc định thì được
        let s = makeSession(b, chosen: "UID-TAI-NGHE", events: ev)
        s.configurationChanged()
        await settle()
        #expect(b.calls == ["restart", "rebuild(UID-TAI-NGHE)", "rebuild(mặc định)"])
        #expect(ev.list == [.recovered(fellBackFromUID: "UID-TAI-NGHE")])
    }

    @Test func thiếtBịĐãChọnThửLạiĐượcThìKhôngBáoRơiVềMặcĐịnh() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = b.now - 5
        b.rebuildWorks = { $0 == "UID-TAI-NGHE" }
        let s = makeSession(b, chosen: "UID-TAI-NGHE", events: ev)
        s.configurationChanged()
        await settle()
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
    }

    @Test func mọiBướcKhôiPhụcHỏngThìBáoThấtBạiĐúngMộtLần() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = b.now - 5
        let s = makeSession(b, events: ev)
        s.configurationChanged()
        await settle()
        #expect(ev.failedCount == 1)
        #expect(b.calls.count == MicRecoveryPolicy.steps(chosenUID: nil).count)
        #expect(!s.isRecovering)
    }

    @Test func engineChạyLạiĐượcNhưngMicroCâmThìCoiLàHỏngVàThửBướcSau() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = b.now - 5
        b.restartWorks = true; b.mute = true; b.rebuildWorks = { _ in true }
        let s = makeSession(b, events: ev)
        s.configurationChanged()
        await settle()
        // mọi bước đều "chạy được" nhưng không có khung mới ⇒ không được báo recovered giả
        #expect(ev.list.contains { $0 == .recovered(fellBackFromUID: nil) } == false)
        #expect(ev.failedCount == 1)
        #expect(b.calls == ["restart", "rebuild(mặc định)", "rebuild(mặc định)"])
    }

    @Test func watchdogPhátHiệnEngineChếtÂmThầmKhôngCầnThôngBáo() async {
        let b = FakeBackend(); let ev = Events()
        b.lastFrame = b.now - 3 // engine "chạy" nhưng 3 s không có khung
        b.restartWorks = true
        let s = makeSession(b, events: ev)
        s.watchdogTick()
        await settle()
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
    }

    @Test func micFlappingVôTậnBịChặnBởiTrầnKhôiPhục() async {
        let b = FakeBackend(); let ev = Events()
        b.restartWorks = true
        let s = makeSession(b, events: ev)
        for _ in 0..<(MicRecoveryPolicy.maxRecoveriesPerRecording + 1) {
            b.lastFrame = b.now - 3 // lại đứng
            s.watchdogTick()
            await settle()
        }
        #expect(ev.list.filter { $0 == .recovered(fellBackFromUID: nil) }.count == MicRecoveryPolicy.maxRecoveriesPerRecording)
        #expect(ev.failedCount == 1)
    }

    @Test func huỷPhiênThìKhôngCònSựKiệnNàoSauĐó() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.lastFrame = b.now - 5; b.restartWorks = true
        let s = makeSession(b, events: ev)
        s.configurationChanged()
        s.cancel() // người dùng nhả phím/Esc trước khi khôi phục xong
        await settle()
        #expect(ev.list.isEmpty)
        s.configurationChanged(); s.watchdogTick(); await settle()
        #expect(ev.list.isEmpty)
    }

    @Test func mởMicroThấtBạiNgayTừĐầuĐượcKhôiPhụcThayVìBáoĐỏ() async {
        let b = FakeBackend(); let ev = Events()
        b.running = false; b.format = MicInputFormat(sampleRate: 0, channels: 0); b.lastFrame = nil
        b.rebuildWorks = { $0 == nil }
        let s = makeSession(b, events: ev)
        s.recoverAfterStartFailure()
        await settle()
        #expect(ev.list == [.recovered(fellBackFromUID: nil)])
    }
}

@Suite struct MicFailureOutcomeTests {
    @Test func đãCóĐủÂmThanhThìGửiĐiVàChỉNhắcNhẹ() {
        let o = MicRecoveryPolicy.outcome(collectedSeconds: 0.5, deviceName: "Ulisten B1 ANC", neverStarted: false)
        guard case .sendCollected(let notice) = o else { Issue.record("phải gửi đi: \(o)"); return }
        #expect(notice.contains("đã gửi"))
        #expect(MicRecoveryPolicy.outcome(collectedSeconds: 12, deviceName: nil, neverStarted: false) == o)
    }

    @Test func chưaCóGìThìBáoLỗiĐúngNguyênNhânKèmTênThiếtBị() {
        let mid = MicRecoveryPolicy.outcome(collectedSeconds: 0.49, deviceName: "Ulisten B1 ANC", neverStarted: false)
        #expect(mid == .error(message: "micro bị ngắt giữa chừng (Ulisten B1 ANC)"))
        let start = MicRecoveryPolicy.outcome(collectedSeconds: 0, deviceName: "Micrô MacBook Pro", neverStarted: true, detail: "-10868")
        #expect(start == .error(message: "không mở được micro (Micrô MacBook Pro): -10868"))
        // không nói chung chung và không còn câu cũ gây hiểu nhầm "rút micro"
        for o in [mid, start] {
            guard case .error(let m) = o else { continue }
            #expect(!m.contains("thay đổi hoặc bị rút"))
        }
        #expect(MicRecoveryPolicy.outcome(collectedSeconds: 0, deviceName: nil, neverStarted: false) == .error(message: "micro bị ngắt giữa chừng"))
    }

    @Test func thôngĐiệpHiểnThịChoNgườiDùngĐúng() {
        let text = ErrorText.message(.micUnavailable("micro bị ngắt giữa chừng (Ulisten B1 ANC)"))
        #expect(text == "Micro không dùng được: micro bị ngắt giữa chừng (Ulisten B1 ANC)")
    }

    @Test func nhắcThiếtBịKhôngCònLàNhắcNhẹKhôngPhảiLỗi() {
        #expect(MicRecoveryPolicy.deviceMissingNotice.contains("mặc định"))
        #expect(LastErrorPolicy.after(overlay: .notice(MicRecoveryPolicy.deviceMissingNotice)) == nil) // không vào "Lỗi gần nhất"
    }
}

@Suite struct RecordingBufferTests {
    private func tone(_ n: Int, rate: Double, amp: Float = 0.5) -> [Float] {
        (0..<n).map { amp * sin(2 * Float.pi * 440 * Float($0) / Float(rate)) }
    }

    private func int16s(_ d: Data) -> [Int16] {
        d.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }

    @Test func đổiTầnSốGiữaLượtGiữNguyênMẫuĐãThu() {
        let buf = RecordingBuffer()
        buf.append(mono: tone(48000, rate: 48000), inputRate: 48000)   // 1 s ở 48 kHz (tai nghe chạy nhạc)
        let before = buf.seconds
        #expect(before > 0.9 && before <= 1.0)
        buf.append(mono: tone(16000, rate: 16000), inputRate: 16000)   // Bluetooth đổi sang HFP 16 kHz: 1 s nữa
        #expect(abs(buf.seconds - 2.0) < 0.01)
        let pcm = int16s(buf.finish())
        #expect(abs(pcm.count - 32000) < 40)
        // 1 giây ĐẦU vẫn là tiếng thật (không bị vứt/ghi đè khi đổi bộ chuyển đổi)
        let firstPeak = pcm.prefix(15000).map { abs(Int($0)) }.max() ?? 0
        let secondPeak = pcm.suffix(15000).map { abs(Int($0)) }.max() ?? 0
        #expect(firstPeak > 10000 && secondPeak > 10000)
    }

    @Test func khôngĐổiTầnSốThìKếtQuảGiốngHệtMộtLầnXửLý() {
        let signal = tone(24000, rate: 48000)
        let a = RecordingBuffer()
        a.append(mono: Array(signal[0..<9000]), inputRate: 48000)
        a.append(mono: Array(signal[9000...]), inputRate: 48000)
        let b = RecordingBuffer()
        b.append(mono: signal, inputRate: 48000)
        #expect(a.finish() == b.finish())
    }

    @Test func snapshotKhôngLàmMấtMẫuVàFinishXoáSạch() {
        let buf = RecordingBuffer()
        buf.append(mono: tone(16000, rate: 16000), inputRate: 16000)
        let s1 = buf.snapshotData(); let s2 = buf.snapshotData()
        #expect(s1 == s2 && !s1.isEmpty)
        #expect(buf.finish() == s1)
        #expect(buf.isEmpty)
    }
}

@Suite struct LastErrorPolicyTests {
    @Test func lượtThànhCôngXoáLỗiCũ_lượtLỗiGiữLỗiMới() {
        // Trước đó có lỗi đỏ ("Lỗi gần nhất"); một lượt ghi THÀNH CÔNG (đã dán / không nghe thấy gì / nhắc nhẹ) phải xoá nó.
        #expect(LastErrorPolicy.after(overlay: .done) == nil)
        #expect(LastErrorPolicy.after(overlay: .notice("Không nghe thấy gì")) == nil)
        #expect(LastErrorPolicy.after(overlay: .transcribing) == nil)
        #expect(LastErrorPolicy.after(overlay: .error("Micro không dùng được: x")) == "Micro không dùng được: x")
    }

    @Test func kếtQuảThànhCôngCủaEngineQuaDictationDecisionKhôngTạoLỗi() {
        let ok = TranscribeResult(text: "xin chào", silence: false, mode: "normal", model: "m", rewriteError: nil, totalMs: nil)
        let plan = DictationDecision.plan(for: .success(ok))
        #expect(LastErrorPolicy.after(overlay: plan.overlay) == nil)
        let failed = DictationDecision.plan(for: .failure(.micUnavailable("x")))
        #expect(LastErrorPolicy.after(overlay: failed.overlay) != nil)
    }
}
