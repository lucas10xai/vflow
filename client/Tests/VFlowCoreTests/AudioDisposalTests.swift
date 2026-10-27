import Foundation
import Testing
@testable import VFlowCore

/// Ghi lại các lần gọi xoá (an toàn đa luồng cho closure @Sendable).
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [String] = []
    var ids: [String] { lock.lock(); defer { lock.unlock() }; return _ids }
    func add(_ id: String) { lock.lock(); _ids.append(id); lock.unlock() }
}

private final class PatchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _patches: [SettingsPatch] = []
    var patches: [SettingsPatch] { lock.lock(); defer { lock.unlock() }; return _patches }
    func add(_ p: SettingsPatch) { lock.lock(); _patches.append(p); lock.unlock() }
}

@Suite struct HistoryGateDecisionTests {
    @Test func normalRecordedEntryKeepsItsAudio() {
        let d = HistoryGate.decide(enabled: true, insertedText: "xin chào", audioId: "au_1")
        #expect(d == .init(record: true, discardAudioId: nil), "mục lịch sử đã trỏ tới âm thanh ⇒ KHÔNG được xoá")
    }

    @Test func historyOffDiscardsAudioBecauseNothingPointsToIt() {
        let d = HistoryGate.decide(enabled: false, insertedText: "xin chào", audioId: "au_1")
        #expect(d == .init(record: false, discardAudioId: "au_1"))
    }

    @Test func nothingInsertedDiscardsAudio() {
        for text in [nil, "", "   \n"] as [String?] {
            let d = HistoryGate.decide(enabled: true, insertedText: text, audioId: "au_1")
            #expect(d == .init(record: false, discardAudioId: "au_1"), "text=\(String(describing: text))")
        }
    }

    /// Command Mode ghi mục lịch sử nhưng mục KHÔNG mang `audio_id` ⇒ âm thanh vẫn phải xoá.
    @Test func commandModeEntryDoesNotCarryAudioSoItIsDiscardedEvenWhenRecorded() {
        let d = HistoryGate.decide(enabled: true, insertedText: "viết lại câu này", audioId: "au_cmd", entryCarriesAudio: false)
        #expect(d.record)
        #expect(d.discardAudioId == "au_cmd")
    }

    @Test func noAudioIdMeansNothingToDiscardInAnyBranch() {
        for enabled in [true, false] {
            for text in [nil, "", "chữ"] as [String?] {
                for carries in [true, false] {
                    #expect(HistoryGate.decide(enabled: enabled, insertedText: text, audioId: nil, entryCarriesAudio: carries).discardAudioId == nil)
                }
            }
        }
    }

    @Test func recordDecisionStillMatchesShouldRecord() {
        for enabled in [true, false] {
            for text in [nil, "", "  ", "chữ"] as [String?] {
                #expect(HistoryGate.decide(enabled: enabled, insertedText: text, audioId: "x").record
                        == HistoryGate.shouldRecord(enabled: enabled, insertedText: text))
            }
        }
    }
}

@Suite struct AudioDisposalTests {
    @Test func callsDeleteExactlyOnceWithTheId() async {
        let log = CallLog()
        let ok = await AudioDisposal.discard(audioId: "au_1") { id in log.add(id); return true }
        #expect(ok)
        #expect(log.ids == ["au_1"])
    }

    @Test func noIdMeansNoCall() async {
        let log = CallLog()
        let a = await AudioDisposal.discard(audioId: nil) { id in log.add(id); return true }
        let b = await AudioDisposal.discard(audioId: "") { id in log.add(id); return true }
        #expect(!a && !b)
        #expect(log.ids.isEmpty)
    }

    /// Engine lỗi/404/chết ⇒ `delete` báo `false`: không ném, không gọi lại, người gọi đi tiếp.
    @Test func failedDeleteIsReportedAsFalseAndNeverRetried() async {
        let log = CallLog()
        let ok = await AudioDisposal.discard(audioId: "au_gone") { id in log.add(id); return false }
        #expect(!ok)
        #expect(log.ids == ["au_gone"], "best-effort: đúng một lần, không thử lại")
    }
}

@Suite struct AudioHistoryEnforcerTests {
    @Test func turningHistoryOffSendsAudioHistoryFalseWithoutAnyOtherField() async throws {
        let log = PatchLog()
        let enforcer = AudioHistoryEnforcer(send: { patch in log.add(patch); return .success(AppSettings(cloudLlm: true, llmModel: nil, llmTimeoutMs: 3500, actionsEnabled: true)) })
        let r = await enforcer.historyEnabledChanged(to: false)
        #expect((try? r.get()) != nil)
        #expect(log.patches.count == 1)
        let body = try #require(EngineAPI.settingsPutRequest(port: 1, token: "t", patch: log.patches[0]).httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj.count == 1)
        #expect(obj["audio_history"] as? Bool == false)
    }

    /// Bật lại Lịch sử KHÔNG được gửi gì (đặc biệt không bật audio_history).
    @Test func turningHistoryOnSendsNothing() async {
        let log = PatchLog()
        let enforcer = AudioHistoryEnforcer(send: { patch in log.add(patch); return .failure(.engineNotRunning) })
        let r = await enforcer.historyEnabledChanged(to: true)
        #expect((try? r.get()) != nil)
        #expect(log.patches.isEmpty)
    }

    @Test func sendFailureIsReportedNotSwallowed() async {
        let enforcer = AudioHistoryEnforcer(send: { _ in .failure(.engineNotRunning) })
        let r = await enforcer.historyEnabledChanged(to: false)
        guard case .failure(.engineNotRunning) = r else { Issue.record("phải báo lỗi thật"); return }
    }
}
