//
//  MachOSectionView.swift
//  BinaryExplorer
//
//  Everything the Mach-O header tells us: slices, segments, sections, load
//  commands and the FairPlay encryption record.
//

import SwiftUI

struct MachOSection_View: View {
    let analysis: IPAAnalysis
    @State private var selectedSliceID: String?
    @State private var expandedSegments: Set<String> = ["__TEXT"]

    private var machO: MachOFile? { analysis.app.machO }

    private var slice: MachOSlice? {
        guard let machO else { return nil }
        return machO.slices.first { $0.id == selectedSliceID } ?? machO.primarySlice
    }

    var body: some View {
        SectionScaffold(title: "Mach-O",
                        subtitle: analysis.app.executableURL?.lastPathComponent ?? "No executable",
                        symbol: ExplorerSection.binary.symbol,
                        tint: ExplorerSection.binary.tint) {
            if let machO, let slice {
                if machO.isFat { sliceSwitcher(machO) }
                headerCard(slice)
                encryptionCard(slice)
                segmentCard(slice)
                loadCommandCard(slice)
                runtimeCard(slice)
            } else {
                Card {
                    ContentUnavailableLabel(symbol: "cpu",
                                            title: "No Mach-O to show",
                                            message: "The bundle's CFBundleExecutable could not be parsed as a Mach-O image.")
                }
            }
        }
    }

    // MARK: Slices

    private func sliceSwitcher(_ machO: MachOFile) -> some View {
        Card(title: "Universal binary",
             subtitle: "\(machO.slices.count) architecture slices in one file",
             symbol: "rectangle.split.3x1.fill",
             tint: ExplorerSection.binary.tint) {
            HStack(spacing: 10) {
                ForEach(machO.slices) { candidate in
                    Button {
                        selectedSliceID = candidate.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.architecture)
                                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            Text(Format.bytes(candidate.size))
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .frame(minWidth: 108, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(candidate.id == slice?.id
                                  ? ExplorerSection.binary.tint.opacity(0.2)
                                  : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(candidate.id == slice?.id
                                          ? ExplorerSection.binary.tint.opacity(0.55)
                                          : Theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
                }
                Spacer()
            }
        }
    }

    // MARK: Header

    private func headerCard(_ slice: MachOSlice) -> some View {
        Card(title: "Mach header", symbol: "doc.badge.gearshape.fill", tint: ExplorerSection.binary.tint) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    StatTile(label: "Architecture", value: slice.architecture,
                             detail: slice.fileType, symbol: "cpu.fill", tint: ExplorerSection.binary.tint)
                    StatTile(label: "File size", value: Format.bytes(slice.size),
                             detail: "\(slice.segments.count) segments", symbol: "internaldrive.fill",
                             tint: Theme.accent)
                    StatTile(label: "__TEXT", value: Format.bytes(slice.textSize),
                             detail: "Executable code and constants", symbol: "chevron.left.forwardslash.chevron.right",
                             tint: FileKind.executable.color)
                    StatTile(label: "__LINKEDIT", value: Format.bytes(slice.linkEditSize),
                             detail: "Symbols, fixups, signature", symbol: "link",
                             tint: FileKind.signature.color)
                }

                VStack(spacing: 0) {
                    KeyValueRow(key: "Target platform",
                                value: [slice.platform, slice.minimumOS.map { "min \($0)" }, slice.sdk.map { "SDK \($0)" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                    KeyValueRow(key: "UUID", value: slice.uuid?.uuidString ?? "—", monospaced: true)
                    KeyValueRow(key: "Source version",
                                value: slice.sourceVersion.flatMap { $0.hasPrefix("0.0.0") ? nil : $0 } ?? "—",
                                monospaced: true)
                    KeyValueRow(key: "Dynamic linker", value: slice.dylinker ?? "—", monospaced: true)
                    if let entry = slice.entryPoint {
                        KeyValueRow(key: "Entry point (LC_MAIN)", value: Format.hex(entry, width: 8), monospaced: true)
                    }
                    KeyValueRow(key: "Header flags", value: slice.flags.joined(separator: ", "), monospaced: true)
                    if !slice.rpaths.isEmpty {
                        KeyValueRow(key: "Runpath search", value: slice.rpaths.joined(separator: "\n"), monospaced: true)
                    }
                }

                FlowLayout(spacing: 7) {
                    Chip(text: slice.isPositionIndependent ? "Position independent" : "No PIE",
                         symbol: slice.isPositionIndependent ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                         tint: slice.isPositionIndependent ? FileKind.localization.color : FileKind.executable.color,
                         filled: !slice.isPositionIndependent)
                    if slice.linkedSwift {
                        Chip(text: "Swift", symbol: "swift", tint: FileKind.vector.color)
                    }
                    if slice.hasObjC {
                        Chip(text: "Objective-C runtime", symbol: "c.circle.fill", tint: FileKind.structuredData.color)
                    }
                    if slice.hasChainedFixups {
                        Chip(text: "Chained fixups", symbol: "link.circle.fill", tint: FileKind.localization.color)
                    }
                    if slice.hasExportsTrie {
                        Chip(text: "Exports trie", symbol: "arrow.triangle.branch", tint: Theme.accent)
                    }
                    Chip(text: "\(Format.count(slice.symbolCount)) symbols", symbol: "number", tint: Theme.accent)
                }
            }
        }
    }

    // MARK: Encryption

    @ViewBuilder
    private func encryptionCard(_ slice: MachOSlice) -> some View {
        if let encryption = slice.encryption {
            let tint = encryption.isEncrypted ? FileKind.assetCatalog.color : FileKind.localization.color
            Card(title: "FairPlay encryption",
                 subtitle: "LC_ENCRYPTION_INFO_64",
                 symbol: encryption.isEncrypted ? "lock.fill" : "lock.open.fill",
                 tint: tint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Chip(text: encryption.isEncrypted ? "Encrypted" : "Not encrypted",
                             symbol: encryption.isEncrypted ? "lock.fill" : "lock.open.fill",
                             tint: tint, filled: true)
                        Text("cryptid = \(encryption.cryptID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    VStack(spacing: 0) {
                        KeyValueRow(key: "Encrypted range",
                                    value: "\(Format.hex(encryption.offset, width: 8)) … \(Format.hex(encryption.offset + encryption.size, width: 8))",
                                    monospaced: true)
                        KeyValueRow(key: "Encrypted size", value: Format.bytes(encryption.size))
                        KeyValueRow(key: "Share of slice",
                                    value: String(format: "%.1f%%", Double(encryption.size) / Double(max(slice.size, 1)) * 100))
                    }
                    NoteBlock(text: encryption.isEncrypted
                              ? "The App Store wraps __TEXT in FairPlay DRM when it re-signs a submission. Until the range is decrypted on device, disassembly and string extraction see ciphertext."
                              : "cryptid is 0, so the load command is present but disarmed. This is what a pre-submission build looks like — the whole binary is readable.",
                              symbol: "lock.doc.fill", tint: tint)
                }
            }
        }
    }

    // MARK: Segments

    private func segmentCard(_ slice: MachOSlice) -> some View {
        Card(title: "Segments and sections",
             subtitle: "Virtual memory layout of the slice",
             symbol: "square.stack.3d.up.fill",
             tint: Theme.accentViolet) {
            VStack(alignment: .leading, spacing: 12) {
                let total = Double(max(slice.segments.reduce(UInt64(0)) { $0 + $1.fileSize }, 1))
                ProportionBar(segments: slice.segments.map { (segmentColor($0.name), Double($0.fileSize)) },
                              height: 12)

                VStack(spacing: 6) {
                    ForEach(slice.segments) { segment in
                        SegmentDisclosure(segment: segment,
                                          share: Double(segment.fileSize) / total,
                                          color: segmentColor(segment.name),
                                          isExpanded: expandedSegments.contains(segment.name)) {
                            if expandedSegments.contains(segment.name) {
                                expandedSegments.remove(segment.name)
                            } else {
                                expandedSegments.insert(segment.name)
                            }
                        }
                    }
                }
            }
        }
    }

    private func segmentColor(_ name: String) -> Color {
        switch name {
        case "__TEXT": return FileKind.executable.color
        case "__DATA", "__DATA_CONST", "__DATA_DIRTY": return FileKind.structuredData.color
        case "__LINKEDIT": return FileKind.localization.color
        case "__PAGEZERO": return FileKind.directory.color
        default: return FileKind.appExtension.color
        }
    }

    // MARK: Load commands

    private func loadCommandCard(_ slice: MachOSlice) -> some View {
        Card(title: "Load commands",
             subtitle: "\(slice.loadCommands.reduce(0) { $0 + $1.count }) commands the dynamic linker executes",
             symbol: "list.number",
             tint: Theme.accent) {
            FlowLayout(spacing: 7) {
                ForEach(slice.loadCommands, id: \.name) { command in
                    HStack(spacing: 5) {
                        Text(command.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        if command.count > 1 {
                            Text("×\(command.count)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: Runtime

    private func runtimeCard(_ slice: MachOSlice) -> some View {
        Card(title: "Runtime composition",
             subtitle: "What the section table says about languages and metadata",
             symbol: "gearshape.2.fill",
             tint: FileKind.machineLearning.color) {
            let interesting = slice.allSections.filter {
                $0.name.hasPrefix("__swift5") || $0.name.hasPrefix("__objc_")
                    || ["__text", "__cstring", "__const", "__unwind_info", "__eh_frame"].contains($0.name)
            }
            VStack(spacing: 7) {
                if interesting.isEmpty {
                    Text("No language-specific metadata sections found.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                } else {
                    let maximum = Double(interesting.first?.size ?? 1)
                    ForEach(interesting.prefix(14)) { item in
                        HStack(spacing: 9) {
                            Text(item.name)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 176, alignment: .leading)
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Theme.accentGradient(sectionColor(item.name)))
                                    .frame(width: max(3, proxy.size.width * Double(item.size) / maximum), height: 6)
                                    .frame(height: proxy.size.height, alignment: .center)
                            }
                            .frame(height: 14)
                            Text(Format.bytes(item.size))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func sectionColor(_ name: String) -> Color {
        if name.hasPrefix("__swift5") { return FileKind.vector.color }
        if name.hasPrefix("__objc_") { return FileKind.structuredData.color }
        return FileKind.executable.color
    }
}

// MARK: - Segment row

private struct SegmentDisclosure: View {
    let segment: MachOSegment
    let share: Double
    let color: Color
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 12)
                        .opacity(segment.sections.isEmpty ? 0 : 1)
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                    Text(segment.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.primaryText)
                    Text(segment.protectionDescription)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.07), in: Capsule())
                    if !segment.sections.isEmpty {
                        Text("\(segment.sections.count) sections")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer(minLength: 8)
                    Text(String(format: "%.1f%%", share * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(Format.bytes(segment.fileSize))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 78, alignment: .trailing)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded, !segment.sections.isEmpty {
                VStack(spacing: 2) {
                    HStack(spacing: 10) {
                        Text("SECTION").frame(width: 170, alignment: .leading)
                        Text("ADDRESS").frame(width: 130, alignment: .leading)
                        Text("OFFSET").frame(width: 92, alignment: .leading)
                        Spacer()
                        Text("SIZE").frame(width: 78, alignment: .trailing)
                    }
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ForEach(segment.sections.sorted { $0.address < $1.address }) { item in
                        HStack(spacing: 10) {
                            Text(item.name)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 170, alignment: .leading)
                                .lineLimit(1)
                            Text(Format.hex(item.address, width: 12))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 130, alignment: .leading)
                            Text(item.isZeroFill ? "zero-fill" : Format.hex(item.offset, width: 6))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 92, alignment: .leading)
                            Spacer()
                            Text(Format.bytes(item.size))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 78, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2.5)
                    }
                }
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }
}
