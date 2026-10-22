import Foundation
import Security

/// Which signed build is running. Each channel gets its own SQLite file so a
/// development build, TestFlight, and the App Store cannot append into one database.
enum DistributionChannel: String, Sendable, Equatable {
    case development
    case testflight
    case appStore = "app-store"
    case developerID = "developer-id"
    case unknown

    var databaseFileName: String {
        "homesensorplot-\(rawValue).sqlite"
    }

    /// Leaf-certificate summary from codesign, for example
    /// "Apple Development: …" or "TestFlight Beta Distribution".
    static func matching(certificateSummary: String) -> DistributionChannel {
        let summary = certificateSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.range(of: "TestFlight", options: .caseInsensitive) != nil {
            return .testflight
        }
        // "3rd Party Mac Developer" contains "Mac Developer", so distribution checks come first.
        if summary.range(of: "Developer ID", options: .caseInsensitive) != nil {
            return .developerID
        }
        if summary.range(of: "Apple Distribution", options: .caseInsensitive) != nil
            || summary.range(of: "3rd Party Mac Developer", options: .caseInsensitive) != nil
            || summary.range(of: "Mac App Distribution", options: .caseInsensitive) != nil {
            return .appStore
        }
        if summary.range(of: "Apple Development", options: .caseInsensitive) != nil
            || summary.range(of: "iPhone Developer", options: .caseInsensitive) != nil
            || summary.range(of: "Mac Developer", options: .caseInsensitive) != nil {
            return .development
        }
        return .unknown
    }

    static func current(bundle: Bundle = .main) -> DistributionChannel {
        if let summary = leafCertificateSummary(bundle: bundle) {
            let matched = matching(certificateSummary: summary)
            if matched != .unknown {
                return matched
            }
        }
        if bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil {
            return .development
        }
        if let receipt = bundle.appStoreReceiptURL {
            if receipt.lastPathComponent == "sandboxReceipt" {
                return .testflight
            }
            if FileManager.default.fileExists(atPath: receipt.path) {
                return .appStore
            }
        }
        return .unknown
    }

    private static func leafCertificateSummary(bundle: Bundle) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard infoStatus == errSecSuccess, let information else { return nil }
        let info = information as NSDictionary
        guard let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else {
            return nil
        }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }
}
