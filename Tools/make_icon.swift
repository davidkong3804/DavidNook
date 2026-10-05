#!/usr/bin/env swift
// DavidNook AppIcon generator.
//
// Draws a black rounded-rectangle with a notch cut out of the top edge using
// CoreGraphics only (no external assets) and writes every macOS AppIcon size
// plus Contents.json into the asset catalog.
//
// Usage (from the repository root):
//   swift Tools/make_icon.swift [output-dir]
// Default output: boringNotch/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "boringNotch/Assets.xcassets/AppIcon.appiconset"

// (point size, scale) pairs required by the macOS AppIcon set.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

/// Draws the icon on a 1024x1024 reference canvas, scaled to `pixels`.
func renderIcon(pixels: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let s = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: s, y: s)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Body: Apple's icon grid leaves a 100pt margin on a 1024pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Near-black vertical gradient fill.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1),
            CGColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY),
        options: []
    )
    ctx.restoreGState()

    // Faint inner rim so the black body still reads on dark backgrounds.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerWidth: 182, cornerHeight: 182, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // Notch: a bite out of the top edge, rounded at its lower corners. It
    // starts above the body edge so the cut is flush with the top.
    let notchWidth: CGFloat = 320
    let notchHeight: CGFloat = 112
    let radius: CGFloat = 52
    let notchRect = CGRect(
        x: 512 - notchWidth / 2,
        y: body.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight + 24
    )
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

    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.addPath(notchPath)
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return false }
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
