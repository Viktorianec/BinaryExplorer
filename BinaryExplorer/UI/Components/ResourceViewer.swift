//
//  ResourceViewer.swift
//  BinaryExplorer
//
//  Inline previews for everything inside a bundle: images, property lists,
//  text, fonts, media and a hex/strings fallback for opaque binaries.
//

import SwiftUI
import AppKit
import QuickLookUI
import UniformTypeIdentifiers

enum ResourceViewerSupport {

    static func isPreviewable(_ node: FileNode) -> Bool {
        !node.isDirectory
    }

    static func imageMetadata(_ url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }
        var rows: [(String, String)] = []
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            rows.append(("Pixel size", "\(w) × \(h)"))
            rows.append(("Megapixels", String(format: "%.2f MP", Double(w * h) / 1_000_000)))
        }
        if let depth = props[kCGImagePropertyDepth] as? Int { rows.append(("Bit depth", "\(depth)")) }
        if let model = props[kCGImagePropertyColorModel] as? String { rows.append(("Colour model", model)) }
        if let profile = props[kCGImagePropertyProfileName] as? String { rows.append(("Colour profile", profile)) }
        if let alpha = props[kCGImagePropertyHasAlpha] as? Bool { rows.append(("Alpha channel", alpha ? "Yes" : "No")) }
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double { rows.append(("DPI", "\(Int(dpi))")) }
        if let type = CGImageSourceGetType(source) as String? {
            rows.append(("Container", UTType(type)?.localizedDescription ?? type))
        }
        rows.append(("Frames", "\(CGImageSourceGetCount(source))"))
        return rows
    }

    /// Xcode's PNG optimiser rewrites store assets into Apple's CgBI variant.
    static func isAppleOptimizedPNG(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 16) else { return false }
        defer { try? handle.close() }
        return head.count == 16 && head.range(of: Data("CgBI".utf8)) != nil
    }

    static func scale(from name: String) -> String? {
        if name.contains("@3x") { return "@3x" }
        if name.contains("@2x") { return "@2x" }
        return nil
    }
}

// MARK: - Router

struct ResourcePreview: View {
    let node: FileNode
    @State private var payload: Data?
    @State private var loadFailed = false

    var body: some View {
        Group {
            switch node.kind {
            case .image, .vector:
                ImageResourcePreview(node: node)
            case .propertyList, .privacyManifest, .interface:
                PropertyListPreview(node: node)
            case .structuredData, .text, .localization:
                TextResourcePreview(node: node)
            case .font:
                FontResourcePreview(node: node)
            case .media:
                QuickLookPreview(url: node.url)
                    .frame(minHeight: 320)
            case .assetCatalog:
                AssetCatalogPreview(node: node)
            default:
                BinaryResourcePreview(node: node)
            }
        }
    }
}

// MARK: - Images

struct ImageResourcePreview: View {
    let node: FileNode
    @State private var zoom: Double = 1
    @State private var showsCheckerboard = true

    private var image: NSImage? { NSImage(contentsOf: node.url) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if showsCheckerboard {
                    CheckerboardBackground()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(zoom > 2 ? .none : .high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .padding(18)
                } else {
                    ContentUnavailableLabel(symbol: "photo.badge.exclamationmark",
                                            title: "Cannot decode image",
                                            message: "The file is not readable by ImageIO.")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1))

            HStack(spacing: 14) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.tertiaryText)
                Slider(value: $zoom, in: 0.25...6)
                    .controlSize(.small)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.tertiaryText)
                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 48, alignment: .trailing)
                Divider().frame(height: 16)
                Toggle("Alpha grid", isOn: $showsCheckerboard)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))
                Button("Reset") { zoom = 1 }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }

            let metadata = ResourceViewerSupport.imageMetadata(node.url)
            if !metadata.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(metadata.enumerated()), id: \.offset) { _, row in
                        KeyValueRow(key: row.0, value: row.1)
                    }
                    if ResourceViewerSupport.isAppleOptimizedPNG(node.url) {
                        KeyValueRow(key: "PNG variant",
                                    value: "CgBI (Apple-optimised)",
                                    tint: FileKind.image.color)
                    }
                    if let scale = ResourceViewerSupport.scale(from: node.name) {
                        KeyValueRow(key: "Rendition scale", value: scale)
                    }
                }
            }
        }
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color.white.opacity(0.10)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : step
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: step, height: step)),
                                 with: .color(Color.black.opacity(0.25)))
                    x += step * 2
                }
                y += step
                row += 1
            }
        }
    }
}

// MARK: - Property lists

struct PropertyListPreview: View {
    let node: FileNode
    @State private var mode: Mode = .tree

    enum Mode: String, CaseIterable { case tree = "Tree", raw = "Raw" }

    private var parsed: (value: Any, format: PropertyListSerialization.PropertyListFormat)? {
        guard let data = try? Data(contentsOf: node.url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let value = try? PropertyListSerialization.propertyList(from: data,
                                                                      options: [],
                                                                      format: &format) else { return nil }
        return (value, format)
    }

    var body: some View {
        if let parsed {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Chip(text: parsed.format == .binary ? "Binary plist" : "XML plist",
                         symbol: "doc.badge.gearshape", tint: FileKind.propertyList.color)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 140)
                    .labelsHidden()
                }
                if mode == .tree {
                    PlistTreeView(root: parsed.value)
                } else {
                    ScrollView {
                        Text(PlistRenderer.xml(from: parsed.value) ?? "—")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 420)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        } else {
            BinaryResourcePreview(node: node)
        }
    }
}

enum PlistRenderer {
    static func xml(from value: Any) -> String? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value,
                                                             format: .xml,
                                                             options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct PlistNode: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var typeName: String
    var children: [PlistNode]?

    static func build(key: String, value: Any) -> PlistNode {
        switch value {
        case let dictionary as [String: Any]:
            let children = dictionary.keys.sorted().map { build(key: $0, value: dictionary[$0]!) }
            return PlistNode(key: key, value: "\(children.count) keys", typeName: "Dictionary", children: children)
        case let array as [Any]:
            let children = array.enumerated().map { build(key: "[\($0.offset)]", value: $0.element) }
            return PlistNode(key: key, value: "\(children.count) items", typeName: "Array", children: children)
        case let flag as Bool:
            return PlistNode(key: key, value: flag ? "true" : "false", typeName: "Boolean", children: nil)
        case let number as NSNumber:
            return PlistNode(key: key, value: number.stringValue, typeName: "Number", children: nil)
        case let date as Date:
            return PlistNode(key: key, value: Format.date(date), typeName: "Date", children: nil)
        case let data as Data:
            return PlistNode(key: key, value: "\(Format.bytes(data.count)) of data", typeName: "Data", children: nil)
        default:
            return PlistNode(key: key, value: String(describing: value), typeName: "String", children: nil)
        }
    }
}

struct PlistTreeView: View {
    let root: Any

    private var nodes: [PlistNode] {
        let built = PlistNode.build(key: "root", value: root)
        return built.children ?? [built]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OutlineGroup(nodes, children: \.children) { node in
                    HStack(spacing: 10) {
                        Text(node.key)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.primaryText)
                        Text(node.typeName)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.07), in: Capsule())
                        Spacer(minLength: 12)
                        Text(node.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 440)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Text

struct TextResourcePreview: View {
    let node: FileNode
    @State private var query = ""

    private var text: String {
        guard let data = try? Data(contentsOf: node.url) else { return "" }
        if node.url.pathExtension.lowercased() == "json",
           let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys]),
           let rendered = String(data: pretty, encoding: .utf8) {
            return rendered
        }
        // .strings files are usually UTF-16 with a BOM.
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
    }

    private var lines: [(Int, String)] {
        let all = text.components(separatedBy: .newlines)
        let filtered = query.isEmpty
            ? Array(all.enumerated())
            : all.enumerated().filter { $0.element.localizedCaseInsensitiveContains(query) }
        return filtered.prefix(4000).map { ($0.offset + 1, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Theme.tertiaryText)
                TextField("Filter lines", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                Spacer()
                Text("\(lines.count) lines")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(lines, id: \.0) { number, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(number)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 44, alignment: .trailing)
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.primaryText.opacity(0.85))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 440)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Fonts

struct FontResourcePreview: View {
    let node: FileNode
    @State private var sample = "The quick brown fox jumps over the lazy dog 0123456789"
    @State private var size: Double = 28

    private var descriptors: [NSFontDescriptor] {
        guard let data = try? Data(contentsOf: node.url),
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider), let name = font.postScriptName as String? else { return [] }
        CTFontManagerRegisterGraphicsFont(font, nil)
        return [NSFontDescriptor(name: name, size: size)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let descriptor = descriptors.first,
               let font = NSFont(descriptor: descriptor, size: size) {
                Text(sample)
                    .font(Font(font))
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                KeyValueRow(key: "PostScript name", value: font.fontName, monospaced: true)
                KeyValueRow(key: "Family", value: font.familyName ?? "—")
                HStack {
                    Text("Size").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    Slider(value: $size, in: 10...72).controlSize(.small)
                    Text("\(Int(size)) pt").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }
                TextField("Sample text", text: $sample)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
            } else {
                ContentUnavailableLabel(symbol: "textformat",
                                        title: "Font could not be loaded",
                                        message: "Core Text declined to register this file.")
            }
        }
    }
}

// MARK: - Asset catalog

struct AssetCatalogPreview: View {
    let node: FileNode

    private var info: AssetCatalogInfo? { AssetCatalogProbe.probe(url: node.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoteBlock(text: "Assets.car is a compiled CoreUI archive built on Apple's BOM container format. Individual renditions are only decodable through CoreUI at runtime, so Binary Explorer reports the catalog's structure rather than unpacking it.",
                      symbol: "photo.stack.fill",
                      tint: FileKind.assetCatalog.color)
            if let info {
                VStack(spacing: 0) {
                    KeyValueRow(key: "File size", value: Format.bytes(info.fileSize))
                    if let count = info.renditionCount {
                        KeyValueRow(key: "Renditions", value: Format.count(count))
                    }
                    if let count = info.namedAssetCount {
                        KeyValueRow(key: "Named assets", value: Format.count(count))
                    }
                    if let count = info.colorCount, count > 0 {
                        KeyValueRow(key: "Named colours", value: Format.count(count))
                    }
                    if let count = info.appearanceCount, count > 0 {
                        KeyValueRow(key: "Appearances", value: Format.count(count))
                    }
                    if let version = info.coreUIVersion {
                        KeyValueRow(key: "CoreUI version", value: "\(version)")
                    }
                    if let version = info.storageVersion {
                        KeyValueRow(key: "Storage version", value: "\(version)")
                    }
                    if let creator = info.creator {
                        KeyValueRow(key: "Created by", value: creator, monospaced: true)
                    }
                    if let toolchain = info.toolchain {
                        KeyValueRow(key: "Toolchain", value: toolchain, monospaced: true)
                    }
                    if let timestamp = info.storageTimestamp {
                        KeyValueRow(key: "Compiled", value: Format.date(timestamp))
                    }
                    if let uuid = info.uuid {
                        KeyValueRow(key: "Catalog UUID", value: uuid.uuidString, monospaced: true)
                    }
                }
                if !info.variables.isEmpty {
                    Text("BOM SECTIONS")
                        .font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(Theme.tertiaryText)
                    FlowLayout(spacing: 6) {
                        ForEach(info.variables, id: \.self) { name in
                            Chip(text: name, tint: FileKind.assetCatalog.color)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Binary fallback

struct BinaryResourcePreview: View {
    let node: FileNode
    @State private var mode: Mode = .hex

    enum Mode: String, CaseIterable { case hex = "Hex", strings = "Strings" }

    private var sample: Data {
        guard let handle = try? FileHandle(forReadingFrom: node.url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 64 * 1024)) ?? Data()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Chip(text: "First \(Format.bytes(sample.count))", symbol: "doc.viewfinder", tint: Theme.accent)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small).frame(width: 150).labelsHidden()
            }
            ScrollView {
                Text(mode == .hex ? HexDump.render(sample) : HexDump.strings(sample).joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 420)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

enum HexDump {
    static func render(_ data: Data, maxBytes: Int = 8192) -> String {
        let slice = data.prefix(maxBytes)
        var output = ""
        var offset = 0
        for chunk in slice.chunked(into: 16) {
            let hex = chunk.map { String(format: "%02x", $0) }
            let left = hex.prefix(8).joined(separator: " ")
            let right = hex.dropFirst(8).joined(separator: " ")
            let ascii = String(chunk.map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : "." })
            output += String(format: "%08x  %-23s  %-23s  |%@|\n",
                             offset,
                             (left as NSString).utf8String!,
                             (right as NSString).utf8String!,
                             ascii)
            offset += chunk.count
        }
        if data.count > maxBytes {
            output += "\n… \(Format.bytes(data.count - maxBytes)) more not shown"
        }
        return output
    }

    /// Printable ASCII runs, the way `strings(1)` finds them.
    static func strings(_ data: Data, minimumLength: Int = 4, limit: Int = 800) -> [String] {
        var result: [String] = []
        var current: [UInt8] = []
        for byte in data {
            if byte >= 32, byte < 127 {
                current.append(byte)
            } else {
                if current.count >= minimumLength {
                    result.append(String(decoding: current, as: UTF8.self))
                    if result.count >= limit { return result }
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= minimumLength { result.append(String(decoding: current, as: UTF8.self)) }
        return result
    }
}

extension Data {
    func chunked(into size: Int) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var buffer: [UInt8] = []
        buffer.reserveCapacity(size)
        for byte in self {
            buffer.append(byte)
            if buffer.count == size {
                result.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }
}

// MARK: - QuickLook

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = false
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url {
            view.previewItem = url as QLPreviewItem
        }
    }
}

// MARK: - Helpers

struct ContentUnavailableLabel: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

/// Simple wrapping layout for chip clouds.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
