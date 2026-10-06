import Foundation

/// 縮小取樣後的一幀亮度（0…255，列優先）。像素只在記憶體裡短暫存在，偵測完即丟。
public struct LumaFrame: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    /// 由 BGRA 緩衝縮小取樣（點取樣）成 `targetWidth × targetHeight` 的亮度圖。輸入無效回傳 nil。
    public static func fromBGRA(
        baseAddress: UnsafeRawPointer, byteCount: Int, width: Int, height: Int, bytesPerRow: Int,
        targetWidth: Int, targetHeight: Int
    ) -> LumaFrame? {
        guard width > 0, height > 0, targetWidth > 0, targetHeight > 0, bytesPerRow >= width * 4,
              byteCount >= bytesPerRow * (height - 1) + width * 4 else { return nil }
        let p = baseAddress.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        for ty in 0..<targetHeight {
            let y = min(height - 1, (ty * height) / targetHeight + height / (2 * targetHeight))
            for tx in 0..<targetWidth {
                let x = min(width - 1, (tx * width) / targetWidth + width / (2 * targetWidth))
                let i = y * bytesPerRow + x * 4
                let luma = 0.114 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.299 * Double(p[i + 2])
                out[ty * targetWidth + tx] = UInt8(min(max(luma.rounded(), 0), 255))
            }
        }
        return LumaFrame(width: targetWidth, height: targetHeight, pixels: out)
    }
}

/// 自動偵測影片區域（純函式）：對多幀小圖逐像素累積「變動次數」，取變動最大的連通區域的外接矩形。
///
/// 原理：影片播放區域每幀都在變，網頁其他部分（網址列、標題、留言、推薦）大多靜止。
/// 1. 相鄰兩幀亮度差 > `noiseThreshold` 才算「這個像素變了」（壓縮雜訊、抗鋸齒閃爍不算）。
/// 2. 變動次數 ≥ 相鄰幀對數的 `activeFraction` 才算「活躍像素」。
/// 3. 活躍像素膨脹 1 格後做 4 連通標記，取活躍像素最多的連通區域；外接矩形用區域內原始活躍像素算（不含膨脹）。
/// 4. 拒絕：區域太小（活躍像素 < 畫面 `minimumAreaFraction` 或邊長 < 0.1）、外接矩形幾乎整個視窗（寬、高都 ≥ `fullWindowFraction`，例如整頁捲動或全螢幕）。
/// 找不到就回傳 nil——呼叫端顯示說明，不亂框。
///
/// 限制：影片暫停／靜止畫面偵測不到；小畫面或只有局部在動的影片可能框不全；旁邊有大面積動態（動畫廣告）可能框到別處——使用者可手動微調。
public enum VideoRegionDetector {
    public static let noiseThreshold = 12
    public static let activeFraction = 0.4
    public static let minimumFrames = 4
    public static let minimumAreaFraction = 0.02
    public static let minimumSide = 0.1
    public static let fullWindowFraction = 0.92

    public static func detect(frames: [LumaFrame]) -> NormalizedCropRect? {
        guard frames.count >= minimumFrames, let first = frames.first, first.width >= 8, first.height >= 8 else { return nil }
        let w = first.width, h = first.height
        guard frames.allSatisfy({ $0.width == w && $0.height == h && $0.pixels.count == w * h }) else { return nil }

        let pairs = frames.count - 1
        var changes = [Int](repeating: 0, count: w * h)
        for k in 0..<pairs {
            let a = frames[k].pixels, b = frames[k + 1].pixels
            for i in 0..<(w * h) where abs(Int(a[i]) - Int(b[i])) > noiseThreshold { changes[i] += 1 }
        }
        let needed = Int((Double(pairs) * activeFraction).rounded(.up))
        let active = changes.map { $0 >= max(needed, 1) }

        // 膨脹 1 格（把影片內部靜止的小縫隙接起來）。
        var dilated = active
        for y in 0..<h { for x in 0..<w where active[y * w + x] {
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < w, ny >= 0, ny < h { dilated[ny * w + nx] = true }
            } }
        } }

        // 4 連通標記（迭代 flood fill），挑活躍像素最多的區域。
        var visited = [Bool](repeating: false, count: w * h)
        var best: (count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)?
        var stack: [Int] = []
        for start in 0..<(w * h) where dilated[start] && !visited[start] {
            var count = 0, minX = w, minY = h, maxX = -1, maxY = -1
            visited[start] = true
            stack.append(start)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                if active[i] {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
                if x > 0, dilated[i - 1], !visited[i - 1] { visited[i - 1] = true; stack.append(i - 1) }
                if x < w - 1, dilated[i + 1], !visited[i + 1] { visited[i + 1] = true; stack.append(i + 1) }
                if y > 0, dilated[i - w], !visited[i - w] { visited[i - w] = true; stack.append(i - w) }
                if y < h - 1, dilated[i + w], !visited[i + w] { visited[i + w] = true; stack.append(i + w) }
            }
            if count > (best?.count ?? 0) { best = (count, minX, minY, maxX, maxY) }
        }
        guard let best, best.maxX >= best.minX else { return nil }

        let rw = Double(best.maxX - best.minX + 1) / Double(w)
        let rh = Double(best.maxY - best.minY + 1) / Double(h)
        guard Double(best.count) >= minimumAreaFraction * Double(w * h), rw >= minimumSide, rh >= minimumSide else { return nil }
        guard !(rw >= fullWindowFraction && rh >= fullWindowFraction) else { return nil }
        return NormalizedCropRect(x: Double(best.minX) / Double(w), y: Double(best.minY) / Double(h), width: rw, height: rh).sanitized
    }
}
