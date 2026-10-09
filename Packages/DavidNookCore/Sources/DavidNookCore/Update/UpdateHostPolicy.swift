import Foundation

/// 自動更新允許連線的主機白名單。只有使用者按下「檢查更新」後才會用到；一律 https、預設連接埠、不帶帳密。
public enum UpdateHostPolicy {
    /// 精確比對的主機。
    public static let exactHosts: Set<String> = [
        "api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]
    /// 子網域後綴（`*.githubusercontent.com`；不含裸網域）。
    public static let hostSuffixes: [String] = [".githubusercontent.com"]

    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), !host.isEmpty
        else { return false }
        if exactHosts.contains(host) { return true }
        return hostSuffixes.contains { host.hasSuffix($0) && host.count > $0.count }
    }

    /// HTTP 重新導向目的地是否可接受（與初始請求同一份白名單）。
    public static func allowsRedirect(to url: URL) -> Bool { isAllowed(url) }
}
