//
//  Theme.swift
//  BinaryExplorer
//
//  The visual language: a deep-space palette, glass cards and the small
//  primitives every section is assembled from.
//

import SwiftUI

enum Theme {
    static let accent = Color(red: 0.38, green: 0.62, blue: 1.00)
    static let accentWarm = Color(red: 1.00, green: 0.46, blue: 0.38)
    static let accentMint = Color(red: 0.36, green: 0.86, blue: 0.68)
    static let accentViolet = Color(red: 0.66, green: 0.48, blue: 1.00)

    static let canvasTop = Color(red: 0.055, green: 0.065, blue: 0.11)
    static let canvasBottom = Color(red: 0.025, green: 0.032, blue: 0.06)

    static let cardStroke = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.06)

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.38)

    static var canvas: LinearGradient {
        LinearGradient(colors: [canvasTop, canvasBottom],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    static func accentGradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.55)],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }
}

// MARK: - Backdrop

/// The app-wide background: a gradient plus two soft colour blooms.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.canvas
            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height)
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.28), .clear],
                                         center: .center, startRadius: 0, endRadius: side * 0.45))
                    .frame(width: side, height: side)
                    .offset(x: -side * 0.32, y: -side * 0.38)
                Circle()
                    .fill(RadialGradient(colors: [Theme.accentViolet.opacity(0.22), .clear],
                                         center: .center, startRadius: 0, endRadius: side * 0.4))
                    .frame(width: side * 0.9, height: side * 0.9)
                    .offset(x: side * 0.42, y: side * 0.34)
            }
            .blur(radius: 40)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var symbol: String?
    var tint: Color = Theme.accent
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 16) {
            if let title {
                HStack(spacing: 10) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 26, height: 26)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.55))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    var label: String
    var value: String
    var detail: String?
    var symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Rows and chips

struct KeyValueRow: View {
    var key: String
    var value: String
    var monospaced: Bool = false
    var tint: Color?
    var selectable: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(key)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 200, alignment: .leading)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 11.5, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(tint ?? Theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
    }
}

struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(filled ? Color.black.opacity(0.85) : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
        )
        .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.3), lineWidth: 1))
    }
}

/// Horizontal proportion bar used for size breakdowns.
struct ProportionBar: View {
    var segments: [(color: Color, value: Double)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(Theme.accentGradient(segment.color))
                        .frame(width: max(1, proxy.size.width * segment.value / total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accentGradient(tint))
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Explains a concept inline — used for the IPA anatomy notes.
struct NoteBlock: View {
    var text: String
    var symbol: String = "text.book.closed.fill"
    var tint: Color = Theme.accentMint

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(tint.opacity(0.16), lineWidth: 1))
    }
}

// MARK: - Layout helpers

struct SectionScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                    .padding(.bottom, 2)
                content
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
    }
}

extension View {
    /// Uniform hover affordance for list rows and grid cells.
    func rowHighlight(isSelected: Bool, tint: Color = Theme.accent) -> some View {
        background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tint.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}
