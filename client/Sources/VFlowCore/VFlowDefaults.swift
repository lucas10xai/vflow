import Foundation

/// Lớp truy cập UserDefaults DUY NHẤT của app — cô lập theo `VFLOW_HOME` để các lần chạy thử (ảnh
/// chụp, kiểm thủ công) không ghi đè khoá (`mode`, `hasSeenWelcome`, vị trí cửa sổ…) của app thật
/// (domain `org.aios.vflow`, dùng `UserDefaults.standard`). KHÔNG có `VFLOW_HOME` ⇒ `.standard`
/// (hành vi cũ, không di cư dữ liệu); CÓ ⇒ một suite riêng SUY RA từ đường dẫn, không bao giờ trùng
/// hai `VFLOW_HOME` khác nhau và không bao giờ đụng domain thật.
public enum VFlowDefaults {
    /// Tên suite suy ra từ `home` — băm ổn định (FNV-1a, không dùng `Hasher` vì seed đổi mỗi lần
    /// chạy process) để CÙNG một `VFLOW_HOME` luôn ra CÙNG suite giữa các lần mở app.
    public static func suiteName(forHome home: String) -> String {
        "org.aios.vflow.sandbox." + stableHash(home)
    }

    static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    /// `UserDefaults` dùng cho TOÀN BỘ app: `.standard` khi không có `VFLOW_HOME`; suite riêng khi
    /// có. `UserDefaults(suiteName:)` chỉ trả `nil` nếu tên suite không hợp lệ — không xảy ra với
    /// tên sinh ra ở đây, nhưng vẫn rơi về `.standard` thay vì ép buộc (`!`) để không bao giờ sập.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> UserDefaults {
        guard let home = environment["VFLOW_HOME"], !home.isEmpty else { return .standard }
        return UserDefaults(suiteName: suiteName(forHome: home)) ?? .standard
    }
}
