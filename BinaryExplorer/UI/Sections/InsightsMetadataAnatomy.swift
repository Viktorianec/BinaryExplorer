//
//  InsightsMetadataAnatomy.swift
//  BinaryExplorer
//
//  Three lighter sections: the findings list, the raw Info.plist and a
//  reference page describing how an .ipa is put together.
//

import SwiftUI

// MARK: - Insights

struct InsightsSection: View {
    let analysis: IPAAnalysis
    @State private var levelFilter: Insight.Level?

    private var grouped: [(String, [Insight])] {
        let filtered = analysis.insights.filter { levelFilter == nil || $0.level == levelFilter }
        return Dictionary(grouping: filtered, by: \.category)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.level < $1.level }) }
    }

    private func count(_ level: Insight.Level) -> Int {
        analysis.insights.filter { $0.level == level }.count
    }

    var body: some View {
        SectionScaffold(title: "Insights",
                        subtitle: "\(analysis.insights.count) findings across distribution, security, size and privacy",
                        symbol: ExplorerSection.insights.symbol,
                        tint: ExplorerSection.insights.tint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach([Insight.Level.critical, .warning, .notice, .positive], id: \.rawValue) { level in
                    Button {
                        levelFilter = levelFilter == level ? nil : level
                    } label: {
                        StatTile(label: level.title,
                                 value: "\(count(level))",
                                 detail: levelFilter == level ? "Filtering by this level" : "Tap to filter",
                                 symbol: level.symbol,
                                 tint: tint(for: level))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(levelFilter == level ? tint(for: level) : .clear, lineWidth: 1.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(grouped, id: \.0) { category, items in
                Card(title: category,
                     subtitle: "\(items.count) finding\(items.count == 1 ? "" : "s")",
                     symbol: symbol(for: category),
                     tint: ExplorerSection.insights.tint) {
                    VStack(spacing: 10) {
                        ForEach(items) { InsightRow(insight: $0) }
                    }
                }
            }
        }
    }

    private func tint(for level: Insight.Level) -> Color {
        switch level {
        case .critical: return FileKind.executable.color
        case .warning: return FileKind.assetCatalog.color
        case .notice: return Theme.accent
        case .positive: return FileKind.localization.color
        }
    }

    private func symbol(for category: String) -> String {
        switch category {
        case "Distribution": return "bag.fill"
        case "Security": return "lock.shield.fill"
        case "Binary": return "cpu.fill"
        case "Size": return "scalemass.fill"
        case "Privacy": return "hand.raised.fill"
        case "Performance": return "bolt.fill"
        case "Capabilities": return "switch.2"
        default: return "gearshape.fill"
        }
    }
}

// MARK: - Info.plist

struct MetadataSection: View {
    let analysis: IPAAnalysis
    @State private var selectedBundle: String?
    @State private var query = ""

    private var bundle: BundleInfo {
        analysis.allBundles.first { $0.relativePath == selectedBundle } ?? analysis.app
    }

    private var keys: [String] {
        bundle.infoPlist.keys.sorted().filter {
            query.isEmpty
                || $0.localizedCaseInsensitiveContains(query)
                || String(describing: bundle.infoPlist[$0]!).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        SectionScaffold(title: "Info.plist",
                        subtitle: "\(bundle.infoPlist.count) keys in \(bundle.name)",
                        symbol: ExplorerSection.metadata.symbol,
                        tint: ExplorerSection.metadata.tint) {
            Card {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(get: { selectedBundle ?? analysis.app.relativePath },
                                                  set: { selectedBundle = $0 })) {
                        ForEach(analysis.allBundles) { item in
                            Text("\(item.name) · \(item.kind.rawValue)").tag(item.relativePath)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                        TextField("Filter keys and values", text: $query)
                            .textFieldStyle(.plain).font(.system(size: 11.5))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Spacer()
                    Text("\(keys.count) keys")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Card(title: "Raw keys", symbol: "list.bullet.rectangle.fill", tint: ExplorerSection.metadata.tint) {
                VStack(spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        KeyValueRow(key: key,
                                    value: render(bundle.infoPlist[key]),
                                    monospaced: true)
                        if key != keys.last {
                            Divider().opacity(0.12)
                        }
                    }
                }
            }
        }
    }

    private func render(_ value: Any?) -> String {
        switch value {
        case let flag as Bool: return flag ? "true" : "false"
        case let list as [Any]:
            return list.map { String(describing: $0) }.joined(separator: "\n")
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted()
                .map { "\($0) = \(render(dictionary[$0]))" }
                .joined(separator: "\n")
        case let data as Data: return "<\(Format.bytes(data.count)) of data>"
        case .some(let value): return String(describing: value)
        case .none: return "—"
        }
    }
}

// MARK: - Anatomy reference

struct AnatomySection: View {
    let analysis: IPAAnalysis

    private struct Entry: Identifiable {
        var id: String { path }
        var path: String
        var kind: FileKind
        var title: String
        var text: String
        var required: Bool
        /// Matches the entry against a bundle-relative path.
        var matches: (String) -> Bool
    }

    private var entries: [Entry] {
        [
            Entry(path: "Payload/", kind: .directory, title: "The only top-level folder",
                  text: "An .ipa is a plain ZIP. Everything the installer reads lives under Payload/. Sibling folders such as iTunesArtwork or WatchKitSupport are added by the store pipeline, never by Xcode.",
                  required: true,
                  matches: { _ in true }),
            Entry(path: "Payload/<App>.app", kind: .executable, title: "The application bundle",
                  text: "A flat bundle: unlike macOS there is no Contents/MacOS layer. The executable, Info.plist and every resource sit side by side at the bundle root.",
                  required: true,
                  matches: { $0.hasSuffix(".app") }),
            Entry(path: "Info.plist", kind: .propertyList, title: "Bundle manifest",
                  text: "Binary property list naming the executable, bundle identifier, versions, minimum OS, device families, orientations, URL schemes, background modes and every purpose string the system shows the user.",
                  required: true,
                  matches: { $0.hasSuffix("/Info.plist") }),
            Entry(path: "<Executable>", kind: .executable, title: "Mach-O binary",
                  text: "Named by CFBundleExecutable. Since iOS 11 it is a single arm64 slice; older builds are fat binaries. LC_ENCRYPTION_INFO_64 is where the store attaches FairPlay.",
                  required: true,
                  matches: { [name = analysisAppName] in $0.hasSuffix("/" + name) }),
            Entry(path: "Assets.car", kind: .assetCatalog, title: "Compiled asset catalog",
                  text: "actool packs images, colours, symbols and app icons into Apple's CoreUI/BOM container. App thinning slices it per device at delivery, so the installed size is smaller than what ships here.",
                  required: false,
                  matches: { $0.hasSuffix("/Assets.car") }),
            Entry(path: "AppIcon*.png", kind: .image, title: "Loose icon renditions",
                  text: "Even with an asset catalog, iOS writes primary icon PNGs to the bundle root so Springboard and the installer can read them without CoreUI.",
                  required: false,
                  matches: { ($0 as NSString).lastPathComponent.hasPrefix("AppIcon") && $0.hasSuffix(".png") }),
            Entry(path: "_CodeSignature/CodeResources", kind: .signature, title: "Resource seal",
                  text: "A plist of SHA-1 and SHA-256 hashes for every non-executable file, plus rules marking optional or omitted paths. Editing any sealed file breaks launch.",
                  required: true,
                  matches: { $0.hasSuffix("_CodeSignature/CodeResources") }),
            Entry(path: "embedded.mobileprovision", kind: .provisioning, title: "Provisioning profile",
                  text: "CMS-signed plist binding the app ID, team, entitlements, certificates and — for development and ad hoc — the list of device UDIDs. Stripped from App Store copies.",
                  required: false,
                  matches: { $0.hasSuffix("embedded.mobileprovision") }),
            Entry(path: "Frameworks/", kind: .framework, title: "Embedded dynamic code",
                  text: "Third-party .framework and .dylib bundles, each separately signed. dyld loads all of them before main() runs, so the count directly affects cold-start time.",
                  required: false,
                  matches: { $0.contains("/Frameworks/") }),
            Entry(path: "PlugIns/", kind: .appExtension, title: "App extensions",
                  text: ".appex bundles — widgets, share sheets, intents, keyboards. Each has its own Info.plist with NSExtensionPointIdentifier, its own binary and its own signature.",
                  required: false,
                  matches: { $0.contains("/PlugIns/") }),
            Entry(path: "Watch/", kind: .watchApp, title: "Companion watchOS app",
                  text: "A complete watchOS application bundle, itself containing PlugIns/ for its extensions.",
                  required: false,
                  matches: { $0.contains("/Watch/") }),
            Entry(path: "*.lproj/", kind: .localization, title: "Localization folders",
                  text: "One folder per language holding Localizable.strings, .stringsdict and localized nibs. The set of folders is what the App Store lists as supported languages.",
                  required: false,
                  matches: { $0.contains(".lproj/") }),
            Entry(path: "*.bundle/", kind: .resourceBundle, title: "SDK resource bundles",
                  text: "Swift packages and CocoaPods ship their assets and PrivacyInfo.xcprivacy in resource-only bundles rather than merging them into the app.",
                  required: false,
                  matches: { $0.contains(".bundle/") }),
            Entry(path: "PkgInfo", kind: .text, title: "Legacy type code",
                  text: "Eight bytes — usually APPL???? — kept for compatibility with the classic Mac bundle format. Nothing on iOS reads it.",
                  required: false,
                  matches: { $0.hasSuffix("/PkgInfo") })
        ]
    }

    private var analysisAppName: String { analysis.app.name }

    private func presence(_ entry: Entry) -> Bool {
        analysis.payloadRoot.flattened().contains { entry.matches($0.relativePath) }
    }

    var body: some View {
        SectionScaffold(title: "Anatomy of an IPA",
                        subtitle: "The canonical layout, checked against this archive",
                        symbol: ExplorerSection.anatomy.symbol,
                        tint: ExplorerSection.anatomy.tint) {
            Card {
                Text("An iOS application archive is a ZIP with a fixed shape. Everything below is what a reviewer expects to find, why it is there, and whether this particular archive has it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(entries) { entry in
                let present = presence(entry)
                Card {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: entry.kind.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(entry.kind.color)
                            .frame(width: 36, height: 36)
                            .background(entry.kind.color.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 9) {
                                Text(entry.path)
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.primaryText)
                                Chip(text: entry.required ? "Required" : "Optional",
                                     tint: entry.required ? Theme.accent : Theme.tertiaryText)
                                Spacer()
                                Chip(text: present ? "Present" : "Absent",
                                     symbol: present ? "checkmark" : "minus",
                                     tint: present ? FileKind.localization.color : Theme.tertiaryText,
                                     filled: present)
                            }
                            Text(entry.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                            Text(entry.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.secondaryText.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
