//
//  WelcomeView.swift
//  BinaryExplorer
//
//  The empty state: a slowly turning wireframe cube over the drop target.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var spin: Double = 0

    private let capabilities: [(String, String, String, Color)] = [
        ("cube.transparent.fill", "Spatial view",
         "A 3D treemap city of the payload, Mach-O strata and a link constellation.", Theme.accentViolet),
        ("cpu.fill", "Mach-O parser",
         "Slices, segments, sections, load commands, encryption and chained fixups.", Theme.accentWarm),
        ("checkmark.seal.fill", "Trust chain",
         "Code directory, entitlements, CMS signers and the provisioning profile.", Theme.accentMint),
        ("photo.stack.fill", "Resource viewer",
         "Preview images, property lists, strings, fonts, media and raw bytes.", Color(red: 1, green: 0.72, blue: 0.3))
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.35), .clear],
                                         center: .center, startRadius: 4, endRadius: 190))
                    .frame(width: 380, height: 380)
                    .blur(radius: 22)

                WireCube(rotation: spin)
                    .stroke(LinearGradient(colors: [Theme.accent, Theme.accentViolet],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .frame(width: 220, height: 220)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 16)
            }
            .frame(height: 300)
            .onAppear {
                withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                    spin = 360
                }
            }

            VStack(spacing: 10) {
                Text("Binary Explorer")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.accent.opacity(0.85)],
                                                    startPoint: .top, endPoint: .bottom))
                Text("Drop an .ipa here to take an iOS application apart —\nbundle, binary, signature and every resource inside it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 12) {
                Button {
                    state.openPanel()
                } label: {
                    Label("Choose an IPA…", systemImage: "folder.badge.plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)

                Text("or drag it into the window")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.top, 22)

            HStack(alignment: .top, spacing: 14) {
                ForEach(capabilities, id: \.1) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: item.0)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(item.3)
                            .frame(width: 32, height: 32)
                            .background(item.3.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(item.1)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(item.2)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: 210, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.cardStroke, lineWidth: 1))
                }
            }
            .padding(.top, 34)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An isometric cube whose vertices are rotated in software — cheap, and it
/// keeps the welcome screen from spinning up a full SceneKit renderer.
private struct WireCube: Shape {
    var rotation: Double

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let vertices: [(Double, Double, Double)] = [
            (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)
        ]
        let edges = [(0, 1), (1, 2), (2, 3), (3, 0),
                     (4, 5), (5, 6), (6, 7), (7, 4),
                     (0, 4), (1, 5), (2, 6), (3, 7)]

        let yaw = rotation * .pi / 180
        let pitch = 0.62
        let scale = min(rect.width, rect.height) * 0.34
        let center = CGPoint(x: rect.midX, y: rect.midY)

        func project(_ v: (Double, Double, Double)) -> CGPoint {
            let x1 = v.0 * cos(yaw) - v.2 * sin(yaw)
            let z1 = v.0 * sin(yaw) + v.2 * cos(yaw)
            let y1 = v.1 * cos(pitch) - z1 * sin(pitch)
            let z2 = v.1 * sin(pitch) + z1 * cos(pitch)
            let perspective = 3.4 / (3.4 + z2)
            return CGPoint(x: center.x + x1 * scale * perspective,
                           y: center.y + y1 * scale * perspective)
        }

        var path = Path()
        for edge in edges {
            path.move(to: project(vertices[edge.0]))
            path.addLine(to: project(vertices[edge.1]))
        }
        return path
    }
}
