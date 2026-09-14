//
//  ProvisioningProfile.swift
//  BinaryExplorer
//
//  Decodes embedded.mobileprovision — a CMS-wrapped property list — and derives
//  the distribution channel from the flags Apple actually ships inside it.
//

import Foundation
import Security

struct ProvisioningProfile {
    enum Channel: String {
        case development = "Development"
        case adHoc = "Ad Hoc"
        case appStore = "App Store"
        case enterprise = "Enterprise (In-House)"
        case unknown = "Unknown"

        var symbol: String {
            switch self {
            case .development: return "hammer.fill"
            case .adHoc: return "person.2.fill"
            case .appStore: return "bag.fill"
            case .enterprise: return "building.2.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    var name: String
    var uuid: String
    var appIDName: String?
    var teamName: String?
    var teamIdentifiers: [String]
    var applicationIdentifier: String?
    var platforms: [String]
    var creationDate: Date?
    var expirationDate: Date?
    var timeToLive: Int?
    var provisionedDevices: [String]
    var provisionsAllDevices: Bool
    var isXcodeManaged: Bool
    var entitlements: [String: Any]
    var certificates: [SigningCertificate]
    var rawPlist: [String: Any]

    var channel: Channel {
        if provisionsAllDevices { return .enterprise }
        if !provisionedDevices.isEmpty {
            let allowsDebug = (entitlements["get-task-allow"] as? Bool) ?? false
            return allowsDebug ? .development : .adHoc
        }
        if entitlements["application-identifier"] != nil { return .appStore }
        return .unknown
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    static func parse(data: Data) -> ProvisioningProfile? {
        guard let plistData = extractPlist(from: data),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
                as? [String: Any] else { return nil }

        let certificates = (plist["DeveloperCertificates"] as? [Data] ?? []).compactMap {
            SecCertificateCreateWithData(nil, $0 as CFData)
        }.map(CodeSignatureParser.describe)

        return ProvisioningProfile(
            name: plist["Name"] as? String ?? "Untitled profile",
            uuid: plist["UUID"] as? String ?? "—",
            appIDName: plist["AppIDName"] as? String,
            teamName: plist["TeamName"] as? String,
            teamIdentifiers: plist["TeamIdentifier"] as? [String] ?? [],
            applicationIdentifier: (plist["Entitlements"] as? [String: Any])?["application-identifier"] as? String,
            platforms: plist["Platform"] as? [String] ?? [],
            creationDate: plist["CreationDate"] as? Date,
            expirationDate: plist["ExpirationDate"] as? Date,
            timeToLive: plist["TimeToLive"] as? Int,
            provisionedDevices: plist["ProvisionedDevices"] as? [String] ?? [],
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            isXcodeManaged: plist["IsXcodeManaged"] as? Bool ?? false,
            entitlements: plist["Entitlements"] as? [String: Any] ?? [:],
            certificates: certificates,
            rawPlist: plist)
    }

    /// Prefers a proper CMS decode; falls back to scanning for the plist markers
    /// when the signature uses an algorithm CMSDecoder declines to parse.
    private static func extractPlist(from data: Data) -> Data? {
        if let content = CodeSignatureParser.cmsContent(data), !content.isEmpty {
            return content
        }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards) else { return nil }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}
