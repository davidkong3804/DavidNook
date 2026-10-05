#!/usr/bin/env swift
// DavidNook AppIcon generator.
//
// 以 CoreGraphics 向量繪製（沒有任何外部素材，也不使用任何其他 App 的設計）：
//   - 深色圓角方形底（macOS 圖示網格：1024 畫布留 100 邊距，主體 824）
//   - 頂端黑色瀏海（由上緣垂下，下方兩角圓弧）
//   - 瀏海下方的「歌詞行」：五條圓角長條，目前這一行用暖色漸層，左側帶一個音符
// 尺寸 16–1024（@1x／@2x）全部輸出並寫入 Contents.json。小於 64 px 時改用簡化版（瀏海＋三條），避免糊成一團。
//
// 用法（在專案根目錄）：
//   swift Tools/make_icon.swift [輸出目錄] [--preview <1024 預覽 PNG 路徑>]
// 預設輸出目錄：boringNotch/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var outputDir = "boringNotch/Assets.xcassets/AppIcon.appiconset"
var previewPath: String?
do {
    var args = Array(CommandLine.arguments.dropFirst())
    while let arg = args.first {
        args.removeFirst()
        if arg == "--preview", let path = args.first {
            previewPath = path
            args.removeFirst()
        } else {
            outputDir = arg
        }
    }
}

// macOS AppIcon 需要的 (點數尺寸, 倍率)。
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func capsule(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
}

/// 八分音符，畫在以 (cx, cy) 為音符頭中心、`size` 為整體高度的位置。
func notePath(cx: CGFloat, cy: CGFloat, size: CGFloat) -> CGPath {
    let u = size / 100
    let path = CGMutablePath()
    // 音符頭：略微傾斜的橢圓
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: .pi / 9)
    path.addEllipse(in: CGRect(x: -27 * u, y: -19 * u, width: 54 * u, height: 38 * u), transform: t)
    // 符桿
    let stemX = cx + 21 * u
    path.addRect(CGRect(x: stemX, y: cy + 4 * u, width: 9 * u, height: 92 * u))
    // 符尾
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: stemX + 9 * u, y: cy + 96 * u))
    flag.addCurve(
        to: CGPoint(x: stemX + 46 * u, y: cy + 46 * u),
        control1: CGPoint(x: stemX + 12 * u, y: cy + 72 * u),
        control2: CGPoint(x: stemX + 52 * u, y: cy + 70 * u)
    )
    flag.addCurve(
        to: CGPoint(x: stemX + 9 * u, y: cy + 70 * u),
        control1: CGPoint(x: stemX + 40 * u, y: cy + 62 * u),
        control2: CGPoint(x: stemX + 22 * u, y: cy + 62 * u)
    )
    flag.closeSubpath()
    path.addPath(flag)
    t = .identity
    return path
}

/// 在 1024×1024 的參考畫布上繪製，再縮放成 `pixels`。
func renderIcon(pixels: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let s = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: s, y: s)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    let detailed = pixels >= 64

    // 主體
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 主體下方的柔和陰影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 深色石墨藍漸層底
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(0.19, 0.21, 0.27), color(0.07, 0.08, 0.11)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY),
        options: []
    )

    // 瀏海：從上緣垂下的黑色形狀（畫在主體裡，上緣超出一點以確保貼齊）
    let notchWidth: CGFloat = 330
    let notchHeight: CGFloat = 112
    let radius: CGFloat = 56
    let notchRect = CGRect(x: 512 - notchWidth / 2, y: body.maxY - notchHeight, width: notchWidth, height: notchHeight + 30)
    let notchPath = CGMutablePath()
    notchPath.move(to: CGPoint(x: notchRect.minX, y: notchRect.maxY))
    notchPath.addLine(to: CGPoint(x: notchRect.minX, y: notchRect.minY + radius))
    notchPath.addArc(
        tangent1End: CGPoint(x: notchRect.minX, y: notchRect.minY),
        tangent2End: CGPoint(x: notchRect.minX + radius, y: notchRect.minY),
        radius: radius
    )
    notchPath.addLine(to: CGPoint(x: notchRect.maxX - radius, y: notchRect.minY))
    notchPath.addArc(
        tangent1End: CGPoint(x: notchRect.maxX, y: notchRect.minY),
        tangent2End: CGPoint(x: notchRect.maxX, y: notchRect.minY + radius),
        radius: radius
    )
    notchPath.addLine(to: CGPoint(x: notchRect.maxX, y: notchRect.maxY))
    notchPath.closeSubpath()
    ctx.addPath(notchPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    // 瀏海下緣一圈很淡的亮邊，讓它在深色底上仍可辨識
    ctx.addPath(notchPath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
    ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()

    // 主體的內緣細亮邊
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerWidth: 182, cornerHeight: 182, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // 歌詞行
    let left: CGFloat = detailed ? 276 : 240
    struct Line { let y: CGFloat; let width: CGFloat; let height: CGFloat; let alpha: CGFloat; let current: Bool }
    let lines: [Line] = detailed
        ? [
            Line(y: 640, width: 400, height: 48, alpha: 0.14, current: false),
            Line(y: 545, width: 510, height: 48, alpha: 0.28, current: false),
            Line(y: 436, width: 470, height: 72, alpha: 1, current: true),
            Line(y: 327, width: 540, height: 48, alpha: 0.28, current: false),
            Line(y: 232, width: 330, height: 48, alpha: 0.14, current: false),
        ]
        : [
            Line(y: 600, width: 520, height: 96, alpha: 0.30, current: false),
            Line(y: 440, width: 560, height: 130, alpha: 1, current: true),
            Line(y: 280, width: 440, height: 96, alpha: 0.30, current: false),
        ]
    for line in lines {
        let rect = CGRect(x: left, y: line.y - line.height / 2, width: line.width, height: line.height)
        ctx.saveGState()
        if line.current {
            ctx.setShadow(offset: .zero, blur: 40, color: color(1.0, 0.45, 0.35, 0.55))
            ctx.addPath(capsule(rect))
            ctx.clip()
            let accent = CGGradient(
                colorsSpace: space,
                colors: [color(1.00, 0.40, 0.45), color(1.00, 0.68, 0.34)] as CFArray,
                locations: [0, 1]
            )!
            ctx.drawLinearGradient(accent, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        } else {
            ctx.addPath(capsule(rect))
            ctx.setFillColor(CGColor(gray: 1, alpha: line.alpha))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // 目前這一行左邊的音符（只在較大的尺寸畫）
    if detailed {
        ctx.saveGState()
        ctx.addPath(notePath(cx: 176, cy: 400, size: 104))
        ctx.setFillColor(color(1.00, 0.55, 0.40))
        ctx.fillPath()
        ctx.restoreGState()
    }

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for v in variants {
    let pixels = v.points * v.scale
    let name = "icon_\(v.points)x\(v.points)@\(v.scale)x.png"
    guard let image = renderIcon(pixels: pixels),
          writePNG(image, to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
    else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    images.append([
        "filename": name, "idiom": "mac",
        "scale": "\(v.scale)x", "size": "\(v.points)x\(v.points)",
    ])
}

let contents: [String: Any] = ["images": images, "info": ["author": "make_icon.swift", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent("Contents.json"))
print("wrote \(variants.count) icons to \(outputDir)")

if let previewPath {
    guard let image = renderIcon(pixels: 1024), writePNG(image, to: URL(fileURLWithPath: previewPath)) else {
        FileHandle.standardError.write(Data("failed to render preview\n".utf8))
        exit(1)
    }
    print("wrote 1024 preview to \(previewPath)")
}
