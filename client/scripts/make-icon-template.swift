#!/usr/bin/env swift
// Sinh ảnh TEMPLATE đơn sắc (đen + alpha) cho biểu tượng thanh menu, từ logo-mark.png: mọi điểm ảnh
// có alpha>0 được ép RGB=(0,0,0), giữ nguyên alpha (kể cả alpha trung gian ở viền khử răng cưa) —
// macOS vẽ lại thành TRẮNG trên thanh menu tối, ĐEN trên thanh menu sáng khi `NSImage.isTemplate =
// true` (đặt ở phía Swift gọi, `BrandIcon.swift`, không phải ở đây). Dùng bởi
// client/scripts/make-icon.sh — KHÔNG chạy trực tiếp ngoài script đó.
// dùng: make-icon-template.swift <logo-mark.png vào> <ra-18.png> <ra-36.png> <ra-54.png>
import AppKit
import CoreGraphics

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5 else { fail("dùng: make-icon-template.swift <vào.png> <ra18.png> <ra36.png> <ra54.png>") }
let inPath = args[1]
let outPaths = [args[2], args[3], args[4]]
let outSizes = [18, 36, 54]

guard let input = NSImage(contentsOfFile: inPath),
      let srcCG = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("không đọc được ảnh vào: \(inPath)")
}

let colorSpace = CGColorSpaceCreateDeviceRGB()

for (size, outPath) in zip(outSizes, outPaths) {
    // Vẽ nguồn (co giãn chất lượng cao) vào canvas đích rồi ép RGB=0 ở mọi điểm có alpha>0.
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("không tạo được context \(size)px")
    }
    ctx.interpolationQuality = .high
    ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: size, height: size))
    for i in 0..<(size * size) {
        let o = i * 4
        if pixels[o + 3] > 0 {
            // premultipliedLast: RGB=0 là giá trị hợp lệ duy nhất cho "đen" dù premultiplied hay không.
            pixels[o] = 0
            pixels[o + 1] = 0
            pixels[o + 2] = 0
        }
    }
    guard let outImage = ctx.makeImage() else { fail("không tạo được ảnh ra \(size)px") }
    let rep = NSBitmapImageRep(cgImage: outImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("không mã hoá PNG \(size)px") }
    do {
        try data.write(to: URL(fileURLWithPath: outPath))
    } catch {
        fail("không ghi được \(outPath): \(error)")
    }
}

print("Đã sinh \(outPaths.joined(separator: ", "))")
