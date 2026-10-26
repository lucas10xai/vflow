import Foundation

/// Cách chạy engine con: `node <repo>/bin/vflow.js serve`.
public struct EngineLaunchSpec: Equatable, Sendable {
    public var node: String
    public var script: String
    public var repo: String
    public var port: Int
}

/// Đọc `~/.vflow/client.json` (`{"repo": "...", "node": "...", "port": 7611}`, mọi khoá tuỳ chọn).
/// Ứng dụng GUI không có PATH của shell nên node được dò ở các vị trí cố định.
public enum ClientConfig {
    public static let defaultPort = 7611
    public static let nodeCandidates = ["~/.local/bin/node", "/opt/homebrew/bin/node", "/usr/local/bin/node"]

    public struct FileSystem: Sendable {
        public var read: @Sendable (String) -> Data?
        public var fileExists: @Sendable (String) -> Bool
        public var isExecutable: @Sendable (String) -> Bool
        public init(read: @escaping @Sendable (String) -> Data?, fileExists: @escaping @Sendable (String) -> Bool,
                    isExecutable: @escaping @Sendable (String) -> Bool) {
            self.read = read
            self.fileExists = fileExists
            self.isExecutable = isExecutable
        }

        public static let live = FileSystem(
            read: { FileManager.default.contents(atPath: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    /// - Parameter bundlePath: đường dẫn `VFlow.app`; nếu app nằm ở `<repo>/client/build/` thì dùng repo đó khi cấu hình không chỉ định.
    /// - Parameter vflowHome: thư mục chứa `client.json` (mặc định `<home>/.vflow`); đặt riêng để tôn trọng `VFLOW_HOME`
    ///   (xem `VFlowHome`) mà không đổi cách mở rộng `~` của "repo"/"node" (luôn dựa trên `home` thật).
    public static func resolve(home: String, vflowHome: String? = nil, bundlePath: String?, fs: FileSystem) -> Result<EngineLaunchSpec, ClientError> {
        let dataHome = vflowHome ?? (home + "/.vflow")
        let configPath = dataHome + "/client.json"
        var obj: [String: Any] = [:]
        if let data = fs.read(configPath) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.configInvalid("\(configPath) không phải JSON object hợp lệ"))
            }
            obj = parsed
        }

        var port = defaultPort
        if let p = obj["port"] {
            guard let n = p as? Int, (1...65535).contains(n) else {
                return .failure(.configInvalid("\"port\" phải là số nguyên 1–65535"))
            }
            port = n
        }

        // Ưu tiên nguồn "repo" (thư mục chứa bin/vflow.js): client.json (người dùng đặt) > engine tự
        // đủ đóng gói TRONG bundle (M4b/Phần 2, app không cần repo/Node hệ thống) > suy ra từ
        // bundlePath kiểu `<repo>/client/build/VFlow.app` (chạy thẳng từ repo lúc phát triển).
        let repo: String
        let usedBundledEngine: Bool
        if let r = obj["repo"] {
            guard let s = r as? String, !s.isEmpty else { return .failure(.configInvalid("\"repo\" phải là chuỗi đường dẫn")) }
            repo = expand(s, home: home)
            guard fs.fileExists(repo + "/bin/vflow.js") else {
                return .failure(.configInvalid("không thấy \(repo)/bin/vflow.js (khoá \"repo\")"))
            }
            usedBundledEngine = false
        } else if let b = bundlePath, fs.fileExists(bundledEngineDir(b) + "/bin/vflow.js") {
            repo = bundledEngineDir(b)
            usedBundledEngine = true
        } else if let b = bundlePath, let derived = repoFromBundle(b), fs.fileExists(derived + "/bin/vflow.js") {
            repo = derived
            usedBundledEngine = false
        } else {
            return .failure(.configInvalid("chưa biết repo vflow: thêm \"repo\" vào \(configPath)"))
        }

        // Cổng Node: client.json (người dùng đặt) > Node đóng gói CÙNG engine tự đủ vừa chọn ở trên
        // (chỉ khi đó thật là engine trong bundle — không lẫn Node đóng gói cho repo dev) > dò hệ thống.
        let node: String
        if let n = obj["node"] {
            guard let s = n as? String, !s.isEmpty else { return .failure(.configInvalid("\"node\" phải là chuỗi đường dẫn")) }
            let p = expand(s, home: home)
            // Cấu hình chỉ định sai ⇒ báo lỗi, không âm thầm dùng node khác.
            guard fs.isExecutable(p) else { return .failure(.configInvalid("\"node\" không chạy được: \(p)")) }
            node = p
        } else if usedBundledEngine, fs.isExecutable(repo + "/node/bin/node") {
            node = repo + "/node/bin/node"
        } else if let found = nodeCandidates.map({ expand($0, home: home) }).first(where: fs.isExecutable) {
            node = found
        } else {
            return .failure(.configInvalid("không tìm thấy node (đã thử \(nodeCandidates.joined(separator: ", "))); đặt \"node\" trong \(configPath)"))
        }
        return .success(EngineLaunchSpec(node: node, script: repo + "/bin/vflow.js", repo: repo, port: port))
    }

    /// `<bundle>/Contents/Resources/engine` — thư mục engine tự đủ nếu `bundle-engine.sh` đã đóng
    /// gói (có `bin/vflow.js`, `node_modules/`, và Node riêng ở `node/bin/node`).
    static func bundledEngineDir(_ bundlePath: String) -> String { bundlePath + "/Contents/Resources/engine" }

    /// `<repo>/client/build/VFlow.app` ⇒ `<repo>`.
    static func repoFromBundle(_ bundlePath: String) -> String? {
        var parts = bundlePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while parts.last == "" { parts.removeLast() }
        guard parts.count >= 4, parts[parts.count - 2] == "build", parts[parts.count - 3] == "client" else { return nil }
        return parts.dropLast(3).joined(separator: "/")
    }
}

/// Cổng dùng để gọi engine: tính từ `EngineLaunchSpec` đã resolve, KHÔNG BAO GIỜ suy đoán ra
/// `ClientConfig.defaultPort` khi cấu hình lỗi/chưa biết. Cấu hình lỗi ⇒ `.blocked` (gọi engine
/// lúc đó chỉ có thể là nhầm cổng), không có đường nào trả về mặc định thay cho cổng thật.
public enum EnginePortResolution: Equatable, Sendable {
    case port(Int)
    case blocked(ClientError)

    public static func resolve(spec: EngineLaunchSpec?, configError: ClientError?) -> EnginePortResolution {
        if let spec { return .port(spec.port) }
        if let configError { return .blocked(configError) }
        return .blocked(.configInvalid("chưa xác định được cổng engine"))
    }
}
