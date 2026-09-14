//
//  PrivacySection.swift
//  BinaryExplorer
//
//  Purpose strings, App Transport Security, background modes and every
//  PrivacyInfo.xcprivacy manifest in the payload.
//

import SwiftUI

struct PrivacySection: View {
    let analysis: IPAAnalysis

    var body: some View {
        SectionScaffold(title: "Privacy & ATS",
                        subtitle: "\(analysis.app.usageDescriptions.count) purpose strings · \(analysis.privacyManifests.count) privacy manifests",
                        symbol: ExplorerSection.privacy.symbol,
                        tint: ExplorerSection.privacy.tint) {
            usageCard
            atsCard
            capabilitiesCard
            manifestsCard
        }
    }

    // MARK: Purpose strings

    private var usageCard: some View {
        Card(title: "Purpose strings",
             subtitle: "Shown verbatim in the system permission prompt",
             symbol: "text.bubble.fill",
             tint: ExplorerSection.privacy.tint) {
            let entries = analysis.app.usageDescriptions
            if entries.isEmpty {
                Text("The app declares no NS*UsageDescription keys.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries, id: \.key) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Image(systemName: symbol(for: entry.key))
                                    .font(.system(size: 10))
                                    .foregroundStyle(ExplorerSection.privacy.tint)
                                Text(entry.key)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                Text("\(entry.value.count) chars")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(entry.value.count < 20
                                                     ? FileKind.assetCatalog.color : Theme.tertiaryText)
                            }
                            Text("“\(entry.value)”")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func symbol(for key: String) -> String {
        switch key {
        case "NSCameraUsageDescription": return "camera.fill"
        case "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription": return "photo.on.rectangle"
        case "NSMicrophoneUsageDescription": return "mic.fill"
        case "NSFaceIDUsageDescription": return "faceid"
        case "NSSiriUsageDescription": return "mic.circle.fill"
        case "NSContactsUsageDescription": return "person.crop.circle.fill"
        case "NSCalendarsUsageDescription": return "calendar"
        case "NSUserTrackingUsageDescription": return "hand.raised.fill"
        default:
            return key.contains("Location") ? "location.fill" : "lock.shield.fill"
        }
    }

    // MARK: ATS

    private var atsCard: some View {
        Card(title: "App Transport Security",
             subtitle: "Transport rules enforced by NSURLSession",
             symbol: "network.badge.shield.half.filled",
             tint: Theme.accent) {
            if let ats = analysis.app.appTransportSecurity {
                VStack(alignment: .leading, spacing: 12) {
                    let arbitrary = ats["NSAllowsArbitraryLoads"] as? Bool ?? false
                    FlowLayout(spacing: 7) {
                        Chip(text: arbitrary ? "Arbitrary loads allowed" : "Arbitrary loads blocked",
                             symbol: arbitrary ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                             tint: arbitrary ? FileKind.executable.color : FileKind.localization.color,
                             filled: arbitrary)
                        ForEach(["NSAllowsArbitraryLoadsInWebContent",
                                 "NSAllowsLocalNetworking",
                                 "NSAllowsArbitraryLoadsForMedia"], id: \.self) { key in
                            if ats[key] as? Bool == true {
                                Chip(text: key.replacingOccurrences(of: "NSAllows", with: ""),
                                     tint: FileKind.assetCatalog.color)
                            }
                        }
                    }

                    if let domains = ats["NSExceptionDomains"] as? [String: Any], !domains.isEmpty {
                        Text("EXCEPTION DOMAINS")
                            .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                            .foregroundStyle(Theme.tertiaryText)
                        VStack(spacing: 8) {
                            ForEach(domains.keys.sorted(), id: \.self) { domain in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(domain)
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.primaryText)
                                    if let rules = domains[domain] as? [String: Any] {
                                        FlowLayout(spacing: 5) {
                                            ForEach(rules.keys.sorted(), id: \.self) { rule in
                                                Chip(text: "\(rule.replacingOccurrences(of: "NSException", with: "").replacingOccurrences(of: "NSThirdPartyException", with: "3P ")) = \(rules[rule]!)",
                                                     tint: Theme.accent)
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            } else {
                NoteBlock(text: "No NSAppTransportSecurity dictionary. ATS defaults apply: HTTPS with TLS 1.2 and forward secrecy for every connection.",
                          symbol: "checkmark.shield.fill", tint: FileKind.localization.color)
            }
        }
    }

    // MARK: Capabilities

    private var capabilitiesCard: some View {
        Card(title: "Runtime declarations",
             subtitle: "What the app asks the system for at launch",
             symbol: "gearshape.fill",
             tint: Theme.accentViolet) {
            VStack(alignment: .leading, spacing: 12) {
                if !analysis.app.backgroundModes.isEmpty {
                    labeledChips("Background modes", analysis.app.backgroundModes,
                                 tint: FileKind.appExtension.color, symbol: "moon.zzz.fill")
                }
                if !analysis.app.requiredCapabilities.isEmpty {
                    labeledChips("Required capabilities", analysis.app.requiredCapabilities,
                                 tint: Theme.accent, symbol: "cpu.fill")
                }
                if !analysis.app.supportedOrientations.isEmpty {
                    labeledChips("Orientations", analysis.app.supportedOrientations,
                                 tint: FileKind.interface.color, symbol: "rotate.right.fill")
                }
                if !analysis.app.urlSchemes.isEmpty {
                    labeledChips("URL schemes", analysis.app.urlSchemes,
                                 tint: FileKind.structuredData.color, symbol: "link")
                }
                VStack(spacing: 0) {
                    KeyValueRow(key: "Export compliance",
                                value: analysis.app.encryptionDeclared.map { $0 ? "Uses non-exempt encryption" : "Exempt (declared)" } ?? "Not declared")
                    KeyValueRow(key: "Requires iPhone OS",
                                value: (analysis.app.infoPlist["LSRequiresIPhoneOS"] as? Bool) == true ? "Yes" : "No")
                    KeyValueRow(key: "Scene manifest",
                                value: analysis.app.infoPlist["UIApplicationSceneManifest"] != nil ? "Present" : "Absent")
                }
            }
        }
    }

    private func labeledChips(_ title: String, _ values: [String], tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { Chip(text: $0, symbol: symbol, tint: tint) }
            }
        }
    }

    // MARK: Manifests

    private var manifestsCard: some View {
        Card(title: "Privacy manifests",
             subtitle: "PrivacyInfo.xcprivacy found across the payload",
             symbol: "hand.raised.fill",
             tint: FileKind.privacyManifest.color) {
            if analysis.privacyManifests.isEmpty {
                NoteBlock(text: "No privacy manifests found. Apple requires one from the app and from every SDK on its required-reason API list.",
                          symbol: "exclamationmark.triangle.fill", tint: FileKind.assetCatalog.color)
            } else {
                VStack(spacing: 8) {
                    ForEach(analysis.privacyManifests) { manifest in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: manifest.tracking ? "eye.fill" : "eye.slash.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(manifest.tracking
                                                     ? FileKind.assetCatalog.color : FileKind.privacyManifest.color)
                                Text(manifest.owner)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                if manifest.tracking {
                                    Chip(text: "Tracking", tint: FileKind.assetCatalog.color, filled: true)
                                }
                            }
                            if !manifest.accessedAPITypes.isEmpty {
                                FlowLayout(spacing: 5) {
                                    ForEach(manifest.accessedAPITypes, id: \.self) {
                                        Chip(text: $0, tint: Theme.accent)
                                    }
                                }
                            }
                            if !manifest.collectedDataTypes.isEmpty {
                                FlowLayout(spacing: 5) {
                                    ForEach(manifest.collectedDataTypes, id: \.self) {
                                        Chip(text: $0, tint: FileKind.appExtension.color)
                                    }
                                }
                            }
                            if !manifest.trackingDomains.isEmpty {
                                Text(manifest.trackingDomains.joined(separator: ", "))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}
