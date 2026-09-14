//
//  DependenciesSection.swift
//  BinaryExplorer
//
//  What the executable links against, and what code the bundle carries with it.
//

import SwiftUI

struct DependenciesSection: View {
    let analysis: IPAAnalysis
    @State private var filter: String = ""
    @State private var showsSystem = true

    private var slice: MachOSlice? { analysis.app.machO?.primarySlice }

    private var libraries: [LinkedLibrary] {
        guard let slice else { return [] }
        return slice.libraries
            .filter { showsSystem || !$0.isSystem }
            .filter { filter.isEmpty || $0.path.localizedCaseInsensitiveContains(filter) }
            .sorted { lhs, rhs in
                if lhs.isEmbedded != rhs.isEmbedded { return lhs.isEmbedded }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        SectionScaffold(title: "Dependencies",
                        subtitle: slice.map { "\($0.libraries.count) linked libraries · \($0.rpaths.count) runpaths" } ?? "—",
                        symbol: ExplorerSection.dependencies.symbol,
                        tint: ExplorerSection.dependencies.tint) {
            if let slice {
                summaryCard(slice)
                embeddedCard
                extensionsCard
                linkListCard
            } else {
                Card { ContentUnavailableLabel(symbol: "link.badge.plus",
                                               title: "No link table",
                                               message: "The executable could not be parsed.") }
            }
        }
    }

    // MARK: Summary

    private func summaryCard(_ slice: MachOSlice) -> some View {
        let embedded = slice.libraries.filter(\.isEmbedded)
        let weak = slice.libraries.filter { $0.kind == .weak }
        let frameworks = slice.libraries.filter { $0.origin == "System framework" }
        let privateFrameworks = slice.libraries.filter { $0.origin == "Private framework" }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            StatTile(label: "Total links", value: "\(slice.libraries.count)",
                     detail: "Resolved by dyld before main()", symbol: "link",
                     tint: ExplorerSection.dependencies.tint)
            StatTile(label: "Embedded", value: "\(embedded.count)",
                     detail: "Shipped in Frameworks/", symbol: "shippingbox.fill",
                     tint: FileKind.framework.color)
            StatTile(label: "System frameworks", value: "\(frameworks.count)",
                     detail: privateFrameworks.isEmpty ? "All public" : "\(privateFrameworks.count) private",
                     symbol: "building.columns.fill", tint: Theme.accent)
            StatTile(label: "Weak links", value: "\(weak.count)",
                     detail: "Optional at load time", symbol: "link.badge.plus",
                     tint: FileKind.interface.color)
        }
    }

    // MARK: Embedded code

    @ViewBuilder
    private var embeddedCard: some View {
        if !analysis.embeddedFrameworks.isEmpty {
            Card(title: "Embedded frameworks",
                 subtitle: "Dynamic code copied into the bundle — each one costs launch time",
                 symbol: "shippingbox.fill",
                 tint: FileKind.framework.color) {
                VStack(spacing: 8) {
                    ForEach(analysis.embeddedFrameworks) { framework in
                        BundleRow(bundle: framework)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var extensionsCard: some View {
        if !analysis.appExtensions.isEmpty || !analysis.watchApps.isEmpty {
            Card(title: "Extensions and companion apps",
                 subtitle: "Separately signed bundles with their own executables",
                 symbol: "puzzlepiece.extension.fill",
                 tint: FileKind.appExtension.color) {
                VStack(spacing: 8) {
                    ForEach(analysis.appExtensions) { item in
                        BundleRow(bundle: item, detail: item.extensionPointIdentifier)
                    }
                    ForEach(analysis.watchApps) { item in
                        BundleRow(bundle: item, detail: "watchOS companion")
                    }
                }
            }
        }
    }

    // MARK: Link table

    private var linkListCard: some View {
        Card(title: "Link table",
             subtitle: "LC_LOAD_DYLIB and friends, in load order",
             symbol: "list.bullet.rectangle",
             tint: ExplorerSection.dependencies.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                        TextField("Filter libraries", text: $filter)
                            .textFieldStyle(.plain).font(.system(size: 11.5))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    Toggle("System libraries", isOn: $showsSystem)
                        .toggleStyle(.checkbox).font(.system(size: 11))
                    Spacer()
                    Text("\(libraries.count) shown")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }

                VStack(spacing: 1) {
                    ForEach(libraries) { library in
                        HStack(spacing: 10) {
                            Image(systemName: library.isEmbedded ? "shippingbox.fill" : "cube.transparent.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(library.isEmbedded
                                                 ? FileKind.framework.color : FileKind.dynamicLibrary.color)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(library.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                Text(library.path)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Theme.tertiaryText)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 10)
                            if library.kind != .required {
                                Chip(text: library.kind.rawValue, tint: FileKind.interface.color)
                            }
                            Text(library.origin)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 118, alignment: .trailing)
                            Text(library.currentVersion)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 84, alignment: .trailing)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }
}

struct BundleRow: View {
    let bundle: BundleInfo
    var detail: String?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: bundle.kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(bundle.kind.fileKind.color)
                .frame(width: 26, height: 26)
                .background(bundle.kind.fileKind.color.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text(detail ?? bundle.bundleIdentifier)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let slice = bundle.machO?.primarySlice {
                Chip(text: slice.architecture, tint: Theme.accent)
                if slice.linkedSwift { Chip(text: "Swift", tint: FileKind.vector.color) }
            }
            Text(Format.bytes(bundle.size))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
    }
}
