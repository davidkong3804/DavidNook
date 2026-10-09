import Foundation
import Security

/// 以 Security.framework 讀取 .app 的簽章與 entitlements（不啟動 `codesign` 行程，沙盒內也能用）。
public struct SecurityAppBundleInspector: AppBundleInspecting {
    /// `kSecCodeSignatureRuntime`（Hardened Runtime）。
    private static let runtimeFlag: UInt32 = 0x10000

    public init() {}

    public func inspect(appAt url: URL) throws -> AppBundleFacts {
        // Info.plist
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw UpdateVerificationFailure.unreadable("Contents/Info.plist")
        }

        // 架構
        var architectures: [String] = []
        if let bundle = Bundle(url: url), let archs = bundle.executableArchitectures {
            for number in archs {
                switch number.intValue {
                case 0x0100000C: architectures.append("arm64")
                case 0x01000007: architectures.append("x86_64")
                case let other: architectures.append("cputype-\(other)")
                }
            }
        }

        // 簽章
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard created == errSecSuccess, let code = staticCode else {
            throw UpdateVerificationFailure.unreadable("SecStaticCodeCreateWithPath (OSStatus \(created))")
        }
        var signatureError: String?
        var cfError: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &cfError)
        if status != errSecSuccess {
            let detail = cfError?.takeRetainedValue().localizedDescription
            signatureError = detail ?? "OSStatus \(status)"
        } else {
            cfError?.release()
        }

        // 簽章資訊（flags、entitlements）
        var hardened = false
        var entitlements: [String: EntitlementValue] = [:]
        var info: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dict = info as? [String: Any] {
            if let value = dict[kSecCodeInfoFlags as String] as? NSNumber { hardened = value.uint32Value & Self.runtimeFlag != 0 }
            if let ents = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
                for (key, value) in ents { entitlements[key] = Self.convert(value) }
            }
        }

        return AppBundleFacts(
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            shortVersion: plist["CFBundleShortVersionString"] as? String,
            architectures: architectures, signatureError: signatureError,
            hardenedRuntime: hardened, entitlements: entitlements
        )
    }

    static func convert(_ value: Any) -> EntitlementValue {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        if let string = value as? String { return .string(string) }
        if let array = value as? [Any] { return .array(array.map(convert)) }
        return .other(String(describing: value))
    }
}
