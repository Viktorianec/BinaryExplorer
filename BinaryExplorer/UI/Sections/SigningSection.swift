//
//  SigningSection.swift
//  BinaryExplorer
//
//  Code directory, entitlements, certificate chain and the embedded
//  provisioning profile.
//

import SwiftUI

struct SigningSection: View {
    let analysis: IPAAnalysis

    private var slice: MachOSlice? { analysis.app.machO?.primarySlice }
    private var signature: CodeSignature? { slice?.codeSignature }

    var body: some View {
        SectionScaffold(title: "Signing",
                        subtitle: signature.map { "Embedded signature · \(Format.bytes($0.size))" } ?? "No embedded signature",
                        symbol: ExplorerSection.signing.symbol,
                        tint: ExplorerSection.signing.tint) {
            if let signature {
                codeDirectoryCard(signature)
                entitlementsCard
                certificatesCard(signature)
            } else {
                Card { ContentUnavailableLabel(symbol: "seal.slash",
                                               title: "No code signature",
                                               message: "LC_CODE_SIGNATURE is missing or unreadable in this slice.") }
            }
            provisioningCard
            codeResourcesNote
        }
    }

    // MARK: Code directory

    private func codeDirectoryCard(_ signature: CodeSignature) -> some View {
        Card(title: "Code directory",
             subtitle: "The hash manifest the kernel checks page by page",
             symbol: "checkmark.seal.fill",
             tint: ExplorerSection.signing.tint) {
            VStack(alignment: .leading, spacing: 14) {
                if let directory = signature.primaryDirectory {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StatTile(label: "Identifier", value: directory.identifier,
                                 detail: "Signing identity", symbol: "person.badge.key.fill",
                                 tint: ExplorerSection.signing.tint)
                        StatTile(label: "Team", value: directory.teamID ?? "—",
                                 detail: "Apple developer team", symbol: "person.3.fill",
                                 tint: Theme.accent)
                        StatTile(label: "Hash", value: directory.hashType,
                                 detail: "\(directory.hashSize)-byte digests", symbol: "number.square.fill",
                                 tint: Theme.accentViolet)
                        StatTile(label: "Code pages", value: Format.count(directory.codeSlots),
                                 detail: "\(Format.bytes(UInt64(directory.pageSize))) per page",
                                 symbol: "square.grid.3x3.fill", tint: FileKind.structuredData.color)
                    }

                    VStack(spacing: 0) {
                        KeyValueRow(key: "CDHash", value: Format.fingerprint(directory.cdHash), monospaced: true)
                        KeyValueRow(key: "Code limit", value: Format.bytes(directory.codeLimit))
                        KeyValueRow(key: "Special slots", value: "\(directory.specialSlots)")
                        KeyValueRow(key: "Directory version", value: directory.version, monospaced: true)
                        KeyValueRow(key: "Flags",
                                    value: directory.flags.isEmpty ? "none" : directory.flags.joined(separator: ", "),
                                    monospaced: true)
                    }
                }

                if signature.codeDirectories.count > 1 {
                    Text("ALTERNATE DIRECTORIES")
                        .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                        .foregroundStyle(Theme.tertiaryText)
                    FlowLayout(spacing: 6) {
                        ForEach(signature.codeDirectories) { directory in
                            Chip(text: "\(directory.hashType) · \(directory.cdHash.prefix(16))",
                                 tint: Theme.accent)
                        }
                    }
                }

                FlowLayout(spacing: 7) {
                    Chip(text: signature.hasCMSSignature ? "CMS signed" : "No CMS blob",
                         symbol: signature.hasCMSSignature ? "checkmark.shield.fill" : "xmark.shield.fill",
                         tint: signature.hasCMSSignature ? FileKind.localization.color : FileKind.executable.color)
                    if signature.requirementsPresent {
                        Chip(text: "Designated requirement", symbol: "doc.badge.ellipsis", tint: Theme.accent)
                    }
                    if signature.hasDEREntitlements {
                        Chip(text: "DER entitlements", symbol: "doc.text.fill", tint: Theme.accentViolet)
                    }
                    if signature.isAdHoc {
                        Chip(text: "Ad-hoc", symbol: "exclamationmark.triangle.fill",
                             tint: FileKind.assetCatalog.color, filled: true)
                    }
                }
            }
        }
    }

    // MARK: Entitlements

    @ViewBuilder
    private var entitlementsCard: some View {
        if let entitlements = analysis.app.entitlements, !entitlements.isEmpty {
            Card(title: "Entitlements",
                 subtitle: "\(entitlements.count) capabilities granted to the binary",
                 symbol: "key.fill",
                 tint: Theme.accentMint) {
                VStack(spacing: 0) {
                    ForEach(entitlements.keys.sorted(), id: \.self) { key in
                        KeyValueRow(key: key,
                                    value: renderEntitlement(entitlements[key]),
                                    monospaced: true,
                                    tint: tintForEntitlement(key, entitlements[key]))
                    }
                }
            }
        }
    }

    private func renderEntitlement(_ value: Any?) -> String {
        switch value {
        case let flag as Bool: return flag ? "true" : "false"
        case let list as [Any]: return list.map { String(describing: $0) }.joined(separator: "\n")
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { "\($0): \(dictionary[$0]!)" }.joined(separator: "\n")
        case .some(let value): return String(describing: value)
        case .none: return "—"
        }
    }

    private func tintForEntitlement(_ key: String, _ value: Any?) -> Color? {
        if key == "get-task-allow", (value as? Bool) == true { return FileKind.executable.color }
        if key == "aps-environment", (value as? String) == "development" { return FileKind.assetCatalog.color }
        return nil
    }

    // MARK: Certificates

    @ViewBuilder
    private func certificatesCard(_ signature: CodeSignature) -> some View {
        if !signature.certificates.isEmpty {
            Card(title: "Certificate chain",
                 subtitle: "Signers embedded in the CMS blob",
                 symbol: "lock.doc.fill",
                 tint: Theme.accent) {
                VStack(spacing: 9) {
                    ForEach(signature.certificates) { certificate in
                        CertificateRow(certificate: certificate)
                    }
                }
            }
        }
    }

    // MARK: Provisioning

    @ViewBuilder
    private var provisioningCard: some View {
        if let profile = analysis.app.provisioning {
            Card(title: "Provisioning profile",
                 subtitle: profile.name,
                 symbol: profile.channel.symbol,
                 tint: profile.isExpired ? FileKind.executable.color : Theme.accentMint) {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        StatTile(label: "Channel", value: profile.channel.rawValue,
                                 detail: profile.isXcodeManaged ? "Xcode managed" : "Manually created",
                                 symbol: profile.channel.symbol, tint: Theme.accentMint)
                        StatTile(label: "Expires", value: Format.day(profile.expirationDate),
                                 detail: profile.isExpired
                                    ? "Expired"
                                    : profile.daysRemaining.map { "\($0) days left" } ?? "—",
                                 symbol: "calendar.badge.clock",
                                 tint: profile.isExpired ? FileKind.executable.color : Theme.accent)
                        StatTile(label: "Devices", value: profile.provisionsAllDevices
                                    ? "All" : "\(profile.provisionedDevices.count)",
                                 detail: profile.provisionedDevices.isEmpty && !profile.provisionsAllDevices
                                    ? "No device list" : "Registered UDIDs",
                                 symbol: "iphone.gen3", tint: Theme.accentViolet)
                        StatTile(label: "Team", value: profile.teamIdentifiers.first ?? "—",
                                 detail: profile.teamName ?? "—", symbol: "person.3.fill",
                                 tint: FileKind.structuredData.color)
                    }

                    VStack(spacing: 0) {
                        KeyValueRow(key: "Profile UUID", value: profile.uuid, monospaced: true)
                        KeyValueRow(key: "App ID name", value: profile.appIDName ?? "—")
                        KeyValueRow(key: "Application identifier",
                                    value: profile.applicationIdentifier ?? "—", monospaced: true)
                        KeyValueRow(key: "Platforms", value: profile.platforms.joined(separator: ", "))
                        KeyValueRow(key: "Created", value: Format.date(profile.creationDate))
                        if let ttl = profile.timeToLive {
                            KeyValueRow(key: "Time to live", value: "\(ttl) days")
                        }
                    }

                    if !profile.certificates.isEmpty {
                        Text("PROFILE CERTIFICATES")
                            .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                            .foregroundStyle(Theme.tertiaryText)
                        VStack(spacing: 9) {
                            ForEach(profile.certificates) { CertificateRow(certificate: $0) }
                        }
                    }
                }
            }
        } else {
            Card(title: "Provisioning profile", symbol: "signature", tint: Theme.tertiaryText) {
                NoteBlock(text: "No embedded.mobileprovision is present. App Store builds have their profile stripped during processing, so a store download legitimately has none — a development, ad hoc or enterprise build always ships one.",
                          symbol: "info.circle.fill", tint: Theme.accent)
            }
        }
    }

    private var codeResourcesNote: some View {
        Card(title: "_CodeSignature/CodeResources",
             subtitle: "Per-file hash manifest for everything that is not the binary",
             symbol: "doc.badge.gearshape.fill",
             tint: FileKind.signature.color) {
            NoteBlock(text: "The Mach-O code directory only covers the executable's own pages. Every other file in the bundle — nibs, plists, assets — is hashed into CodeResources, and rules in that same plist say which paths are optional or omitted. Changing any sealed resource invalidates the signature and the app refuses to launch.",
                      symbol: "checkmark.seal.fill", tint: FileKind.signature.color)
        }
    }
}

// MARK: - Certificate row

struct CertificateRow: View {
    let certificate: SigningCertificate

    private var isExpired: Bool {
        guard let notAfter = certificate.notValidAfter else { return false }
        return notAfter < Date()
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: isExpired ? "seal.slash.fill" : "seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(isExpired ? FileKind.executable.color : Theme.accentMint)
                .frame(width: 26, height: 26)
                .background((isExpired ? FileKind.executable.color : Theme.accentMint).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(certificate.summary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(certificate.role)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                    if let organization = certificate.organization {
                        Text(organization)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.day(certificate.notValidAfter))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(isExpired ? FileKind.executable.color : Theme.secondaryText)
                Text(isExpired ? "expired" : "valid until")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
    }
}
