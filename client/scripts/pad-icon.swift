#!/usr/bin/env swift
// Thu nhỏ một ảnh vuông vào vùng an toàn ở giữa canvas vuông (đúng chuẩn lưới biểu tượng macOS),
// giữ nền trong suốt. Dùng bởi client/scripts/make-icon.sh — KHÔNG chạy trực tiếp.
// dùng: pad-icon.swift <ảnh vào.png> <ảnh ra.png> <canvas px> <tỉ lệ an toàn 0-1>
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 5,
      let canvasPx = Int(CommandLine.arguments[3]),
      let safeFraction = Double(CommandLine.arguments[4]) else {
    FileHandle.standardError.write(Data("dùng: pad-icon.swift <vào.png> <ra.png> <canvas px> <tỉ lệ an toàn>\n".utf8))
    exit(64)
}
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

guard let input = NSImage(contentsOfFile: inPath), let inputCG = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("không đọc được ảnh vào: \(inPath)\n".utf8))
    exit(1)
}

let canvas = CGFloat(canvasPx)
guard let ctx = CGContext(data: nil, width: canvasPx, height: canvasPx, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("không tạo được context\n".utf8))
    exit(1)
}
let logoSide = canvas * CGFloat(safeFraction)
let origin = (canvas - logoSide) / 2
ctx.interpolationQuality = .high
ctx.draw(inputCG, in: CGRect(x: origin, y: origin, width: logoSide, height: logoSide))

guard let outputImage = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: outputImage)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: outPath))
print("Đã thu nhỏ \(inPath) vào vùng an toàn \(Int(safeFraction * 100))% canvas \(canvasPx)px → \(outPath)")
