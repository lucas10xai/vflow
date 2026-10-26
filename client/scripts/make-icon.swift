#!/usr/bin/env swift
// Vẽ biểu tượng vflow bằng CoreGraphics (không tài nguyên bên ngoài, không bản quyền lạ):
// nền vuông bo tối #0d0d12, hình micro + vài vạch sóng âm màu cam #f37021.
// Dùng bởi client/scripts/make-icon.sh — KHÔNG chạy trực tiếp (cần tham số thư mục xuất).
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("dùng: make-icon.swift <thư mục .iconset>\n".utf8))
    exit(64)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let bg = CGColor(red: 0x0d / 255.0, green: 0x0d / 255.0, blue: 0x12 / 255.0, alpha: 1)
let fg = CGColor(red: 0xf3 / 255.0, green: 0x70 / 255.0, blue: 0x21 / 255.0, alpha: 1)

/// Vẽ icon kích thước `size` px vào `path` (PNG).
func drawIcon(size: Int, path: String) {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        FileHandle.standardError.write(Data("không tạo được context cho \(size)px\n".utf8))
        exit(1)
    }

    // Nền vuông bo (squircle tối giản).
    let radius = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(bg)
    ctx.fillPath()

    // Thân micro: viên nhộng dọc ở giữa phía trên.
    let capsuleWidth = s * 0.22
    let capsuleHeight = s * 0.40
    let capsuleX = (s - capsuleWidth) / 2
    let capsuleY = s * 0.40
    let capsuleRect = CGRect(x: capsuleX, y: capsuleY, width: capsuleWidth, height: capsuleHeight)
    let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: capsuleWidth / 2, cornerHeight: capsuleWidth / 2, transform: nil)
    ctx.addPath(capsulePath)
    ctx.setFillColor(fg)
    ctx.fillPath()

    // Chân đế + cần micro: vòng cung hở dưới thân, cộng một chân thẳng.
    let standWidth = s * 0.045
    let standX = (s - standWidth) / 2
    let standTop = capsuleY - s * 0.01
    let standBottom = s * 0.20
    ctx.setStrokeColor(fg)
    ctx.setLineWidth(standWidth)
    ctx.setLineCap(.round)
    let archRadius = capsuleWidth * 0.95
    let archCenter = CGPoint(x: s / 2, y: capsuleY + archRadius * 0.15)
    ctx.addArc(center: archCenter, radius: archRadius, startAngle: CGFloat.pi * 1.15, endAngle: CGFloat.pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: standX + standWidth / 2, y: standTop - archRadius * 0.3))
    ctx.addLine(to: CGPoint(x: standX + standWidth / 2, y: standBottom))
    ctx.strokePath()
    let baseWidth = s * 0.16
    ctx.move(to: CGPoint(x: s / 2 - baseWidth / 2, y: standBottom))
    ctx.addLine(to: CGPoint(x: s / 2 + baseWidth / 2, y: standBottom))
    ctx.strokePath()

    // Vài vạch sóng âm hai bên micro.
    let barWidth = s * 0.06
    let gap = s * 0.05
    let heights: [CGFloat] = [0.14, 0.24, 0.14]
    for (i, h) in heights.enumerated() {
        let barHeight = s * h
        let barY = capsuleY + (capsuleHeight - barHeight) / 2
        let offset = CGFloat(i + 1) * (barWidth + gap)
        for side: CGFloat in [-1, 1] {
            let barX = s / 2 + side * (capsuleWidth / 2 + offset) - barWidth / 2
            let barRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
            let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            ctx.addPath(barPath)
            ctx.setFillColor(fg.copy(alpha: 0.75) ?? fg)
            ctx.fillPath()
        }
    }

    guard let image = ctx.makeImage() else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
}

// Kích thước chuẩn của một .iconset (xem `iconutil`).
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for s in sizes {
    drawIcon(size: s.px, path: outDir + "/\(s.name).png")
}
print("Đã vẽ \(sizes.count) kích thước vào \(outDir)")
