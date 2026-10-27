import Foundation

/// Vị trí HUD ghi âm (V3, Cài đặt › Giao diện) — "Dưới màn hình" là hành vi CŨ (mặc định, không đổi
/// gì khi người dùng chưa chọn lại), "Cạnh notch" đặt sát mép TRÊN màn hình, tránh vùng notch.
public enum OverlayPosition: String, CaseIterable, Sendable {
    case bottom, topNearNotch

    public var title: String {
        switch self {
        case .bottom: "Dưới màn hình"
        case .topNearNotch: "Cạnh notch"
        }
    }
}

/// Cỡ HUD (V3) — chỉ ảnh hưởng số dòng chữ TRỰC TIẾP ("Xem chữ chạy trực tiếp") hiện thêm dưới
/// dòng trạng thái chính; dòng trạng thái chính (biểu tượng + chữ + sóng âm) luôn hiện ở mọi cỡ.
public enum OverlaySize: String, CaseIterable, Sendable {
    case compact, medium, large

    public var title: String {
        switch self {
        case .compact: "Gọn"
        case .medium: "Vừa"
        case .large: "Lớn"
        }
    }

    /// Số dòng chữ chạy trực tiếp hiện thêm (0 = không hiện, chỉ viên thuốc + sóng).
    public var livePreviewLineCount: Int {
        switch self {
        case .compact: 0
        case .medium: 2
        case .large: 4
        }
    }

    /// Độ rộng tối đa gợi ý cho khung chữ chạy trực tiếp — "Lớn" rộng hơn "Vừa" để chứa 4 dòng mà
    /// không quá hẹp/cao.
    public var maxPreviewWidth: Double {
        switch self {
        case .compact: 0
        case .medium: 320
        case .large: 460
        }
    }

    /// Độ rộng tối đa của CẢ viên HUD (gồm lề) — "Lớn" phải rộng hơn khung chữ trực tiếp 460 + lề 2×14
    /// để 4 dòng không bị ép hẹp; "Gọn"/"Vừa" giữ 460 như hành vi cũ.
    public var maxContainerWidth: Double {
        switch self {
        case .compact, .medium: 460
        case .large: 500
        }
    }
}

/// Đặt khung HUD lên màn hình — hàm THUẦN (chỉ nhận toạ độ, không đụng AppKit), test được (xem
/// contract mục 5a). Lớp AppKit (`OverlayController`) đưa `NSScreen.visibleFrame`/`frame` và
/// `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`/`safeAreaInsets` vào đây.
public enum OverlayLayout {
    public struct Rect: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var width: Double
        public var height: Double
        public init(minX: Double, minY: Double, width: Double, height: Double) {
            self.minX = minX
            self.minY = minY
            self.width = width
            self.height = height
        }
        public var maxX: Double { minX + width }
        public var maxY: Double { minY + height }
        public var midX: Double { minX + width / 2 }
    }

    /// Khoảng cách từ mép màn hình (đáy ở vị trí "Dưới màn hình", đỉnh ở vị trí "Cạnh notch") tới HUD.
    public static let edgeMargin: Double = 18

    /// Hai dải hai bên notch ở dạng KHÔNG PHỤ THUỘC hệ toạ độ mà `NSScreen.auxiliaryTopLeftArea/
    /// auxiliaryTopRightArea` dùng (toàn cục hay cục bộ theo màn hình — màn hình phụ có gốc khác 0
    /// làm hai cách khác nhau): dải trái luôn bắt đầu ở mép trái màn hình, dải phải luôn kết thúc ở mép
    /// phải, nên chỉ cần CHIỀU RỘNG của từng dải. `nil` nếu thiếu một trong hai (máy không notch).
    public static func auxiliaryAreas(screenFrame: Rect, leftWidth: Double?, rightWidth: Double?,
                                      height: Double) -> (left: Rect, right: Rect)? {
        guard let leftWidth, let rightWidth, leftWidth > 0, rightWidth > 0,
              leftWidth + rightWidth < screenFrame.width else { return nil }
        return (Rect(minX: screenFrame.minX, minY: screenFrame.maxY - height, width: leftWidth, height: height),
                Rect(minX: screenFrame.maxX - rightWidth, minY: screenFrame.maxY - height, width: rightWidth, height: height))
    }

    /// `screenFrame`: toàn bộ khung màn hình (bao gồm vùng Dock/thanh menu, dùng để kẹp biên không
    /// tràn ra ngoài — KHÁC `visibleFrame` hiện dùng cho "Dưới màn hình", xem `frame(for:)`).
    /// `visibleFrame`: `NSScreen.visibleFrame` (đã trừ Dock + thanh menu) — dùng cho "Dưới màn hình"
    /// (hành vi CŨ, không đổi). `auxiliaryLeft`/`auxiliaryRight`: vùng hai bên notch
    /// (`NSScreen.auxiliaryTopLeftArea/Right`), `nil` nếu máy không có notch — khi đó "Cạnh notch"
    /// coi cả cạnh trên là tự do (không có vùng cần tránh), vẫn đặt DƯỚI thanh menu bằng cách dùng
    /// `visibleFrame.maxY` làm giới hạn trên. `topInset`: `NSScreen.safeAreaInsets.top` — khi thanh
    /// menu tự ẩn (toàn màn hình) `visibleFrame.maxY` có thể chạm đỉnh màn hình và HUD sẽ chui vào
    /// dải notch; giới hạn trên là `min(visibleFrame.maxY, screenFrame.maxY - topInset)`.
    public static func frame(contentSize: Rect, screenFrame: Rect, visibleFrame: Rect,
                             auxiliaryLeft: Rect?, auxiliaryRight: Rect?,
                             position: OverlayPosition, topInset: Double = 0) -> Rect {
        let width = contentSize.width
        let height = contentSize.height
        switch position {
        case .bottom:
            let x = clampX(visibleFrame.midX - width / 2, width: width, screenFrame: screenFrame)
            let y = clampY(visibleFrame.minY + edgeMargin, height: height, screenFrame: screenFrame)
            return Rect(minX: x, minY: y, width: width, height: height)
        case .topNearNotch:
            // Tâm ngang: giữa notch (khoảng trống giữa hai dải phụ — HUD nằm DƯỚI thanh menu nên không
            // đè lên notch), hoặc giữa cả màn hình nếu không có notch.
            let centerMinX: Double
            let centerMaxX: Double
            if let left = auxiliaryLeft, let right = auxiliaryRight {
                centerMinX = left.maxX
                centerMaxX = right.minX
            } else {
                centerMinX = screenFrame.minX
                centerMaxX = screenFrame.maxX
            }
            let centerX = (centerMinX + centerMaxX) / 2
            let x = clampX(centerX - width / 2, width: width, screenFrame: screenFrame)
            // Ngay dưới thanh menu/notch.
            let ceiling = min(visibleFrame.maxY, screenFrame.maxY - max(0, topInset))
            let y = clampY(ceiling - edgeMargin - height, height: height, screenFrame: screenFrame)
            return Rect(minX: x, minY: y, width: width, height: height)
        }
    }

    /// Kẹp tung độ để HUD không tràn ra ngoài `screenFrame` theo chiều dọc (nội dung cao hơn vùng
    /// còn lại, vd. cỡ "Lớn" trên màn hình thấp).
    private static func clampY(_ y: Double, height: Double, screenFrame: Rect) -> Double {
        min(max(y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - height))
    }

    /// Kẹp hoành độ để HUD không tràn ra ngoài `screenFrame` (vd. HUD rộng hơn vùng an toàn hẹp
    /// giữa hai dải phụ, hoặc màn hình phụ nhỏ hơn nội dung).
    private static func clampX(_ x: Double, width: Double, screenFrame: Rect) -> Double {
        min(max(x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - width))
    }
}
