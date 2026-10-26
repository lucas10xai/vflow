import Foundation
import Testing
@testable import VFlowCore

@Suite struct SettingsValidationTests {
    @Test func timeoutWithinRangeIsValid() {
        #expect(SettingsValidation.validateTimeoutMs(8000).isSuccessSettings)
        #expect(SettingsValidation.validateTimeoutMs(1000).isSuccessSettings)
        #expect(SettingsValidation.validateTimeoutMs(30000).isSuccessSettings)
    }

    @Test func timeoutOutsideRangeIsRejected() {
        guard case .failure = SettingsValidation.validateTimeoutMs(999) else { Issue.record("999ms phải lỗi"); return }
        guard case .failure = SettingsValidation.validateTimeoutMs(30001) else { Issue.record("30001ms phải lỗi"); return }
    }

    @Test func nilModelIsValid() {
        #expect(SettingsValidation.validateModel(nil).isSuccessSettings)
    }

    @Test func modelOver200CharsIsRejected() {
        guard case .failure = SettingsValidation.validateModel(String(repeating: "a", count: 201)) else {
            Issue.record("model > 200 ký tự phải lỗi"); return
        }
    }
}

private extension Result where Failure == SettingsValidationError {
    var isSuccessSettings: Bool { if case .success = self { return true }; return false }
}

@Suite struct EnterActionTests {
    @Test func sendsWhenActionsContainEnterAndEnabled() {
        #expect(EnterAction.shouldSend(actions: ["enter"], actionsEnabled: true))
    }

    @Test func doesNotSendWhenDisabledEvenIfEnginePresentIt() {
        #expect(!EnterAction.shouldSend(actions: ["enter"], actionsEnabled: false))
    }

    @Test func doesNotSendWhenNoEnterAction() {
        #expect(!EnterAction.shouldSend(actions: [], actionsEnabled: true))
    }

    @Test func unrelatedActionsAreIgnored() {
        #expect(!EnterAction.shouldSend(actions: ["something_else"], actionsEnabled: true))
    }
}

@Suite struct SettingsRequestTests {
    @Test func getParsesAllFourFields() {
        let body = Data("{\"cloud_llm\":true,\"llm_model\":\"ag/gemini-3.8-flash\",\"llm_timeout_ms\":8000,\"actions_enabled\":true}".utf8)
        guard case .success(let s) = EngineAPI.parseSettings(status: 200, data: body) else { Issue.record("phải đọc được"); return }
        #expect(s == AppSettings(cloudLlm: true, llmModel: "ag/gemini-3.8-flash", llmTimeoutMs: 8000, actionsEnabled: true))
    }

    @Test func getParsesNullModel() {
        let body = Data("{\"cloud_llm\":false,\"llm_model\":null,\"llm_timeout_ms\":8000,\"actions_enabled\":false}".utf8)
        guard case .success(let s) = EngineAPI.parseSettings(status: 200, data: body) else { Issue.record("phải đọc được"); return }
        #expect(s.llmModel == nil && !s.cloudLlm && !s.actionsEnabled)
    }

    @Test func badRequestIsSurfacedNotSwallowed() {
        let body = Data("{\"error\":{\"code\":\"bad_request\",\"message\":\"llm_timeout_ms phải là số nguyên 1000–30000\"}}".utf8)
        guard case .failure(.engine(let status, let code, _)) = EngineAPI.parseSettings(status: 400, data: body) else {
            Issue.record("phải lỗi engine"); return
        }
        #expect(status == 400 && code == "bad_request")
    }

    @Test func putRequestOnlySendsChangedFields() {
        let req = EngineAPI.settingsPutRequest(port: 7611, token: "t", patch: SettingsPatch(llmTimeoutMs: 5000))
        let obj = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(obj.count == 1 && obj["llm_timeout_ms"] as? Int == 5000)
    }

    @Test func putRequestEncodesExplicitNullModel() {
        let req = EngineAPI.settingsPutRequest(port: 7611, token: "t", patch: SettingsPatch(llmModel: .some(nil)))
        let obj = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(obj["llm_model"] is NSNull)
    }
}

@Suite struct CommandRequestTests {
    @Test func requestEncodesAllFields() {
        let req = EngineAPI.commandRequest(port: 7611, token: "t", instruction: "sửa lỗi chính tả", selection: "đoạn chọn",
                                           context: "ngữ cảnh", app: "com.apple.Terminal")
        let obj = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(obj["instruction"] as? String == "sửa lỗi chính tả")
        #expect(obj["selection"] as? String == "đoạn chọn")
        #expect(obj["app"] as? String == "com.apple.Terminal")
    }

    @Test func successParsesTextAndKind() {
        let body = Data("{\"text\":\"đã sửa\",\"kind\":\"edit\",\"timings_ms\":{\"llm\":900}}".utf8)
        guard case .success(let r) = EngineAPI.parseCommand(status: 200, data: body) else { Issue.record("phải đọc được"); return }
        #expect(r == CommandResult(text: "đã sửa", kind: "edit"))
    }

    @Test(arguments: [("cloud_disabled", 503), ("rewrite_unavailable", 503), ("timeout", 504), ("bad_request", 400)])
    func errorCodesNeverProduceFakeText(code: String, status: Int) {
        let body = Data("{\"error\":{\"code\":\"\(code)\",\"message\":\"lỗi\"}}".utf8)
        guard case .failure(.engine(let s, let c, _)) = EngineAPI.parseCommand(status: status, data: body) else {
            Issue.record("mã \(code) phải lỗi, không được trả text giả"); return
        }
        #expect(s == status && c == code)
    }
}
