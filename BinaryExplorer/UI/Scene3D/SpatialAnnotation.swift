//
//  SpatialAnnotation.swift
//  BinaryExplorer
//
//  Floating callouts for the 3D scenes. Labels are pre-rendered into textures
//  and parented to the object they describe, so they inherit every animation
//  and orbit the scene with it.
//

import SceneKit
import AppKit
import SwiftUI

/// How many callouts the scene shows at once.
enum SpatialLabelMode: String, CaseIterable, Identifiable {
    case off = "None"
    case hover = "On hover"
    case all = "All"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .off: return "tag.slash"
        case .hover: return "cursorarrow.rays"
        case .all: return "tag.fill"
        }
    }

    var help: String {
        switch self {
        case .off: return "Hide every callout"
        case .hover: return "Show a callout for the shape under the pointer"
        case .all: return "Label the most significant shapes at once"
        }
    }
}

/// Where a callout sits relative to the shape it describes.
enum AnnotationPlacement {
    /// Floats above the shape; `tier` staggers neighbours so they don't collide.
    case above
    /// Sits beside the shape, the way a diagram calls out a layer.
    case side(dx: CGFloat, dy: CGFloat)
    /// An explicit offset in the shape's own space — used for radial layouts.
    case offset(SCNVector3)
}

/// Everything needed to draw one callout, keyed by the scene node's name.
struct SpatialAnnotation {
    var nodeName: String
    var title: String
    var subtitle: String
    var color: NSColor
    /// Ranking weight — callouts are drawn heaviest-first.
    var weight: Double
    var placement: AnnotationPlacement = .above
    /// Multiplies the texture's pixels-per-unit: >1 renders a smaller callout,
    /// which is how a dense scene keeps its labels from swallowing the shapes.
    var density: CGFloat = 1
    /// False for shapes that are only labelled on hover, to keep `.all` legible.
    var showsWithAll: Bool = true
}

/// A built scene plus the annotation index that belongs to it.
struct SpatialSceneBundle {
    var scene: SCNScene
    var index: [String: SpatialAnnotation]
    /// Node names pre-labelled at build time, in descending weight order.
    var preLabelled: [String]
}

enum SpatialAnnotationRenderer {

    static let labelPrefix = "label:"
    /// Texture pixels per world unit — the plane is sized from the image.
    private static let pixelsPerUnit: CGFloat = 26

    // MARK: - Node construction

    /// Builds the callout node and parents it above `target`.
    @discardableResult
    static func attach(_ annotation: SpatialAnnotation, to target: SCNNode, rank: Int = 0) -> SCNNode {
        let image = render(annotation)
        let unit = pixelsPerUnit * annotation.density
        let width = image.size.width / unit
        let height = image.size.height / unit

        let plane = SCNPlane(width: width, height: height)
        plane.cornerRadius = 0
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.transparencyMode = .aOne
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = labelPrefix + annotation.nodeName
        node.castsShadow = false
        // Draw after the solids so a callout is never buried inside a building.
        node.renderingOrder = 100
        node.constraints = [SCNBillboardConstraint()]

        let (minBound, maxBound) = target.boundingBox
        let anchor: SCNVector3
        let position: SCNVector3
        switch annotation.placement {
        case .above:
            let stagger = CGFloat(rank % 8) * height * 1.15
            let lift = CGFloat(max(1.6, (maxBound.y - minBound.y) * 0.12)) + height * 0.6 + stagger
            anchor = SCNVector3(0, maxBound.y, 0)
            position = SCNVector3(0, CGFloat(maxBound.y) + lift, 0)
        case .side(let dx, let dy):
            let edge = dx < 0 ? minBound.x : maxBound.x
            anchor = SCNVector3(edge, (minBound.y + maxBound.y) / 2, 0)
            position = SCNVector3(CGFloat(edge) + dx + (dx < 0 ? -width / 2 : width / 2),
                                  CGFloat((minBound.y + maxBound.y) / 2) + dy,
                                  0)
        case .offset(let delta):
            anchor = SCNVector3(0, maxBound.y, 0)
            position = delta
        }
        node.position = position

        // A hairline leader ties the callout back to its shape.
        let stemNode = leader(from: anchor, to: position, color: annotation.color)

        let group = SCNNode()
        group.name = labelPrefix + annotation.nodeName
        group.addChildNode(stemNode)
        node.name = "callout"
        group.addChildNode(node)

        target.addChildNode(group)
        return group
    }

    /// A thin box stretched between the shape and its callout.
    private static func leader(from: SCNVector3, to: SCNVector3, color: NSColor) -> SCNNode {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = max(0.01, sqrt(dx * dx + dy * dy + dz * dz))

        let geometry = SCNBox(width: 0.11, height: CGFloat(length), length: 0.11, chamferRadius: 0)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color.dimmed(0.75).withAlphaComponent(0.8)
        material.writesToDepthBuffer = false
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "leader"
        node.renderingOrder = 99
        node.castsShadow = false
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        // Rotate the box's +Y axis onto the anchor→callout direction.
        node.eulerAngles = SCNVector3(
            Float.pi / 2 - atan2(Float(dy), sqrt(Float(dx * dx + dz * dz))),
            atan2(Float(dx), Float(dz)),
            0
        )
        return node
    }

    // MARK: - Visibility

    /// Applies the current label mode to an already-built scene.
    static func apply(mode: SpatialLabelMode,
                      hovered: String?,
                      bundle: SpatialSceneBundle) {
        let root = bundle.scene.rootNode
        let shown: Set<String>
        switch mode {
        case .off:
            shown = []
        case .hover:
            shown = hovered.map { [$0] } ?? []
        case .all:
            shown = Set(bundle.preLabelled.filter { bundle.index[$0]?.showsWithAll ?? false })
        }

        root.enumerateHierarchy { node, _ in
            guard let name = node.name, name.hasPrefix(labelPrefix) else { return }
            let target = String(name.dropFirst(labelPrefix.count))
            node.isHidden = !shown.contains(target)
        }

        // A shape outside the pre-labelled set still deserves a callout on hover.
        if mode == .hover, let hovered,
           root.childNode(withName: labelPrefix + hovered, recursively: true) == nil,
           let annotation = bundle.index[hovered],
           let target = root.childNode(withName: hovered, recursively: true) {
            attach(annotation, to: target)
        }
    }

    // MARK: - Selection

    private static let selectionName = "selection-cage"

    /// Wraps the selected shape in a wireframe cage. Applied imperatively so a
    /// click never rebuilds the scene — and never resets the camera.
    static func applySelection(nodeName: String?, in scene: SCNScene) {
        scene.rootNode.childNode(withName: selectionName, recursively: true)?.removeFromParentNode()
        guard let nodeName,
              let target = scene.rootNode.childNode(withName: nodeName, recursively: true) else { return }

        let (minBound, maxBound) = target.boundingBox
        let width = CGFloat(maxBound.x - minBound.x)
        let height = CGFloat(maxBound.y - minBound.y)
        let length = CGFloat(maxBound.z - minBound.z)
        guard width > 0, height > 0, length > 0 else { return }

        let cage = edgeCage(width: width * 1.09 + 0.25,
                            height: height * 1.06 + 0.25,
                            length: length * 1.09 + 0.25)

        let node = SCNNode(geometry: cage)
        node.name = selectionName
        node.castsShadow = false
        node.renderingOrder = 98
        node.position = SCNVector3((minBound.x + maxBound.x) / 2,
                                   (minBound.y + maxBound.y) / 2,
                                   (minBound.z + maxBound.z) / 2)
        node.opacity = 0.85
        node.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.35, duration: 0.7),
            .fadeOpacity(to: 0.9, duration: 0.7)
        ])))
        target.addChildNode(node)
    }

    /// The twelve edges of a box as line primitives. `SCNBox` with a `.lines`
    /// fill mode would also draw every triangulation diagonal.
    private static func edgeCage(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let x = Float(width / 2), y = Float(height / 2), z = Float(length / 2)
        let corners: [SCNVector3] = [
            SCNVector3(-x, -y, -z), SCNVector3(x, -y, -z), SCNVector3(x, -y, z), SCNVector3(-x, -y, z),
            SCNVector3(-x, y, -z), SCNVector3(x, y, -z), SCNVector3(x, y, z), SCNVector3(-x, y, z)
        ]
        let indices: [Int32] = [
            0, 1, 1, 2, 2, 3, 3, 0,
            4, 5, 5, 6, 6, 7, 7, 4,
            0, 4, 1, 5, 2, 6, 3, 7
        ]

        let source = SCNGeometrySource(vertices: corners)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.emission.contents = NSColor.white
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        geometry.materials = [material]
        return geometry
    }

    // MARK: - Texture

    private static func render(_ annotation: SpatialAnnotation) -> NSImage {
        let scale: CGFloat = 2
        let titleFont = NSFont.systemFont(ofSize: 15 * scale, weight: .semibold)
        let subtitleFont = NSFont.monospacedSystemFont(ofSize: 12 * scale, weight: .medium)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont, .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: annotation.color.blended(withFraction: 0.42, of: .white) ?? annotation.color
        ]

        let title = annotation.title as NSString
        let subtitle = annotation.subtitle as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)

        let dot: CGFloat = 9 * scale
        let paddingX: CGFloat = 14 * scale
        let paddingY: CGFloat = 9 * scale
        let gap: CGFloat = 3 * scale
        let contentWidth = max(titleSize.width, subtitleSize.width) + dot + 8 * scale
        let width = ceil(contentWidth + paddingX * 2)
        let height = ceil(titleSize.height + subtitleSize.height + gap + paddingY * 2)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let radius = height * 0.30
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5 * scale, dy: 1.5 * scale),
                                 xRadius: radius, yRadius: radius)

        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.11, alpha: 0.94).setFill()
        shape.fill()
        annotation.color.withAlphaComponent(0.85).setStroke()
        shape.lineWidth = 1.6 * scale
        shape.stroke()

        let dotRect = NSRect(x: paddingX,
                             y: height - paddingY - titleSize.height + (titleSize.height - dot) / 2,
                             width: dot, height: dot)
        annotation.color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let textX = paddingX + dot + 8 * scale
        title.draw(at: NSPoint(x: textX, y: height - paddingY - titleSize.height),
                   withAttributes: titleAttributes)
        subtitle.draw(at: NSPoint(x: textX, y: paddingY),
                      withAttributes: subtitleAttributes)

        return image
    }
}
