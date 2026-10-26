import Foundation

/// Thư mục dữ liệu `~/.vflow` (token, client.json, lịch sử, …). Tôn trọng biến môi trường
/// `VFLOW_HOME` giống engine (`engine/stt/registry.js` `vflowHome`) để thử nghiệm không đụng
/// dữ liệu thật: `VFLOW_HOME=/tmp/x` ⇒ dùng thẳng `/tmp/x`, không còn phải là con của `home`.
public enum VFlowHome {
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                                home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        if let v = environment["VFLOW_HOME"], !v.isEmpty {
            return ClientConfig.expand(v, home: home)
        }
        return home + "/.vflow"
    }
}
