//
//  FileKind.swift
//  BinaryExplorer
//
//  Classification of everything found inside a bundle, plus the palette that
//  keeps the tree, the charts and the 3D scene colour-consistent.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum FileKind: String, CaseIterable, Identifiable {
    case executable
    case framework
    case dynamicLibrary
    case appExtension
    case watchApp
    case resourceBundle
    case assetCatalog
    case image
    case vector
    case interface
    case localization
    case font
    case structuredData
    case propertyList
    case database
    case media
    case shader
    case machineLearning
    case animation
    case privacyManifest
    case provisioning
    case signature
    case archive
    case text
    case directory
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .executable: return "Executable"
        case .framework: return "Framework"
        case .dynamicLibrary: return "Dynamic library"
        case .appExtension: return "App extension"
        case .watchApp: return "Watch app"
        case .resourceBundle: return "Resource bundle"
        case .assetCatalog: return "Asset catalog"
        case .image: return "Image"
        case .vector: return "Vector"
        case .interface: return "Interface"
        case .localization: return "Localization"
        case .font: return "Font"
        case .structuredData: return "Structured data"
        case .propertyList: return "Property list"
        case .database: return "Database"
        case .media: return "Media"
        case .shader: return "Shader library"
        case .machineLearning: return "ML model"
        case .animation: return "Animation"
        case .privacyManifest: return "Privacy manifest"
        case .provisioning: return "Provisioning"
        case .signature: return "Code signature"
        case .archive: return "Archive"
        case .text: return "Text"
        case .directory: return "Folder"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .executable: return "terminal.fill"
        case .framework: return "shippingbox.fill"
        case .dynamicLibrary: return "cube.transparent.fill"
        case .appExtension: return "puzzlepiece.extension.fill"
        case .watchApp: return "applewatch"
        case .resourceBundle: return "archivebox.fill"
        case .assetCatalog: return "photo.stack.fill"
        case .image: return "photo.fill"
        case .vector: return "scribble.variable"
        case .interface: return "rectangle.3.group.fill"
        case .localization: return "globe"
        case .font: return "textformat"
        case .structuredData: return "curlybraces"
        case .propertyList: return "list.bullet.rectangle.fill"
        case .database: return "cylinder.split.1x2.fill"
        case .media: return "play.rectangle.fill"
        case .shader: return "sparkles.rectangle.stack.fill"
        case .machineLearning: return "brain.head.profile"
        case .animation: return "wand.and.stars"
        case .privacyManifest: return "hand.raised.fill"
        case .provisioning: return "signature"
        case .signature: return "checkmark.seal.fill"
        case .archive: return "doc.zipper"
        case .text: return "doc.text.fill"
        case .directory: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    /// Chart colour. The eight slots that carry `themeIndex` form the validated
    /// categorical theme (OKLCH-stepped, CVD-checked against the dark surface);
    /// the remaining kinds are steps off the same hue families and only appear
    /// where a label or icon rides alongside the swatch.
    var color: Color {
        switch self {
        case .executable: return Color(hex: 0xC33029)
        case .framework: return Color(hex: 0x0069CD)
        case .dynamicLibrary: return Color(hex: 0x4299E5)
        case .appExtension: return Color(hex: 0x905CD9)
        case .watchApp: return Color(hex: 0x8D34A5)
        case .resourceBundle: return Color(hex: 0x3C6293)
        case .assetCatalog: return Color(hex: 0x905C01)
        case .image: return Color(hex: 0xC48001)
        case .vector: return Color(hex: 0xDB6C44)
        case .interface: return Color(hex: 0x009E92)
        case .localization: return Color(hex: 0x27A83A)
        case .font: return Color(hex: 0x9A82DB)
        case .structuredData: return Color(hex: 0x00A5B3)
        case .propertyList: return Color(hex: 0x00768A)
        case .database: return Color(hex: 0x00736E)
        case .media: return Color(hex: 0xBC3682)
        case .shader: return Color(hex: 0x4D7800)
        case .machineLearning: return Color(hex: 0xBA6ABF)
        case .animation: return Color(hex: 0xD56C98)
        case .privacyManifest: return Color(hex: 0x238C47)
        case .provisioning: return Color(hex: 0x728295)
        case .signature: return Color(hex: 0x49AB64)
        case .archive: return Color(hex: 0xA16733)
        case .text: return Color(hex: 0x7B95A2)
        case .directory: return Color(hex: 0x516D81)
        case .other: return Color(hex: 0x6E8393)
        }
    }

    /// Brightened variant used for SceneKit emission, where the material is lit
    /// rather than printed and the chart lightness band no longer applies.
    var sceneColor: Color {
        switch self {
        case .executable: return Color(hex: 0xF86B5E)
        case .framework: return Color(hex: 0x4C9CFF)
        case .dynamicLibrary: return Color(hex: 0x94CAFE)
        case .appExtension: return Color(hex: 0xBD96FF)
        case .watchApp: return Color(hex: 0xBE6AD7)
        case .resourceBundle: return Color(hex: 0x6B92C3)
        case .assetCatalog: return Color(hex: 0xCF8700)
        case .image: return Color(hex: 0xFBB24D)
        case .vector: return Color(hex: 0xFFAA8D)
        case .interface: return Color(hex: 0x0FD7C6)
        case .localization: return Color(hex: 0x6BDB72)
        case .font: return Color(hex: 0xC8B8FE)
        case .structuredData: return Color(hex: 0x03DDEF)
        case .propertyList: return Color(hex: 0x20AAC4)
        case .database: return Color(hex: 0x02A8A2)
        case .media: return Color(hex: 0xF16EB2)
        case .shader: return Color(hex: 0x73AC18)
        case .machineLearning: return Color(hex: 0xED9EF2)
        case .animation: return Color(hex: 0xFEA5C8)
        case .privacyManifest: return Color(hex: 0x62BD78)
        case .provisioning: return Color(hex: 0xA3B3C6)
        case .signature: return Color(hex: 0x81DC96)
        case .archive: return Color(hex: 0xD29868)
        case .text: return Color(hex: 0xAEC7D4)
        case .directory: return Color(hex: 0x819CB0)
        case .other: return Color(hex: 0x9FB4C4)
        }
    }

    /// Position in the validated categorical theme, or nil for the long tail.
    var themeIndex: Int? {
        switch self {
        case .executable: return 6
        case .framework: return 7
        case .appExtension: return 2
        case .assetCatalog: return 4
        case .interface: return 3
        case .localization: return 1
        case .structuredData: return 5
        case .media: return 0
        default: return nil
        }
    }

    /// Kinds ordered the way a legend should list them.
    static var themeOrdered: [FileKind] {
        allCases.filter { $0.themeIndex != nil }.sorted { ($0.themeIndex ?? 0) < ($1.themeIndex ?? 0) }
    }

    /// What this file does in an iOS bundle — shown in the inspector.
    var explanation: String {
        switch self {
        case .executable:
            return "The compiled Mach-O binary that the system loads at launch. On the App Store it is re-signed and, for older submissions, FairPlay-encrypted."
        case .framework:
            return "A dynamically linked framework copied into Frameworks/. Each one is loaded by dyld at launch and counts against startup time."
        case .dynamicLibrary:
            return "A dynamic library loaded at runtime through dyld."
        case .appExtension:
            return "An .appex bundle in PlugIns/ — a widget, share sheet, keyboard or intent extension with its own binary and Info.plist."
        case .watchApp:
            return "A companion watchOS application embedded under Watch/."
        case .resourceBundle:
            return "A resource-only bundle, typically produced by a Swift package or CocoaPod to carry its assets and privacy manifest."
        case .assetCatalog:
            return "Compiled Assets.car — images, colours, app icons and symbols packed in Apple's CAR/BOM container and read through CoreUI."
        case .image:
            return "A loose raster image shipped outside the asset catalog. App icons must stay loose for the installer to find them."
        case .vector:
            return "A vector resource — PDF or SVG — resolved at runtime or at build time."
        case .interface:
            return "Compiled Interface Builder output: .nib and .storyboardc archives produced by ibtool."
        case .localization:
            return "Localized strings inside an .lproj folder. The set of .lproj folders defines which languages the App Store lists."
        case .font:
            return "A font file that must also be declared under UIAppFonts to be usable."
        case .structuredData:
            return "JSON or similar structured data bundled as a resource."
        case .propertyList:
            return "A property list — configuration or metadata, either XML or Apple's binary plist format."
        case .database:
            return "A prepopulated database (SQLite / Core Data / Realm) shipped with the app."
        case .media:
            return "Audio or video media bundled with the app."
        case .shader:
            return "A compiled Metal shader library (default.metallib) produced from .metal sources."
        case .machineLearning:
            return "A compiled Core ML model bundle."
        case .animation:
            return "A vector animation resource such as a Lottie JSON payload."
        case .privacyManifest:
            return "PrivacyInfo.xcprivacy — declares collected data, tracking domains and required-reason API usage. Apple requires it from common SDKs."
        case .provisioning:
            return "embedded.mobileprovision — the signed profile that ties the bundle ID, entitlements, certificates and devices together."
        case .signature:
            return "_CodeSignature/CodeResources — the manifest of per-file hashes that the system verifies at install and launch."
        case .archive:
            return "A nested archive shipped as a resource."
        case .text:
            return "Plain text or markup resource."
        case .directory:
            return "A folder inside the bundle."
        case .other:
            return "An unrecognised resource."
        }
    }

    static func classify(url: URL, isDirectory: Bool) -> FileKind {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if isDirectory {
            switch ext {
            case "app": return .watchApp                    // refined by the analyzer
            case "appex": return .appExtension
            case "framework": return .framework
            case "bundle": return .resourceBundle
            case "lproj": return .localization
            case "storyboardc", "nib": return .interface
            case "mlmodelc": return .machineLearning
            case "xcassets": return .assetCatalog
            case "scnassets": return .media
            default:
                return name == "_CodeSignature" ? .signature : .directory
            }
        }

        if name == "PrivacyInfo.xcprivacy" { return .privacyManifest }
        if name == "embedded.mobileprovision" { return .provisioning }
        if name == "CodeResources" || name == "CodeDirectory" { return .signature }
        if name == "Assets.car" { return .assetCatalog }
        if name.hasSuffix(".lottie") { return .animation }

        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "ktx", "astc":
            return .image
        case "pdf", "svg":
            return .vector
        case "nib", "storyboardc", "storyboard", "xib":
            return .interface
        case "strings", "stringsdict", "loctable":
            return .localization
        case "ttf", "otf", "ttc", "woff", "woff2":
            return .font
        case "json", "geojson", "yaml", "yml", "xml", "csv", "proto", "pb":
            return .structuredData
        case "plist", "xcprivacy", "appintents", "car":
            return ext == "car" ? .assetCatalog : .propertyList
        case "db", "sqlite", "sqlite3", "realm", "momd", "mom":
            return .database
        case "mp3", "mp4", "m4a", "mov", "wav", "aac", "caf", "aiff", "webm":
            return .media
        case "metallib", "metal", "air":
            return .shader
        case "mlmodel", "mlmodelc", "mlpackage", "espresso":
            return .machineLearning
        case "dylib", "a", "so", "tbd":
            return .dynamicLibrary
        case "zip", "bundle", "tar", "gz", "lz4":
            return .archive
        case "txt", "md", "html", "css", "js", "license", "rtf":
            return .text
        case "":
            return .other
        default:
            return .other
        }
    }
}
