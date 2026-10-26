#!/usr/bin/env swift
// Dựng AppIcon 1024x1024: ô bo góc kiểu macOS (squircle, siêu elip liên tục) nền cam lấy mẫu từ
// logo-main.png + chữ V/vạch sóng đen tách bằng mặt nạ alpha theo độ tối, co giãn & căn giữa theo
// tâm khối lượng, vẽ đè lên nền cam MỚI (không dùng lại ảnh vòng tròn gốc làm nền). Dùng bởi
// client/scripts/make-icon.sh — KHÔNG chạy trực tiếp ngoài script đó.
// dùng: make-icon.swift <logo-main.png vào> <appicon-1024.png ra> [tỉ lệ rộng chữ V 0..1 = 0.72]
import AppKit
import CoreGraphics

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("dùng: make-icon.swift <vào.png> <ra.png> [tỉ lệ rộng chữ V]") }
let inPath = args[1]
let outPath = args[2]
// 72% (đầu trên dải 66–72% cho phép): so sánh thực tế 66/69/72% ở 16px và 32px (xem báo cáo) cho
// thấy khác biệt rất nhỏ ở 16px nhưng 72% rõ nét hơn một chút ở 32px — chọn bản đậm nhất còn gọn.
let glyphWidthFraction = args.count > 3 ? (Double(args[3]) ?? 0.72) : 0.72

guard let input = NSImage(contentsOfFile: inPath),
      let srcCG = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("không đọc được ảnh vào: \(inPath)")
}

let W = srcCG.width
let H = srcCG.height
let colorSpace = CGColorSpaceCreateDeviceRGB()

// Render nguồn vào buffer RGBA để đọc từng pixel.
var srcPixels = [UInt8](repeating: 0, count: W * H * 4)
guard let srcCtx = CGContext(data: &srcPixels, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("không tạo được context đọc pixel")
}
srcCtx.draw(srcCG, in: CGRect(x: 0, y: 0, width: W, height: H))

func luma(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
    0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
}

// ── 1. Lấy mẫu màu cam: trung vị RGB các pixel đặc (alpha==255) và sáng (vùng không có chữ V) ─────
var oranges: [(UInt8, UInt8, UInt8)] = []
for i in 0..<(W * H) {
    let o = i * 4
    let r = srcPixels[o], g = srcPixels[o + 1], b = srcPixels[o + 2], a = srcPixels[o + 3]
    if a == 255 && luma(r, g, b) > 120 {
        oranges.append((r, g, b))
    }
}
guard !oranges.isEmpty else { fail("không tìm thấy pixel cam đặc trong \(inPath)") }
func median(_ xs: [UInt8]) -> UInt8 {
    let s = xs.sorted()
    return s[s.count / 2]
}
let orangeR = median(oranges.map { $0.0 })
let orangeG = median(oranges.map { $0.1 })
let orangeB = median(oranges.map { $0.2 })
let orangeLuma = luma(orangeR, orangeG, orangeB)
let blackLuma = 0.0
FileHandle.standardError.write(Data(String(
    format: "• màu cam lấy mẫu (trung vị %d điểm đặc, sáng): #%02X%02X%02X\n",
    oranges.count, orangeR, orangeG, orangeB).utf8))

// ── 2. Mặt nạ chữ V + vạch sóng + chấm: alpha = chuẩn hoá (luma_cam−luma_điểm)/(luma_cam−luma_đen) ─
var maskAlpha = [UInt8](repeating: 0, count: W * H)
var minX = W, maxX = -1, minY = H, maxY = -1
var sumX = 0.0, sumY = 0.0, sumW = 0.0
for y in 0..<H {
    for x in 0..<W {
        let i = y * W + x
        let o = i * 4
        guard srcPixels[o + 3] == 255 else { continue }
        let r = srcPixels[o], g = srcPixels[o + 1], b = srcPixels[o + 2]
        let l = luma(r, g, b)
        var mAlpha = (orangeLuma - l) / (orangeLuma - blackLuma)
        mAlpha = min(1, max(0, mAlpha))
        // Ngưỡng + kéo giãn tương phản: bỏ nhiễu nén PNG rất nhỏ trên nền cam phẳng (lệch luma ~±1–3
        // quanh orangeLuma, tương đương mAlpha nhiễu ~1–3%) để không lộ viền mờ của vòng tròn gốc,
        // đồng thời giữ biên chữ V/vạch sóng sắc nét (biên thật chuyển luma rất nhanh, xem probe).
        let noiseFloor = 0.08
        mAlpha = mAlpha <= noiseFloor ? 0 : min(1, (mAlpha - noiseFloor) / (1 - noiseFloor))
        let v = UInt8(mAlpha * 255)
        maskAlpha[i] = v
        if v > 127 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        if mAlpha > 0 {
            sumX += Double(x) * mAlpha
            sumY += Double(y) * mAlpha
            sumW += mAlpha
        }
    }
}
guard maxX >= minX, maxY >= minY, sumW > 0 else { fail("không tách được mặt nạ chữ V") }
let bboxW = Double(maxX - minX + 1)
let bboxH = Double(maxY - minY + 1)
let centroidX = sumX / sumW
let centroidY = sumY / sumW
FileHandle.standardError.write(Data(String(
    format: "• bbox chữ V (mask>50%%): %.0f×%.0fpx (canvas %d), tâm khối lượng (%.1f, %.1f)\n",
    bboxW, bboxH, W, centroidX, centroidY).utf8))

// Ảnh mặt nạ dùng để vẽ đè: RGB đen tuyệt đối, alpha = maskAlpha (premultiplied == straight vì RGB=0).
var maskPixels = [UInt8](repeating: 0, count: W * H * 4)
for i in 0..<(W * H) {
    maskPixels[i * 4 + 3] = maskAlpha[i]
}
guard let maskCtx = CGContext(data: &maskPixels, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                               space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let maskImage = maskCtx.makeImage() else {
    fail("không tạo được ảnh mặt nạ")
}

// ── 3. Canvas 1024, ô bo góc squircle 824 ở giữa (lề 100px theo lưới biểu tượng Apple), tô cam ────
// QUAN TRỌNG: một siêu elip (Lamé curve) đơn giản |x|^n+|y|^n=1, dù hiệu chỉnh n để khớp bán kính
// góc trung bình, VẪN bị macOS Tahoe (26) tự thêm "tấm nền xám" phía sau (kiểm bằng
// NSWorkspace.icon(forFile:), xem báo cáo) — đường cong "continuous corner" thật của Apple không
// phải Lamé curve. profileFraction dưới đây là bán kính chuẩn hoá (r/r(0°)) đo trực tiếp (dò nhị
// phân điểm alpha=50%) từ 0° đến 45°, bước 0.5°, trên icon hệ thống thực (ô bo góc chuẩn macOS,
// không phải hình minh hoạ của ứng dụng đó) — xác nhận: dùng đúng đường cong này thì KHÔNG còn bị
// thêm nền xám (siêu elip xấp xỉ, dù tỉ lệ bán kính góc đo được đúng ≈22,37%, vẫn bị thêm).
let profileFraction: [Double] = [
    1.00000, 1.00004, 1.00015, 1.00034, 1.00061, 1.00095,
    1.00137, 1.00187, 1.00244, 1.00309, 1.00382, 1.00463,
    1.00551, 1.00647, 1.00751, 1.00863, 1.00983, 1.01111,
    1.01246, 1.01391, 1.01543, 1.01703, 1.01872, 1.02049,
    1.02234, 1.02428, 1.02630, 1.02842, 1.03061, 1.03290,
    1.03528, 1.03774, 1.04030, 1.04295, 1.04569, 1.04853,
    1.05146, 1.05449, 1.05762, 1.06085, 1.06418, 1.06761,
    1.07115, 1.07479, 1.07853, 1.08239, 1.08636, 1.09044,
    1.09464, 1.09895, 1.10338, 1.10793, 1.11260, 1.11740,
    1.12123, 1.12467, 1.12984, 1.13516, 1.14060, 1.14342,
    1.14914, 1.15501, 1.15821, 1.16436, 1.16783, 1.17142,
    1.17801, 1.18189, 1.18590, 1.19004, 1.19377, 1.19581,
    1.20037, 1.20373, 1.20693, 1.20890, 1.21099, 1.21320,
    1.21553, 1.21799, 1.22058, 1.22330, 1.22344, 1.22585,
    1.22581, 1.22726, 1.22911, 1.22929, 1.22957, 1.22994,
    1.23042,
] // 91 điểm, góc = index × 0,5°, 0..45° (đối xứng 8 phần dựng lại toàn hình trong vòng lặp dưới)

func profileRadiusFraction(angleDeg: Double) -> Double {
    var qAngle = angleDeg.truncatingRemainder(dividingBy: 90)
    if qAngle < 0 { qAngle += 90 }
    let folded = qAngle > 45 ? (90 - qAngle) : qAngle
    let posF = folded / 0.5
    let i0 = min(90, max(0, Int(posF)))
    let i1 = min(90, i0 + 1)
    let t = posF - Double(i0)
    return profileFraction[i0] * (1 - t) + profileFraction[i1] * t
}

let canvasPx = 1024
let squircleSide: CGFloat = 824

guard let outCtx = CGContext(data: nil, width: canvasPx, height: canvasPx, bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("không tạo được context ra")
}
outCtx.interpolationQuality = .high

let halfSide = squircleSide / 2
let cx0 = CGFloat(canvasPx) / 2
let cy0 = CGFloat(canvasPx) / 2
let path = CGMutablePath()
let steps = 1440
for i in 0...steps {
    let thetaDeg = Double(i) / Double(steps) * 360
    let thetaRad = thetaDeg * Double.pi / 180
    let r = profileRadiusFraction(angleDeg: thetaDeg) * Double(halfSide)
    let x = cx0 + CGFloat(r * cos(thetaRad))
    let y = cy0 + CGFloat(r * sin(thetaRad))
    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
}
path.closeSubpath()

outCtx.setFillColor(red: CGFloat(orangeR) / 255, green: CGFloat(orangeG) / 255, blue: CGFloat(orangeB) / 255, alpha: 1)
outCtx.addPath(path)
outCtx.fillPath()

// ── 4. Vẽ đè chữ V đen (từ mặt nạ) lên nền cam mới, co theo glyphWidthFraction, căn theo tâm khối lượng ─
let targetWidth = squircleSide * CGFloat(glyphWidthFraction)
let scale = targetWidth / CGFloat(bboxW)
let destSide = CGFloat(canvasPx) * scale
let destX = cx0 - CGFloat(centroidX) * scale
let destY = cy0 - CGFloat(centroidY) * scale
let destRect = CGRect(x: destX, y: destY, width: destSide, height: destSide)
outCtx.draw(maskImage, in: destRect)

guard let finalImage = outCtx.makeImage() else { fail("không tạo được ảnh ra") }
let rep = NSBitmapImageRep(cgImage: finalImage)
guard let data = rep.representation(using: .png, properties: [:]) else { fail("không mã hoá PNG") }
try? data.write(to: URL(fileURLWithPath: outPath))

FileHandle.standardError.write(Data(String(
    format: "• tỉ lệ rộng chữ V: %.1f%% cạnh squircle (%.0fpx / %.0fpx)\n",
    glyphWidthFraction * 100, targetWidth, squircleSide).utf8))
print("Đã sinh \(outPath)")
