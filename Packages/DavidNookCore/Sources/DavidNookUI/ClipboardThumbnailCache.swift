import AppKit
import ImageIO

/// 剪貼簿圖片縮圖：在背景用 ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` 產生，並放進有上限的記憶體快取。
///
/// 為什麼這樣做：Core 把圖片存成原圖檔（可到 20MB），而面板只需要一個小方塊。
/// - **原圖不會進入 SwiftUI 狀態**：視圖只持有縮圖（最長邊 `maxPixelSize` 像素，預設 96）；
///   原圖只由 ImageIO 以檔案 URL 開啟，縮圖產生完就釋放，沒有任何地方把整張圖讀成 `Data`／`NSImage` 保存。
/// - 產生工作在 `Task.detached(priority: .utility)` 執行，不卡主執行緒；同一個檔案同時被多列要求時只做一次。
/// - 記憶體快取用 `NSCache`：`countLimit`（預設 120 張）與 `totalCostLimit`（預設 8MB，成本＝寬×高×4）兩道上限，
///   系統記憶體吃緊時 NSCache 也會自行清掉。
/// - 超過 `maxSourcePixels`（預設 1 億像素）的來源不解碼（避免「壓縮炸彈」類圖片把記憶體吃光），回傳 nil，
///   列表改顯示佔位圖示，貼回功能不受影響。
public final class ClipboardThumbnailCache: @unchecked Sendable {
    /// 縮圖最長邊（像素）；列表以 2x 顯示約 48pt。
    public static let defaultMaxPixelSize = 96
    /// 快取張數上限。
    public static let defaultCountLimit = 120
    /// 快取總成本上限（位元組，成本＝寬×高×4）。
    public static let defaultTotalCostLimit = 8 * 1024 * 1024
    /// 來源圖片像素數上限。
    public static let defaultMaxSourcePixels = 100_000_000

    public let maxPixelSize: Int
    public let countLimit: Int
    public let totalCostLimit: Int
    public let maxSourcePixels: Int

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    public init(
        maxPixelSize: Int = ClipboardThumbnailCache.defaultMaxPixelSize,
        countLimit: Int = ClipboardThumbnailCache.defaultCountLimit,
        totalCostLimit: Int = ClipboardThumbnailCache.defaultTotalCostLimit,
        maxSourcePixels: Int = ClipboardThumbnailCache.defaultMaxSourcePixels
    ) {
        self.maxPixelSize = maxPixelSize
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.maxSourcePixels = maxSourcePixels
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// 只查記憶體快取（同步、不碰磁碟）。
    public func cachedThumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    /// 取得縮圖：快取命中直接回傳，否則在背景產生並放進快取。檔案不存在或無法解碼回傳 nil。
    public func thumbnail(for url: URL) async -> NSImage? {
        let key = url.path
        if let hit = cache.object(forKey: key as NSString) { return hit }

        let task: Task<NSImage?, Never> = lock.withLock {
            if let running = inflight[key] { return running }
            let maxPixelSize = maxPixelSize
            let maxSourcePixels = maxSourcePixels
            let created = Task.detached(priority: .utility) { [weak self] () -> NSImage? in
                let image = Self.makeThumbnail(url: url, maxPixelSize: maxPixelSize, maxSourcePixels: maxSourcePixels)
                if let image, let self {
                    self.cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                }
                self?.lock.withLock { self?.inflight[key] = nil }
                return image
            }
            inflight[key] = created
            return created
        }
        return await task.value
    }

    /// 清空記憶體快取（例如使用者按「清除全部」之後）。
    public func removeAll() {
        cache.removeAllObjects()
    }

    // MARK: 產生縮圖

    /// 用 ImageIO 由檔案 URL 直接產生縮圖（最長邊 ≤ `maxPixelSize` 像素，保留比例，套用 EXIF 方向）。
    /// 回傳的 `NSImage` 尺寸以 2x 為準（點數＝像素／2）。
    static func makeThumbnail(url: URL, maxPixelSize: Int, maxSourcePixels: Int) -> NSImage? {
        // kCGImageSourceShouldCache=false：不讓 ImageIO 長期保留解碼後的原圖。
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }

        // 先讀尺寸（不解碼像素），過大的來源直接放棄。
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue > maxSourcePixels
            || width.multipliedReportingOverflow(by: height).overflow {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,   // 一律由原圖縮，不採用內嵌的（可能很小的）縮圖
            kCGImageSourceCreateThumbnailWithTransform: true,     // 套用 EXIF 方向
            kCGImageSourceShouldCacheImmediately: true,           // 在背景執行緒就完成解碼，不留到主執行緒繪製時
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: Double(cgImage.width) / 2, height: Double(cgImage.height) / 2))
    }

    private static func cost(of image: NSImage) -> Int {
        // 點數×2＝像素；RGBA 每像素 4 位元組。
        Int(image.size.width * 2) * Int(image.size.height * 2) * 4
    }
}
