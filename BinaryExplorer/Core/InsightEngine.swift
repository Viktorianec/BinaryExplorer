//
//  InsightEngine.swift
//  BinaryExplorer
//
//  Turns the parsed bundle into the findings a reviewer would actually flag:
//  distribution readiness, binary hygiene, payload weight and privacy posture.
//

import Foundation

enum InsightEngine {

    /// Apple's cellular-download ceiling for App Store downloads.
    static let cellularDownloadLimit: UInt64 = 200 * 1024 * 1024
    /// The uncompressed executable-code limit for a single iOS binary slice.
    static let executableSliceLimit: UInt64 = 60 * 1024 * 1024

    static func evaluate(_ analysis: IPAAnalysis) -> [Insight] {
        var insights: [Insight] = []
        let app = analysis.app

        insights.append(contentsOf: distribution(analysis))
        insights.append(contentsOf: binary(app))
        insights.append(contentsOf: payload(analysis))
        insights.append(contentsOf: privacy(analysis))
        insights.append(contentsOf: configuration(app))

        return insights.sorted { lhs, rhs in
            lhs.level == rhs.level ? lhs.title < rhs.title : lhs.level < rhs.level
        }
    }

    // MARK: Distribution

    private static func distribution(_ analysis: IPAAnalysis) -> [Insight] {
        var result: [Insight] = []
        let app = analysis.app

        if let profile = app.provisioning {
            if profile.isExpired {
                result.append(Insight(level: .critical,
                                      title: "Provisioning profile has expired",
                                      detail: "“\(profile.name)” expired on \(Format.date(profile.expirationDate)). The app will refuse to launch on device until it is re-signed.",
                                      category: "Distribution"))
            } else if let days = profile.daysRemaining, days < 30 {
                result.append(Insight(level: .warning,
                                      title: "Provisioning profile expires in \(days) days",
                                      detail: "“\(profile.name)” is valid until \(Format.date(profile.expirationDate)). Re-sign before it lapses.",
                                      category: "Distribution"))
            }

            switch profile.channel {
            case .development:
                result.append(Insight(level: .warning,
                                      title: "Signed for development",
                                      detail: "The profile provisions \(profile.provisionedDevices.count) specific device(s) and allows debugging. This build cannot be submitted to the App Store.",
                                      category: "Distribution"))
            case .adHoc:
                result.append(Insight(level: .notice,
                                      title: "Ad Hoc distribution build",
                                      detail: "Installable only on the \(profile.provisionedDevices.count) device(s) listed in the profile.",
                                      category: "Distribution"))
            case .enterprise:
                result.append(Insight(level: .notice,
                                      title: "Enterprise (In-House) build",
                                      detail: "Provisions all devices under the organisation's enterprise programme.",
                                      category: "Distribution"))
            case .appStore:
                result.append(Insight(level: .positive,
                                      title: "App Store distribution profile",
                                      detail: "No device list and no debug entitlement — the profile is shaped for App Store or TestFlight delivery.",
                                      category: "Distribution"))
            case .unknown:
                break
            }
        } else {
            result.append(Insight(level: .notice,
                                  title: "No embedded provisioning profile",
                                  detail: "App Store builds downloaded from Apple have the profile stripped and replaced, so this is expected for a store copy.",
                                  category: "Distribution"))
        }

        if let entitlements = app.entitlements {
            if entitlements["get-task-allow"] as? Bool == true {
                result.append(Insight(level: .critical,
                                      title: "Debugging is enabled (get-task-allow)",
                                      detail: "The binary can be attached to by a debugger. App Store review rejects builds carrying this entitlement.",
                                      category: "Security"))
            }
            if let aps = entitlements["aps-environment"] as? String {
                result.append(Insight(level: aps == "production" ? .positive : .warning,
                                      title: "Push environment: \(aps)",
                                      detail: aps == "production"
                                        ? "Push notifications are configured against Apple's production gateway."
                                        : "The build targets the APNs sandbox; production devices will not receive pushes.",
                                      category: "Capabilities"))
            }
        }

        return result
    }

    // MARK: Binary

    private static func binary(_ app: BundleInfo) -> [Insight] {
        var result: [Insight] = []
        guard let slice = app.machO?.primarySlice else {
            result.append(Insight(level: .warning,
                                  title: "Main executable could not be parsed",
                                  detail: "No readable Mach-O header was found at the path named by CFBundleExecutable.",
                                  category: "Binary"))
            return result
        }

        if let encryption = slice.encryption {
            result.append(Insight(level: encryption.isEncrypted ? .notice : .positive,
                                  title: encryption.isEncrypted
                                    ? "FairPlay encrypted (cryptid \(encryption.cryptID))"
                                    : "Not FairPlay encrypted (cryptid 0)",
                                  detail: encryption.isEncrypted
                                    ? "\(Format.bytes(encryption.size)) starting at offset \(encryption.offset) are encrypted. Static analysis of __TEXT requires a decrypted dump from a device."
                                    : "LC_ENCRYPTION_INFO is present but disarmed — this is a pre-store build, so __TEXT is readable as-is.",
                                  category: "Binary"))
        }

        if !slice.isPositionIndependent {
            result.append(Insight(level: .critical,
                                  title: "Binary is not position-independent",
                                  detail: "The MH_PIE flag is missing, so ASLR cannot randomise the image base. Apple requires PIE for submission.",
                                  category: "Security"))
        }

        if slice.textSize > executableSliceLimit {
            result.append(Insight(level: .warning,
                                  title: "__TEXT exceeds the 60 MB slice limit",
                                  detail: "__TEXT is \(Format.bytes(slice.textSize)). Apple caps uncompressed executable code per architecture slice at 60 MB for iOS.",
                                  category: "Binary"))
        }

        if slice.codeSignature == nil {
            result.append(Insight(level: .warning,
                                  title: "No embedded code signature",
                                  detail: "LC_CODE_SIGNATURE is absent or unreadable, so the binary carries no code directory.",
                                  category: "Security"))
        } else if slice.codeSignature?.isAdHoc == true {
            result.append(Insight(level: .warning,
                                  title: "Binary is ad-hoc signed",
                                  detail: "The code directory carries the adhoc flag — there is no CMS signer chain behind it.",
                                  category: "Security"))
        }

        if slice.hasChainedFixups {
            result.append(Insight(level: .positive,
                                  title: "Uses chained fixups",
                                  detail: "LC_DYLD_CHAINED_FIXUPS replaces the classic rebase/bind opcodes, shrinking __LINKEDIT and speeding up launch.",
                                  category: "Binary"))
        }

        let embedded = slice.libraries.filter(\.isEmbedded)
        if embedded.count > 12 {
            result.append(Insight(level: .warning,
                                  title: "\(embedded.count) dynamic frameworks linked at launch",
                                  detail: "Every embedded dylib costs dyld work before main() runs. Merging rarely-changing frameworks into static libraries shortens cold start.",
                                  category: "Performance"))
        }

        if slice.linkedSwift && slice.libraries.contains(where: { $0.path.contains("libswift") }) {
            result.append(Insight(level: .notice,
                                  title: "Ships the Swift runtime",
                                  detail: "The binary links Swift dylibs explicitly rather than relying solely on the OS-provided runtime.",
                                  category: "Binary"))
        }

        return result
    }

    // MARK: Payload

    private static func payload(_ analysis: IPAAnalysis) -> [Insight] {
        var result: [Insight] = []

        if analysis.archiveSize > cellularDownloadLimit {
            result.append(Insight(level: .warning,
                                  title: "Archive exceeds the cellular download limit",
                                  detail: "The .ipa is \(Format.bytes(analysis.archiveSize)). Downloads above 200 MB require Wi-Fi unless the user overrides the setting.",
                                  category: "Size"))
        }

        if let catalog = analysis.app.assetCatalog, catalog.fileSize > 10 * 1024 * 1024 {
            let share = Double(catalog.fileSize) / Double(max(1, analysis.uncompressedSize)) * 100
            result.append(Insight(level: .notice,
                                  title: "Asset catalog is \(Format.bytes(catalog.fileSize))",
                                  detail: String(format: "Assets.car alone is %.0f%% of the unpacked payload%@. App thinning strips unused scales and idioms at delivery time.",
                                                 share,
                                                 catalog.renditionCount.map { " across \($0) renditions" } ?? ""),
                                  category: "Size"))
        }

        let duplicates = duplicateResources(analysis.payloadRoot)
        if let worst = duplicates.first, worst.wastedBytes > 512 * 1024 {
            result.append(Insight(level: .notice,
                                  title: "Duplicated resources detected",
                                  detail: "“\(worst.name)” appears \(worst.count) times, costing about \(Format.bytes(worst.wastedBytes)) in redundant copies.",
                                  category: "Size"))
        }

        let ratio = analysis.compressionRatio
        if ratio > 0.97 {
            result.append(Insight(level: .notice,
                                  title: "Payload is essentially incompressible",
                                  detail: String(format: "The archive is %.0f%% of the unpacked size — most of the bundle is already-compressed media or an encrypted binary.", ratio * 100),
                                  category: "Size"))
        }

        return result
    }

    private struct DuplicateGroup {
        var name: String
        var count: Int
        var wastedBytes: UInt64
    }

    private static func duplicateResources(_ root: FileNode) -> [DuplicateGroup] {
        var buckets: [String: [FileNode]] = [:]
        for file in root.allFiles() where file.size > 64 * 1024 {
            buckets["\(file.name)-\(file.size)", default: []].append(file)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(name: $0[0].name,
                                  count: $0.count,
                                  wastedBytes: $0[0].size * UInt64($0.count - 1)) }
            .sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: Privacy

    private static func privacy(_ analysis: IPAAnalysis) -> [Insight] {
        var result: [Insight] = []
        let app = analysis.app

        if app.privacyManifest == nil {
            result.append(Insight(level: .warning,
                                  title: "App has no PrivacyInfo.xcprivacy",
                                  detail: "\(analysis.privacyManifests.count) manifest(s) ship inside embedded SDKs, but the app target itself declares none. Apple requires a first-party manifest for apps using required-reason APIs.",
                                  category: "Privacy"))
        }

        let trackers = analysis.privacyManifests.filter(\.tracking)
        if !trackers.isEmpty {
            result.append(Insight(level: .notice,
                                  title: "\(trackers.count) SDK manifest(s) declare tracking",
                                  detail: "Declared by: \(trackers.map(\.owner).joined(separator: ", ")). These require App Tracking Transparency consent before use.",
                                  category: "Privacy"))
        }

        if let ats = app.appTransportSecurity {
            if ats["NSAllowsArbitraryLoads"] as? Bool == true {
                result.append(Insight(level: .warning,
                                      title: "App Transport Security is disabled globally",
                                      detail: "NSAllowsArbitraryLoads permits cleartext HTTP to any host and needs a written justification during review.",
                                      category: "Security"))
            } else if let domains = ats["NSExceptionDomains"] as? [String: Any], !domains.isEmpty {
                result.append(Insight(level: .notice,
                                      title: "\(domains.count) ATS exception domain(s)",
                                      detail: "Relaxed transport rules for: \(domains.keys.sorted().joined(separator: ", ")).",
                                      category: "Security"))
            }
        }

        if app.encryptionDeclared == false {
            result.append(Insight(level: .positive,
                                  title: "Export compliance declared",
                                  detail: "ITSAppUsesNonExemptEncryption is false, so App Store Connect will not ask for export documentation on upload.",
                                  category: "Distribution"))
        } else if app.encryptionDeclared == nil {
            result.append(Insight(level: .notice,
                                  title: "No export-compliance key",
                                  detail: "ITSAppUsesNonExemptEncryption is missing, so every upload prompts for an encryption declaration.",
                                  category: "Distribution"))
        }

        return result
    }

    // MARK: Configuration

    private static func configuration(_ app: BundleInfo) -> [Insight] {
        var result: [Insight] = []

        let usage = app.usageDescriptions
        let vague = usage.filter { $0.value.count < 20 }
        if !vague.isEmpty {
            result.append(Insight(level: .warning,
                                  title: "\(vague.count) terse purpose string(s)",
                                  detail: "Short usage descriptions (\(vague.map(\.key).joined(separator: ", "))) are a common review rejection — explain what the app does with the data.",
                                  category: "Configuration"))
        }

        if app.localizations.count > 1 {
            result.append(Insight(level: .positive,
                                  title: "Localized into \(app.localizations.count) languages",
                                  detail: "The App Store listing can advertise: \(app.localizations.joined(separator: ", ")).",
                                  category: "Configuration"))
        }

        if let minimum = app.minimumOS, let major = Int(minimum.split(separator: ".").first.map(String.init) ?? ""),
           major < 15 {
            result.append(Insight(level: .notice,
                                  title: "Deployment target is iOS \(minimum)",
                                  detail: "Supporting older releases widens reach but blocks newer SwiftUI and Swift concurrency APIs.",
                                  category: "Configuration"))
        }

        if !app.backgroundModes.isEmpty {
            result.append(Insight(level: .notice,
                                  title: "Declares background modes",
                                  detail: "UIBackgroundModes: \(app.backgroundModes.joined(separator: ", ")). Each mode must be justified during review.",
                                  category: "Capabilities"))
        }

        return result
    }
}
