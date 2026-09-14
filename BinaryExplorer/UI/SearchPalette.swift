//
//  SearchPalette.swift
//  BinaryExplorer
//
//  ⌘F command palette over files, libraries, Mach-O sections, Info.plist keys,
//  entitlements and localizations.
//

import SwiftUI

struct SearchPalette: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var highlightedIndex = 0

    private var results: [SearchHit] { state.searchResults() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                TextField("Search files, frameworks, sections, keys…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { activateHighlighted() }
                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                Text("esc")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            Divider().opacity(0.35)

            if state.searchQuery.trimmingCharacters(in: .whitespaces).count < 2 {
                hintView
            } else if results.isEmpty {
                ContentUnavailableLabel(symbol: "questionmark.folder",
                                        title: "No matches",
                                        message: "Nothing in this bundle matches “\(state.searchQuery)”.")
                .frame(height: 240)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                                SearchRow(hit: hit, isHighlighted: index == highlightedIndex)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { state.focus(on: hit); dismiss() }
                                    .onHover { if $0 { highlightedIndex = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 380)
                    .onChange(of: highlightedIndex) { _, value in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) }
                    }
                }

                Divider().opacity(0.35)
                HStack(spacing: 16) {
                    legend("↑↓", "navigate")
                    legend("⏎", "open")
                    Spacer()
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .frame(width: 660)
        .background(.ultraThinMaterial)
        .background(Theme.canvasBottom.opacity(0.85))
        .onAppear { focused = true }
        .onChange(of: state.searchQuery) { _, _ in highlightedIndex = 0 }
        .onExitCommand { dismiss() }
        .background {
            // Invisible buttons give the palette real keyboard navigation.
            Group {
                Button("") { move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { move(1) }.keyboardShortcut(.downArrow, modifiers: [])
            }
            .opacity(0)
        }
    }

    private var hintView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEARCHES ACROSS")
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            ForEach([("doc.fill", "Every file in the payload, by name or path"),
                     ("cube.transparent.fill", "Linked libraries and embedded frameworks"),
                     ("square.stack.3d.up.fill", "Mach-O segments and sections"),
                     ("doc.text.fill", "Info.plist keys and values"),
                     ("checkmark.seal.fill", "Entitlements"),
                     ("globe", "Localizations")], id: \.1) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18)
                    Text(item.1)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private func legend(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlightedIndex = (highlightedIndex + delta + results.count) % results.count
    }

    private func activateHighlighted() {
        guard results.indices.contains(highlightedIndex) else { return }
        state.focus(on: results[highlightedIndex])
        dismiss()
    }
}

private struct SearchRow: View {
    let hit: SearchHit
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: hit.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hit.tint)
                .frame(width: 26, height: 26)
                .background(hit.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(hit.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(hit.destination.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Color.white.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .rowHighlight(isSelected: isHighlighted)
    }
}
