//
//  SpatialSection.swift
//  BinaryExplorer
//
//  The 3D tab: a SceneKit stage with a mode switch, live legend and an
//  inspector for whatever the pointer is over.
//

import SwiftUI
import SceneKit

struct SpatialSection: View {
    let analysis: IPAAnalysis
    @EnvironmentObject private var state: AppState

    private var slice: MachOSlice? { analysis.app.machO?.primarySlice }

    /// Building a scene walks the whole payload, so it is built once per token
    /// and held in state — recomputing it inside `body` would hand the scene
    /// view a fresh copy on every redraw and strand the callout layer.
    @State private var built: SpatialSceneBundle?
    @State private var builtToken: String = ""

    private func makeBundle() -> SpatialSceneBundle {
        switch state.spatialMode {
        case .city:
            return SceneBuilder.buildCity(root: analysis.payloadRoot)
        case .strata:
            guard let slice else { return emptyBundle }
            return SceneBuilder.buildStrata(slice: slice)
        case .constellation:
            guard let slice else { return emptyBundle }
            return SceneBuilder.buildConstellation(slice: slice)
        }
    }

    private func nodeName(for selection: SpatialSelection?) -> String? {
        switch selection {
        case .file(let path): return "file:" + path
        case .section(let name): return "section:" + name
        case .library(let path): return "library:" + path
        case nil: return nil
        }
    }

    private var emptyBundle: SpatialSceneBundle {
        SpatialSceneBundle(scene: SCNScene(), index: [:], preLabelled: [])
    }

    /// Changing this string is what makes the wrapper re-install the scene.
    /// Selection is deliberately absent — clicking must not reset the camera.
    private var sceneToken: String {
        "\(state.spatialMode.rawValue)|\(analysis.app.relativePath)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topLeading) {
                SpatialSceneView(bundle: built ?? emptyBundle,
                                 sceneToken: sceneToken,
                                 autoRotate: state.autoRotate,
                                 labelMode: state.labelMode,
                                 hoveredNodeName: nodeName(for: state.hoveredSpatial),
                                 selectedNodeName: nodeName(for: state.spatialSelection),
                                 onSelect: { state.reveal(spatial: $0) },
                                 onHover: { state.hoveredSpatial = $0 })
                .background(Color(hex: 0x07090F))

                VStack(alignment: .leading, spacing: 12) {
                    captionCard
                    if state.spatialMode == .city { legendCard }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(width: 260)
                .allowsHitTesting(false)

                HStack(alignment: .top) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        if state.spatialSelection != nil {
                            detailPanel.frame(width: 340)
                        }
                        Spacer(minLength: 0)
                        if state.hoveredSpatial != nil, state.hoveredSpatial != state.spatialSelection {
                            inspectorCard.frame(width: 320)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(Color.clear)
        .task(id: sceneToken) {
            let token = sceneToken
            guard builtToken != token else { return }
            let bundle = makeBundle()
            builtToken = token
            built = bundle
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            SectionTitle(title: "Spatial",
                         subtitle: "Interactive 3D map of the archive",
                         symbol: ExplorerSection.spatial.symbol,
                         tint: ExplorerSection.spatial.tint)
                .lineLimit(1)
                // The controls keep their intrinsic size; the title is what
                // gives way when the window narrows.
                .layoutPriority(-1)

            Spacer(minLength: 12)

            controls
                .layoutPriority(1)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    /// Segmented pickers here are deliberately text-only and self-sized.
    /// A macOS segmented control that has to fit into a hard-coded frame drops
    /// and restores its segment images as the mouse crosses it, which reads as
    /// the whole strip twitching under the pointer.
    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $state.spatialMode) {
                ForEach(SpatialMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(slice == nil && state.spatialMode != .city)
            .help(state.spatialMode.caption)

            Picker("", selection: $state.labelMode) {
                ForEach(SpatialLabelMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Callouts: " + state.labelMode.help)

            Toggle(isOn: $state.autoRotate) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .toggleStyle(.button)
            .fixedSize()
            .help("Idle rotation")
        }
    }

    // MARK: Overlays

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(state.spatialMode.rawValue, systemImage: state.spatialMode.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(state.spatialMode.caption)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.25)
            Text("Drag to orbit · scroll to zoom · click a shape to inspect it. Callouts: \(state.labelMode.rawValue.lowercased()).")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    private var legendCard: some View {
        let kinds = Array(analysis.categories.prefix(9))
        return VStack(alignment: .leading, spacing: 7) {
            Text("LEGEND")
                .font(.system(size: 9, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            ForEach(kinds) { category in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(category.kind.sceneColor)
                        .frame(width: 9, height: 9)
                    Text(category.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 4)
                    Text(Format.bytes(category.size))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let selection = state.spatialSelection {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SELECTED")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.9)
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Button {
                        state.spatialSelection = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the selection")
                }

                switch selection {
                case .file(let path):
                    if let node = analysis.payloadRoot.flattened().first(where: { $0.relativePath == path }) {
                        fileDetail(node)
                    }
                case .section(let identifier):
                    sectionDetail(identifier)
                case .library(let path):
                    libraryDetail(path)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ExplorerSection.spatial.tint.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        }
    }

    @ViewBuilder
    private func fileDetail(_ node: FileNode) -> some View {
        inspectorHeader(symbol: node.kind.symbol,
                        tint: node.kind.sceneColor,
                        title: node.name,
                        subtitle: node.kind.title)
        VStack(spacing: 0) {
            KeyValueRow(key: "Unpacked size", value: Format.bytes(node.size))
            if node.isDirectory {
                KeyValueRow(key: "Contains", value: "\(Format.count(node.fileCount)) files")
            } else {
                KeyValueRow(key: "In archive", value: Format.bytes(node.compressedSize))
            }
            KeyValueRow(key: "Share of payload",
                        value: String(format: "%.2f%%",
                                      Double(node.size) / Double(max(analysis.uncompressedSize, 1)) * 100))
            KeyValueRow(key: "Path", value: node.relativePath, monospaced: true)
        }
        NoteBlock(text: node.kind.explanation, symbol: node.kind.symbol, tint: node.kind.color)
        HStack(spacing: 8) {
            if !node.isDirectory {
                Button {
                    state.selectedResourceID = node.relativePath
                    state.section = .resources
                } label: {
                    Label("Preview", systemImage: "eye.fill").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(ExplorerSection.resources.tint)
                .controlSize(.small)
            }
            Button {
                state.selectedFileID = node.relativePath
                state.section = .structure
            } label: {
                Label("In tree", systemImage: "list.bullet.indent").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reveal the unpacked file in Finder")
        }
    }

    @ViewBuilder
    private func sectionDetail(_ identifier: String) -> some View {
        if let slice {
            let match = slice.allSections.first { "\($0.segment).\($0.name)" == identifier }
            inspectorHeader(symbol: "square.stack.3d.up.fill",
                            tint: Theme.accentWarm,
                            title: match?.name ?? identifier,
                            subtitle: match?.segment ?? "Segment")
            VStack(spacing: 0) {
                if let match {
                    KeyValueRow(key: "Size", value: Format.bytes(match.size))
                    KeyValueRow(key: "VM address", value: Format.hex(match.address, width: 12), monospaced: true)
                    KeyValueRow(key: "File offset",
                                value: match.isZeroFill ? "zero-fill" : Format.hex(match.offset, width: 8),
                                monospaced: true)
                } else if let segment = slice.segments.first(where: { $0.name == identifier }) {
                    KeyValueRow(key: "File size", value: Format.bytes(segment.fileSize))
                    KeyValueRow(key: "VM size", value: Format.bytes(segment.vmSize))
                    KeyValueRow(key: "VM address", value: Format.hex(segment.vmAddress, width: 12), monospaced: true)
                    KeyValueRow(key: "Protection", value: segment.protectionDescription, monospaced: true)
                    KeyValueRow(key: "Sections", value: "\(segment.sections.count)")
                }
            }
            Button {
                state.section = .binary
            } label: {
                Label("Open in Mach-O", systemImage: "cpu.fill").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(ExplorerSection.binary.tint)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func libraryDetail(_ path: String) -> some View {
        if let library = slice?.libraries.first(where: { $0.path == path }) {
            inspectorHeader(symbol: library.isEmbedded ? "shippingbox.fill" : "cube.transparent.fill",
                            tint: library.isEmbedded ? FileKind.framework.sceneColor
                                                     : FileKind.dynamicLibrary.sceneColor,
                            title: library.name,
                            subtitle: "\(library.origin) · \(library.kind.rawValue)")
            VStack(spacing: 0) {
                KeyValueRow(key: "Install path", value: library.path, monospaced: true)
                KeyValueRow(key: "Current version", value: library.currentVersion, monospaced: true)
                KeyValueRow(key: "Compatibility", value: library.compatibilityVersion, monospaced: true)
                KeyValueRow(key: "Linkage", value: library.kind.rawValue)
            }
            NoteBlock(text: library.isEmbedded
                      ? "Shipped inside the bundle and loaded by dyld at launch, so it counts against cold-start time."
                      : "Provided by the operating system — it costs no download size and is shared across apps.",
                      symbol: "link", tint: library.isEmbedded ? FileKind.framework.color : Theme.accent)
            Button {
                state.section = .dependencies
            } label: {
                Label("Open in Dependencies", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(ExplorerSection.dependencies.tint)
            .controlSize(.small)
        } else {
            inspectorHeader(symbol: "cpu.fill",
                            tint: FileKind.executable.sceneColor,
                            title: analysis.app.name,
                            subtitle: "Main executable")
        }
    }

    @ViewBuilder
    private var inspectorCard: some View {
        let target = state.hoveredSpatial
        if let target {
            VStack(alignment: .leading, spacing: 10) {
                switch target {
                case .file(let path):
                    if let node = analysis.payloadRoot.flattened().first(where: { $0.relativePath == path }) {
                        inspectorHeader(symbol: node.kind.symbol,
                                        tint: node.kind.sceneColor,
                                        title: node.name,
                                        subtitle: node.kind.title)
                        KeyValueRow(key: "Size", value: Format.bytes(node.size))
                        if !node.isDirectory {
                            KeyValueRow(key: "In archive", value: Format.bytes(node.compressedSize))
                        } else {
                            KeyValueRow(key: "Files", value: Format.count(node.fileCount))
                        }
                        KeyValueRow(key: "Share",
                                    value: String(format: "%.2f%%",
                                                  Double(node.size) / Double(max(analysis.uncompressedSize, 1)) * 100))
                        Text(node.relativePath)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                case .section(let identifier):
                    if let slice {
                        let match = slice.allSections.first { "\($0.segment).\($0.name)" == identifier }
                        inspectorHeader(symbol: "square.stack.3d.up.fill",
                                        tint: Theme.accentWarm,
                                        title: match?.name ?? identifier,
                                        subtitle: match?.segment ?? "Segment")
                        if let match {
                            KeyValueRow(key: "Size", value: Format.bytes(match.size))
                            KeyValueRow(key: "VM address", value: Format.hex(match.address, width: 12), monospaced: true)
                            KeyValueRow(key: "File offset", value: Format.hex(match.offset, width: 8), monospaced: true)
                        } else if let segment = slice.segments.first(where: { $0.name == identifier }) {
                            KeyValueRow(key: "File size", value: Format.bytes(segment.fileSize))
                            KeyValueRow(key: "VM size", value: Format.bytes(segment.vmSize))
                            KeyValueRow(key: "Protection", value: segment.protectionDescription, monospaced: true)
                            KeyValueRow(key: "Sections", value: "\(segment.sections.count)")
                        }
                    }
                case .library(let path):
                    if let library = slice?.libraries.first(where: { $0.path == path }) {
                        inspectorHeader(symbol: library.isEmbedded ? "shippingbox.fill" : "cube.transparent.fill",
                                        tint: library.isEmbedded ? FileKind.framework.sceneColor
                                                                 : FileKind.dynamicLibrary.sceneColor,
                                        title: library.name,
                                        subtitle: "\(library.origin) · \(library.kind.rawValue)")
                        KeyValueRow(key: "Current version", value: library.currentVersion, monospaced: true)
                        KeyValueRow(key: "Compatibility", value: library.compatibilityVersion, monospaced: true)
                        Text(library.path)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(2).truncationMode(.middle)
                    } else {
                        inspectorHeader(symbol: "cpu.fill",
                                        tint: FileKind.executable.sceneColor,
                                        title: analysis.app.name,
                                        subtitle: "Main executable")
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }

    private func inspectorHeader(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
