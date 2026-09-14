//
//  OverviewSection.swift
//  BinaryExplorer
//
//  The landing page: identity, headline numbers, payload composition and the
//  findings that matter most.
//

import SwiftUI

struct OverviewSection: View {
    let analysis: IPAAnalysis
    @EnvironmentObject private var state: AppState

    private var slice: MachOSlice? { analysis.app.machO?.primarySlice }

    var body: some View {
        SectionScaffold(title: "Overview",
                        subtitle: analysis.sourceURL.lastPathComponent,
                        symbol: ExplorerSection.overview.symbol,
                        tint: ExplorerSection.overview.tint) {
            heroCard
            statGrid
            HStack(alignment: .top, spacing: 18) {
                compositionCard
                heaviestCard
            }
            HStack(alignment: .top, spacing: 18) {
                identityCard
                buildCard
            }
            headlineInsights
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Theme.accentGradient(Theme.accentViolet).opacity(0.4))
                        .frame(width: 112, height: 112)
                        .blur(radius: 24)
                    if let icon = analysis.app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 104, height: 104)
                            .overlay(Image(systemName: "app.dashed").font(.system(size: 34))
                                .foregroundStyle(Theme.tertiaryText))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(analysis.app.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text(analysis.app.bundleIdentifier)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)

                    FlowLayout(spacing: 7) {
                        Chip(text: "Version \(analysis.app.shortVersion)", symbol: "number", tint: Theme.accent)
                        Chip(text: "Build \(analysis.app.buildNumber)", tint: Theme.accent.opacity(0.75))
                        if let minimum = analysis.app.minimumOS {
                            Chip(text: "iOS \(minimum)+", symbol: "arrow.up.circle", tint: Theme.accentMint)
                        }
                        ForEach(analysis.app.deviceFamilies, id: \.self) { family in
                            Chip(text: family,
                                 symbol: family == "iPad" ? "ipad" : "iphone",
                                 tint: Theme.accentViolet)
                        }
                        if let category = Format.appCategory(analysis.app.categoryIdentifier) {
                            Chip(text: category, symbol: "tag.fill", tint: FileKind.assetCatalog.color)
                        }
                        if let profile = analysis.app.provisioning {
                            Chip(text: profile.channel.rawValue,
                                 symbol: profile.channel.symbol,
                                 tint: profile.isExpired ? Color(hex: 0xC33029) : Theme.accentMint,
                                 filled: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Stats

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            StatTile(label: "Archive",
                     value: Format.bytes(analysis.archiveSize),
                     detail: "\(Format.count(analysis.entryCount)) zip entries",
                     symbol: "shippingbox.fill",
                     tint: Theme.accent)
            StatTile(label: "Installed",
                     value: Format.bytes(analysis.uncompressedSize),
                     detail: String(format: "Archive is %.0f%% of this after compression",
                                    analysis.compressionRatio * 100),
                     symbol: "internaldrive.fill",
                     tint: Theme.accentViolet)
            StatTile(label: "Executable",
                     value: Format.bytes(slice?.size ?? 0),
                     detail: slice.map { "\($0.architecture) · \($0.segments.count) segments" } ?? "—",
                     symbol: "cpu.fill",
                     tint: Theme.accentWarm)
            StatTile(label: "Files",
                     value: Format.count(analysis.payloadRoot.fileCount),
                     detail: "\(analysis.embeddedFrameworks.count) frameworks · \(analysis.appExtensions.count) extensions",
                     symbol: "doc.on.doc.fill",
                     tint: Theme.accentMint)
        }
    }

    // MARK: Composition

    private var topCategories: [CategoryTotal] {
        Array(analysis.categories.prefix(7))
    }

    private var otherCategory: CategoryTotal? {
        let rest = analysis.categories.dropFirst(7)
        guard !rest.isEmpty else { return nil }
        return CategoryTotal(kind: .other,
                             size: rest.reduce(0) { $0 + $1.size },
                             fileCount: rest.reduce(0) { $0 + $1.fileCount },
                             label: "Everything else")
    }

    private var compositionCard: some View {
        Card(title: "Payload composition",
             subtitle: "Unpacked bytes by file kind",
             symbol: "chart.pie.fill",
             tint: Theme.accentViolet) {
            VStack(alignment: .leading, spacing: 14) {
                ProportionBar(segments: (topCategories + (otherCategory.map { [$0] } ?? []))
                    .map { ($0.kind.color, Double($0.size)) }, height: 13)

                VStack(spacing: 7) {
                    ForEach(topCategories) { category in
                        CategoryRow(category: category, total: analysis.uncompressedSize)
                    }
                    if let otherCategory {
                        CategoryRow(category: otherCategory, total: analysis.uncompressedSize)
                    }
                }
            }
        }
    }

    private var heaviestCard: some View {
        Card(title: "Heaviest files",
             subtitle: "Top contributors to install size",
             symbol: "scalemass.fill",
             tint: Theme.accentWarm) {
            let files = Array(analysis.largestFiles.prefix(8))
            let maximum = Double(files.first?.size ?? 1)
            VStack(spacing: 9) {
                ForEach(files) { file in
                    Button {
                        state.selectedFileID = file.relativePath
                        state.section = ResourceViewerSupport.isPreviewable(file) ? .resources : .structure
                        if ResourceViewerSupport.isPreviewable(file) {
                            state.selectedResourceID = file.relativePath
                        }
                    } label: {
                        FileBar(file: file, maximum: maximum)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Identity / build

    private var identityCard: some View {
        Card(title: "Bundle identity", symbol: "person.text.rectangle.fill", tint: Theme.accent) {
            VStack(spacing: 0) {
                KeyValueRow(key: "Display name", value: analysis.app.displayName)
                KeyValueRow(key: "Bundle name", value: analysis.app.infoPlist["CFBundleName"] as? String ?? "—")
                KeyValueRow(key: "Bundle identifier", value: analysis.app.bundleIdentifier, monospaced: true)
                KeyValueRow(key: "Executable", value: analysis.app.infoPlist["CFBundleExecutable"] as? String ?? "—",
                            monospaced: true)
                KeyValueRow(key: "Version", value: "\(analysis.app.shortVersion) (\(analysis.app.buildNumber))")
                KeyValueRow(key: "Package type", value: analysis.app.infoPlist["CFBundlePackageType"] as? String ?? "—")
                if !analysis.app.urlSchemes.isEmpty {
                    KeyValueRow(key: "URL schemes",
                                value: analysis.app.urlSchemes.joined(separator: ", "),
                                monospaced: true)
                }
                KeyValueRow(key: "Localizations",
                            value: analysis.localizations.isEmpty
                                ? "—" : "\(analysis.localizations.count) (\(analysis.localizations.prefix(6).joined(separator: ", "))\(analysis.localizations.count > 6 ? "…" : ""))")
            }
        }
    }

    private var buildCard: some View {
        Card(title: "Build provenance", symbol: "hammer.fill", tint: Theme.accentMint) {
            VStack(spacing: 0) {
                KeyValueRow(key: "SDK", value: analysis.app.sdkName ?? "—", monospaced: true)
                KeyValueRow(key: "Xcode", value: [analysis.app.xcodeVersion, analysis.app.xcodeBuild]
                    .compactMap { $0 }.joined(separator: " · "))
                KeyValueRow(key: "Build machine", value: analysis.app.buildMachineOS ?? "—", monospaced: true)
                KeyValueRow(key: "Platform", value: analysis.app.platforms.joined(separator: ", "))
                if let slice {
                    KeyValueRow(key: "Target", value: "\(slice.platform ?? "—") \(slice.minimumOS ?? "")")
                    KeyValueRow(key: "Built against SDK", value: slice.sdk ?? "—")
                    KeyValueRow(key: "Binary UUID", value: slice.uuid?.uuidString ?? "—", monospaced: true)
                    KeyValueRow(key: "Source version",
                                value: slice.sourceVersion.flatMap { $0.hasPrefix("0.0.0") ? nil : $0 } ?? "—",
                                monospaced: true)
                }
                KeyValueRow(key: "Analyzed in", value: Format.duration(analysis.analysisDuration))
            }
        }
    }

    // MARK: Insights

    private var headlineInsights: some View {
        let items = Array(analysis.insights.filter { $0.level <= .warning }.prefix(4))
        return Group {
            if !items.isEmpty {
                Card(title: "Needs attention",
                     subtitle: "\(analysis.insights.count) checks ran across distribution, binary, size and privacy",
                     symbol: "exclamationmark.triangle.fill",
                     tint: Color(hex: 0xC48001)) {
                    VStack(spacing: 10) {
                        ForEach(items) { InsightRow(insight: $0) }
                        Button {
                            state.section = .insights
                        } label: {
                            HStack(spacing: 5) {
                                Text("See all \(analysis.insights.count) findings")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Rows

struct CategoryRow: View {
    let category: CategoryTotal
    let total: UInt64

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(category.kind.color)
                .frame(width: 10, height: 10)
            Image(systemName: category.kind.symbol)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 14)
            Text(category.title)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text("\(category.fileCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)
            Text(Format.bytes(category.size))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 74, alignment: .trailing)
            Text(String(format: "%.1f%%", Double(category.size) / Double(max(total, 1)) * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct FileBar: View {
    let file: FileNode
    let maximum: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: file.kind.symbol)
                    .font(.system(size: 9.5))
                    .foregroundStyle(file.kind.color)
                Text(file.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.bytes(file.size))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.accentGradient(file.kind.color))
                    .frame(width: max(4, proxy.size.width * Double(file.size) / max(maximum, 1)))
            }
            .frame(height: 6)
        }
    }
}

struct InsightRow: View {
    let insight: Insight

    private var tint: Color {
        switch insight.level {
        case .critical: return Color(hex: 0xC33029)
        case .warning: return Color(hex: 0xC48001)
        case .notice: return Theme.accent
        case .positive: return Color(hex: 0x27A83A)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: insight.level.symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(insight.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(insight.category)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(tint.opacity(0.16), lineWidth: 1))
    }
}
