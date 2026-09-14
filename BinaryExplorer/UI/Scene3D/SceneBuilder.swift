//
//  SceneBuilder.swift
//  BinaryExplorer
//
//  Builds the three SceneKit scenes behind the Spatial tab. Every node that can
//  be selected carries its model identifier in `node.name`.
//

import SceneKit
import AppKit
import SwiftUI

enum SpatialMode: String, CaseIterable, Identifiable {
    case city = "Bundle City"
    case strata = "Binary Strata"
    case constellation = "Link Constellation"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .city: return "building.2.crop.circle.fill"
        case .strata: return "square.3.layers.3d"
        case .constellation: return "circle.hexagongrid.fill"
        }
    }

    var caption: String {
        switch self {
        case .city:
            return "Every file is a building. Footprint is its share of the payload, height is the log of its size, colour is its kind."
        case .strata:
            return "The main executable laid out as Mach-O segments and sections, stacked in file order."
        case .constellation:
            return "Libraries the executable links against, orbiting by origin: system frameworks outside, embedded code inside."
        }
    }
}

/// Identifies what a tapped node represents.
enum SpatialSelection: Equatable {
    case file(String)
    case section(String)
    case library(String)
}

enum SceneBuilder {

    static let boardSize: CGFloat = 100

    // MARK: - Shared staging

    private static func makeStage(radius: CGFloat) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.028, green: 0.034, blue: 0.062, alpha: 1)
        scene.fogColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.09, alpha: 1)
        scene.fogStartDistance = radius * 1.5
        scene.fogEndDistance = radius * 3.2
        scene.fogDensityExponent = 2

        // Key light — the only shadow caster, angled like a late-afternoon sun.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1150
        key.light?.color = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.92, alpha: 1)
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowRadius = 8
        key.light?.shadowSampleCount = 16
        key.light?.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        key.light?.orthographicScale = Double(radius * 1.6)
        key.light?.zFar = Double(radius * 8)
        key.position = SCNVector3(radius, radius * 1.6, radius)
        key.eulerAngles = SCNVector3(-Float.pi / 3.1, Float.pi / 4.4, 0)
        scene.rootNode.addChildNode(key)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 135
        ambient.light?.color = NSColor(calibratedRed: 0.40, green: 0.46, blue: 0.66, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Two coloured rims give the metal edges something to catch.
        for (offset, color) in [(SCNVector3(-radius * 0.8, radius * 1.5, -radius * 0.8),
                                 NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 1)),
                                (SCNVector3(radius * 0.8, radius * 1.3, -radius * 0.8),
                                 NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.62, alpha: 1))] {
            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .omni
            rim.light?.intensity = 260
            rim.light?.attenuationStartDistance = radius * 0.4
            rim.light?.attenuationEndDistance = radius * 1.6
            rim.light?.color = color
            rim.position = offset
            scene.rootNode.addChildNode(rim)
        }

        return scene
    }

    private static func addCamera(to scene: SCNScene, distance: CGFloat, height: CGFloat, target: CGFloat) {
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.4
        camera.zFar = Double(distance * 12)
        camera.wantsHDR = true
        camera.bloomIntensity = 0.32
        camera.bloomThreshold = 0.92
        camera.bloomBlurRadius = 10
        camera.wantsExposureAdaptation = false
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 4
        camera.contrast = 0.06
        camera.saturation = 1.06

        let node = SCNNode()
        node.camera = camera
        node.name = "camera"
        node.position = SCNVector3(0, height, distance)
        node.look(at: SCNVector3(0, target, 0))
        scene.rootNode.addChildNode(node)
    }

    private static func makeFloor(radius: CGFloat, tint: NSColor) -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.reflectionFalloffEnd = radius * 0.85
        floor.reflectionResolutionScaleFactor = 0.5

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor(calibratedRed: 0.030, green: 0.036, blue: 0.060, alpha: 1)
        floor.materials = [material]

        let node = SCNNode(geometry: floor)
        node.name = "floor"
        node.position = SCNVector3(0, -0.01, 0)
        return node
    }

    /// Faint concentric rings that give the empty floor a sense of scale.
    private static func addGroundRings(to parent: SCNNode, radius: CGFloat) {
        for step in 1...4 {
            let ringRadius = radius * CGFloat(step) / 4
            let torus = SCNTorus(ringRadius: ringRadius, pipeRadius: 0.055)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.95,
                                                alpha: 0.10 - Double(step) * 0.015)
            material.writesToDepthBuffer = false
            torus.materials = [material]
            let node = SCNNode(geometry: torus)
            node.position = SCNVector3(0, 0.02, 0)
            parent.addChildNode(node)
        }
    }

    private static func material(for color: NSColor, emissive: CGFloat = 0.14) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = 0.22
        material.roughness.contents = 0.36
        material.emission.contents = color.dimmed(emissive)
        return material
    }

    // MARK: - Mode 1: Bundle City

    static func buildCity(root: FileNode) -> SpatialSceneBundle {
        let scene = makeStage(radius: boardSize)
        let board = CGRect(x: -boardSize / 2, y: -boardSize / 2, width: boardSize, height: boardSize)

        let container = SCNNode()
        container.name = "content"
        scene.rootNode.addChildNode(container)
        container.addChildNode(makeFloor(radius: boardSize * 1.6,
                                         tint: NSColor(calibratedRed: 0.3, green: 0.45, blue: 0.9, alpha: 1)))

        let maxSize = Double(root.allFiles().map(\.size).max() ?? 1)
        var annotations: [SpatialAnnotation] = []
        place(node: root, in: board, depth: 0, parent: container,
              maxSize: maxSize, annotations: &annotations)

        addCamera(to: scene, distance: boardSize * 1.45, height: boardSize * 1.10, target: 5)
        return finish(scene: scene, annotations: annotations, labelCount: annotations.count)
    }

    /// Indexes the annotations and pre-attaches the heaviest ones.
    private static func finish(scene: SCNScene,
                               annotations: [SpatialAnnotation],
                               labelCount: Int) -> SpatialSceneBundle {
        let ranked = annotations.sorted { $0.weight > $1.weight }
        var index: [String: SpatialAnnotation] = [:]
        for annotation in ranked { index[annotation.nodeName] = annotation }

        var preLabelled: [String] = []
        for annotation in ranked.prefix(labelCount) {
            guard let target = scene.rootNode.childNode(withName: annotation.nodeName, recursively: true) else {
                continue
            }
            SpatialAnnotationRenderer.attach(annotation, to: target, rank: preLabelled.count)
            preLabelled.append(annotation.nodeName)
        }
        scene.rootNode.enumerateHierarchy { node, _ in
            if let name = node.name, name.hasPrefix(SpatialAnnotationRenderer.labelPrefix) {
                node.isHidden = true
            }
        }
        return SpatialSceneBundle(scene: scene, index: index, preLabelled: preLabelled)
    }

    private static func place(node: FileNode,
                              in rect: CGRect,
                              depth: Int,
                              parent: SCNNode,
                              maxSize: Double,
                              annotations: inout [SpatialAnnotation]) {
        // Below a pixel of footprint there is nothing worth drawing.
        guard rect.width > 0.35, rect.height > 0.35 else { return }

        let inset: CGFloat = depth == 0 ? 0 : max(0.12, min(0.6, rect.width * 0.02))
        let area = rect.insetBy(dx: inset, dy: inset)
        guard area.width > 0.2, area.height > 0.2 else { return }

        if node.isDirectory, depth < 4, !node.children.isEmpty {
            if depth > 0 { addDistrictPlate(for: node, rect: area, depth: depth, parent: parent) }
            let tiles = TreemapLayout.layout(node.sortedChildren, in: area) { Double(max($0.size, 1)) }
            for tile in tiles {
                place(node: tile.item, in: tile.rect, depth: depth + 1,
                      parent: parent, maxSize: maxSize, annotations: &annotations)
            }
            return
        }

        addBuilding(for: node, rect: area, maxSize: maxSize, parent: parent)
        // Small footprints get proportionally smaller callouts, otherwise the
        // long tail of tiny files buries the district it belongs to.
        let footprint = min(area.width, area.height)
        let density = max(1.0, min(3.0, 4.2 / max(footprint, 0.6)))
        annotations.append(SpatialAnnotation(nodeName: "file:" + node.relativePath,
                                             title: node.name,
                                             subtitle: "\(node.kind.title) · \(Format.bytes(node.size))",
                                             color: NSColor(node.kind.sceneColor),
                                             weight: Double(node.size),
                                             density: density))
    }

    private static func addDistrictPlate(for node: FileNode, rect: CGRect, depth: Int, parent: SCNNode) {
        let plate = SCNBox(width: rect.width, height: 0.14,
                           length: rect.height, chamferRadius: 0.05)
        let color = NSColor(node.kind.sceneColor)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color.withAlphaComponent(0.22)
        material.emission.contents = color.dimmed(0.10)
        material.metalness.contents = 0.6
        material.roughness.contents = 0.25
        plate.materials = [material]

        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(rect.midX, 0.07 + CGFloat(depth) * 0.02, rect.midY)
        plateNode.name = "file:" + node.relativePath
        plateNode.castsShadow = false
        parent.addChildNode(plateNode)
    }

    private static func addBuilding(for node: FileNode,
                                    rect: CGRect,
                                    maxSize: Double,
                                    parent: SCNNode) {
        // Log scaling keeps a 15 MB catalog from dwarfing a 4 KB plist entirely.
        let normalized = log2(Double(max(node.size, 1)) + 1) / log2(maxSize + 1)
        let height = CGFloat(1.2 + pow(normalized, 1.6) * 15)
        let box = SCNBox(width: rect.width, height: height,
                         length: rect.height, chamferRadius: min(0.28, rect.width * 0.12))

        let color = NSColor(node.kind.sceneColor)
        let side = material(for: color, emissive: 0.13)
        let top = material(for: color.blended(withFraction: 0.35, of: .white) ?? color,
                           emissive: 0.30)
        // SCNBox material order: front, right, back, left, top, bottom.
        box.materials = [side, side, side, side, top, side]

        let buildingNode = SCNNode(geometry: box)
        buildingNode.name = "file:" + node.relativePath
        buildingNode.position = SCNVector3(rect.midX, height / 2, rect.midY)
        buildingNode.castsShadow = true
        parent.addChildNode(buildingNode)
    }

    // MARK: - Mode 2: Binary Strata

    static func buildStrata(slice: MachOSlice) -> SpatialSceneBundle {
        let radius: CGFloat = 60
        let scene = makeStage(radius: radius)
        let container = SCNNode()
        container.name = "content"
        scene.rootNode.addChildNode(container)
        container.addChildNode(makeFloor(radius: radius * 2,
                                         tint: NSColor(calibratedRed: 0.9, green: 0.4, blue: 0.3, alpha: 1)))
        addGroundRings(to: container, radius: radius * 0.9)
        var annotations: [SpatialAnnotation] = []

        let segments = slice.segments.filter { $0.fileSize > 0 }
        let totalFile = max(1, segments.reduce(UInt64(0)) { $0 + max($1.fileSize, 1) })
        let towerHeight: CGFloat = 30
        var y: CGFloat = 0

        for segment in segments {
            let share = CGFloat(Double(max(segment.fileSize, 1)) / Double(totalFile))
            let slabHeight = max(0.9, share * towerHeight)
            let baseColor = NSColor(colorForSegment(segment.name))

            // The segment itself is a translucent shell around its sections.
            let shell = SCNBox(width: 30, height: slabHeight, length: 30, chamferRadius: 0.6)
            let shellMaterial = SCNMaterial()
            shellMaterial.lightingModel = .physicallyBased
            shellMaterial.diffuse.contents = baseColor.withAlphaComponent(0.17)
            shellMaterial.emission.contents = baseColor.dimmed(0.07)
            shellMaterial.metalness.contents = 0.75
            shellMaterial.roughness.contents = 0.2
            shellMaterial.transparencyMode = .dualLayer
            shell.materials = [shellMaterial]

            let shellNode = SCNNode(geometry: shell)
            shellNode.name = "section:" + segment.name
            shellNode.position = SCNVector3(0, y + slabHeight / 2, 0)
            container.addChildNode(shellNode)
            annotations.append(SpatialAnnotation(nodeName: "section:" + segment.name,
                                                 title: segment.name,
                                                 subtitle: "\(Format.bytes(segment.fileSize)) · \(segment.sections.count) sections · \(segment.protectionDescription)",
                                                 color: baseColor,
                                                 weight: Double(segment.fileSize) + 1e12,
                                                 placement: .side(dx: -13, dy: 0)))

            // Sections tile the slab as a treemap so their relative weight reads.
            var sectionLabelTier = 0
            let sections = segment.sections.filter { $0.size > 0 }
            if !sections.isEmpty {
                let plate = CGRect(x: -14, y: -14, width: 28, height: 28)
                let tiles = TreemapLayout.layout(sections, in: plate) { Double(max($0.size, 1)) }
                for tile in tiles {
                    let inner = tile.rect.insetBy(dx: 0.18, dy: 0.18)
                    guard inner.width > 0.1, inner.height > 0.1 else { continue }
                    let box = SCNBox(width: inner.width,
                                     height: max(0.5, slabHeight * 0.72),
                                     length: inner.height,
                                     chamferRadius: 0.12)
                    let tint = baseColor.blended(withFraction: 0.3, of: .white) ?? baseColor
                    box.materials = [material(for: tint, emissive: 0.18)]
                    let node = SCNNode(geometry: box)
                    node.name = "section:\(segment.name).\(tile.item.name)"
                    node.position = SCNVector3(inner.midX, y + slabHeight * 0.36, inner.midY)
                    container.addChildNode(node)
                    // Only the biggest sections earn a permanent callout; the
                    // rest appear on hover so the diagram stays readable.
                    annotations.append(SpatialAnnotation(nodeName: node.name!,
                                                         title: tile.item.name,
                                                         subtitle: "\(segment.name) · \(Format.bytes(tile.item.size))",
                                                         color: baseColor,
                                                         weight: Double(tile.item.size),
                                                         placement: .side(dx: sectionLabelTier % 2 == 0 ? 13 : 24,
                                                                          dy: CGFloat(sectionLabelTier - 2) * 5.2),
                                                         showsWithAll: tile.item.size > segment.fileSize / 8))
                    sectionLabelTier = (sectionLabelTier + 1) % 5
                }
            }

            y += slabHeight + 1.6
        }

        // Frame the whole stack with room for the callouts flanking it.
        let towerTop = y + 4
        addCamera(to: scene,
                  distance: max(radius, towerTop * 2.2),
                  height: towerTop * 0.62,
                  target: towerTop * 0.45)
        return finish(scene: scene, annotations: annotations, labelCount: annotations.count)
    }

    private static func colorForSegment(_ name: String) -> Color {
        switch name {
        case "__TEXT": return FileKind.executable.color
        case "__DATA", "__DATA_CONST", "__DATA_DIRTY": return FileKind.structuredData.color
        case "__LINKEDIT": return FileKind.signature.color
        case "__PAGEZERO": return FileKind.directory.color
        default: return FileKind.framework.sceneColor
        }
    }

    // MARK: - Mode 3: Link Constellation

    static func buildConstellation(slice: MachOSlice) -> SpatialSceneBundle {
        let radius: CGFloat = 92
        let scene = makeStage(radius: radius)
        let container = SCNNode()
        container.name = "content"
        scene.rootNode.addChildNode(container)
        addGroundRings(to: container, radius: radius)
        var annotations: [SpatialAnnotation] = []

        let core = SCNSphere(radius: 5.2)
        core.segmentCount = 64
        let coreMaterial = SCNMaterial()
        coreMaterial.lightingModel = .physicallyBased
        coreMaterial.diffuse.contents = NSColor(FileKind.executable.sceneColor)
        coreMaterial.emission.contents = NSColor(FileKind.executable.sceneColor).dimmed(0.55)
        coreMaterial.metalness.contents = 0.9
        coreMaterial.roughness.contents = 0.12
        core.materials = [coreMaterial]
        let coreNode = SCNNode(geometry: core)
        coreNode.position = SCNVector3(0, 16, 0)
        coreNode.name = "library:__executable"
        coreNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 28)))
        container.addChildNode(coreNode)
        annotations.append(SpatialAnnotation(nodeName: "library:__executable",
                                             title: "Main executable",
                                             subtitle: "\(slice.architecture) · \(slice.libraries.count) links",
                                             color: NSColor(FileKind.executable.sceneColor),
                                             weight: .greatestFiniteMagnitude,
                                             density: 1.5))

        // Three rings, innermost = code the app actually ships.
        let groups: [(String, [LinkedLibrary], CGFloat, CGFloat)] = [
            ("Embedded", slice.libraries.filter(\.isEmbedded), 20, 5),
            ("System frameworks", slice.libraries.filter { $0.origin.hasSuffix("framework") && !$0.isEmbedded }, 46, 20),
            ("System libraries", slice.libraries.filter { $0.origin == "System library" }, 74, 34)
        ]

        for (_, libraries, ringRadius, ringHeight) in groups where !libraries.isEmpty {
            let ring = SCNTorus(ringRadius: ringRadius, pipeRadius: 0.06)
            let ringMaterial = SCNMaterial()
            ringMaterial.lightingModel = .constant
            ringMaterial.diffuse.contents = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1, alpha: 0.18)
            ring.materials = [ringMaterial]
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(0, ringHeight, 0)
            container.addChildNode(ringNode)

            let orbit = SCNNode()
            orbit.position = SCNVector3(0, ringHeight, 0)
            container.addChildNode(orbit)
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2,
                                                     z: 0, duration: Double(ringRadius) * 5.5)))

            for (index, library) in libraries.enumerated() {
                let angle = CGFloat(index) / CGFloat(libraries.count) * .pi * 2
                let size: CGFloat = library.isEmbedded ? 2.1 : 1.35
                let geometry: SCNGeometry = library.kind == .weak
                    ? SCNBox(width: size * 1.5, height: size * 1.5, length: size * 1.5, chamferRadius: size * 0.4)
                    : SCNSphere(radius: size)

                let color = NSColor(library.isEmbedded
                                    ? FileKind.framework.sceneColor
                                    : (library.kind == .weak ? FileKind.interface.sceneColor : FileKind.dynamicLibrary.sceneColor))
                geometry.materials = [material(for: color, emissive: 0.30)]

                let node = SCNNode(geometry: geometry)
                node.name = "library:" + library.path
                node.position = SCNVector3(cos(angle) * ringRadius, 0, sin(angle) * ringRadius)
                orbit.addChildNode(node)
                // Fan the callout outwards along the body's own radius, in
                // three depth tiers so neighbours on a crowded ring miss each other.
                let tier = CGFloat(index % 3)
                let reach = 7.5 + tier * 5.5
                annotations.append(SpatialAnnotation(nodeName: node.name!,
                                                     title: library.name,
                                                     subtitle: "\(library.origin) · \(library.kind.rawValue)",
                                                     color: color,
                                                     weight: library.isEmbedded ? 1e9 : Double(1_000 - index),
                                                     placement: .offset(SCNVector3(cos(angle) * reach,
                                                                                   2.2 + tier * 1.4,
                                                                                   sin(angle) * reach)),
                                                     density: 1.75))

                // A thin strut back to the core makes the dependency explicit.
                let start = SCNVector3(node.position.x, ringHeight, node.position.z)
                orbit.addChildNode(connector(from: SCNVector3(node.position.x, 0, node.position.z),
                                             to: SCNVector3(0, 16 - ringHeight, 0),
                                             color: color,
                                             opacity: 0.14))
                _ = start
            }
        }

        addCamera(to: scene, distance: radius * 1.75, height: radius * 0.95, target: 14)
        return finish(scene: scene, annotations: annotations, labelCount: annotations.count)
    }

    private static func connector(from: SCNVector3, to: SCNVector3, color: NSColor, opacity: CGFloat) -> SCNNode {
        let delta = SCNVector3(to.x - from.x, to.y - from.y, to.z - from.z)
        let length = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
        guard length > 0.001 else { return SCNNode() }

        let cylinder = SCNBox(width: 0.09, height: CGFloat(length), length: 0.09, chamferRadius: 0)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color.withAlphaComponent(opacity)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        cylinder.materials = [material]

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        // Align the cylinder's +Y axis with the segment direction.
        node.eulerAngles = SCNVector3(
            Float.pi / 2 - atan2(Float(delta.y), sqrt(Float(delta.x * delta.x + delta.z * delta.z))),
            atan2(Float(delta.x), Float(delta.z)),
            0
        )
        return node
    }
}

extension NSColor {
    /// Scales the colour's components toward black. SceneKit's emission channel
    /// ignores alpha, so this is how a glow gets dimmed.
    func dimmed(_ factor: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        return NSColor(srgbRed: rgb.redComponent * factor,
                       green: rgb.greenComponent * factor,
                       blue: rgb.blueComponent * factor,
                       alpha: 1)
    }
}
