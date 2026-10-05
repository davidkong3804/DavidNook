import AppKit
import SwiftUI
import XCTest

// 所有渲染用的歌詞文字皆為自編句子，不含任何受版權保護的真實歌詞。

/// 黑色圓角「瀏海風格」底：上緣小圓角、下緣大圓角，外面墊一層淺灰方便看出輪廓。
struct NotchBackdrop<Content: View>: View {
    var size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(white: 0.82)
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 8)
                .fill(Color.black)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            content()
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 把 SwiftUI 視圖離屏渲染成 CGImage（scale 2）。
@MainActor
func renderImage<V: View>(_ view: V, scale: CGFloat = 2) throws -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = true
    guard let image = renderer.cgImage else {
        throw XCTSkip("ImageRenderer 在此環境無法渲染（cgImage 為 nil）")
    }
    return image
}

func pngData(_ image: CGImage) throws -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 編碼失敗"])
    }
    return data
}

/// 快照輸出目錄：環境變數 DAVIDNOOK_SNAPSHOT_DIR，否則暫存目錄。
func snapshotDirectory() throws -> URL {
    let path = ProcessInfo.processInfo.environment["DAVIDNOOK_SNAPSHOT_DIR"]
        ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("DavidNookSnapshots")
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
func writeSnapshot(_ image: CGImage, named name: String) throws -> URL {
    let url = try snapshotDirectory().appendingPathComponent(name + ".png")
    try pngData(image).write(to: url)
    return url
}

/// 讀像素的小工具（RGBA8，預乘 alpha 對不透明圖無影響）。
struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        data = buffer
    }

    /// 0…1 的亮度（簡單平均）。
    func luminance(x: Int, y: Int) -> Double {
        let i = (y * width + x) * 4
        return (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / (3 * 255)
    }

    /// 水平帶（含上下界，像素座標，y 由上往下）內的最大亮度。
    func maxLuminance(rows: ClosedRange<Int>) -> Double {
        var best = 0.0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, height - 1) {
            for x in 0..<width { best = max(best, luminance(x: x, y: y)) }
        }
        return best
    }

    /// 亮度超過門檻的像素數。
    func count(rows: ClosedRange<Int>, above threshold: Double) -> Int {
        var n = 0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, height - 1) {
            for x in 0..<width where luminance(x: x, y: y) > threshold { n += 1 }
        }
        return n
    }
}
