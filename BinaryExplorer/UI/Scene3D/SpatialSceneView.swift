//
//  SpatialSceneView.swift
//  BinaryExplorer
//
//  SwiftUI wrapper around SCNView: orbit controls, click-to-select hit testing
//  and a slow idle rotation that stops as soon as the user grabs the camera.
//

import SwiftUI
import SceneKit

struct SpatialSceneView: NSViewRepresentable {
    let bundle: SpatialSceneBundle
    /// Bumped by the owner whenever the scene must be re-installed.
    let sceneToken: String
    var autoRotate: Bool
    var labelMode: SpatialLabelMode
    var hoveredNodeName: String?
    var selectedNodeName: String?
    var onSelect: (SpatialSelection) -> Void
    var onHover: (SpatialSelection?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SCNView {
        let view = ClickThroughSCNView()
        view.scene = bundle.scene
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.inertiaFriction = 0.08
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = true
        view.rendersContinuously = false
        view.backgroundColor = NSColor(calibratedRed: 0.028, green: 0.034, blue: 0.062, alpha: 1)

        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(click)

        context.coordinator.install(on: view)
        context.coordinator.currentToken = sceneToken
        context.coordinator.installedScene = bundle.scene
        context.coordinator.applyAutoRotation(autoRotate, on: view)
        context.coordinator.applyLabels(bundle: bundle, mode: labelMode, hovered: hoveredNodeName)
        context.coordinator.applySelection(selectedNodeName, in: bundle.scene)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        // Compare scene identity, not just the token: the first render hands us a
        // placeholder while the real scene is still being built off the token.
        if context.coordinator.installedScene !== bundle.scene {
            context.coordinator.currentToken = sceneToken
            context.coordinator.installedScene = bundle.scene
            context.coordinator.resetLabelSignature()
            // Re-installing the scene resets the camera, which is what we want
            // when the user switches visualisation modes.
            view.scene = bundle.scene
            view.pointOfView = bundle.scene.rootNode.childNode(withName: "camera", recursively: true)
        }
        context.coordinator.applyAutoRotation(autoRotate, on: view)
        view.window?.acceptsMouseMovedEvents = true
        var needsRedraw = context.coordinator.applyLabels(bundle: bundle,
                                                          mode: labelMode,
                                                          hovered: hoveredNodeName)
        needsRedraw = context.coordinator.applySelection(selectedNodeName, in: bundle.scene) || needsRedraw
        if needsRedraw { view.setNeedsDisplay(view.bounds) }
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        var parent: SpatialSceneView
        var currentToken: String = ""
        weak var installedScene: SCNScene?
        private var labelSignature: String = ""
        private var selectionSignature: String?

        func resetLabelSignature() {
            labelSignature = ""
            selectionSignature = nil
        }

        @discardableResult
        func applySelection(_ nodeName: String?, in scene: SCNScene) -> Bool {
            guard nodeName != selectionSignature else { return false }
            selectionSignature = nodeName
            SpatialAnnotationRenderer.applySelection(nodeName: nodeName, in: scene)
            return true
        }
        private weak var trackedView: SCNView?
        private var trackingArea: NSTrackingArea?
        private var lastHovered: String?

        init(_ parent: SpatialSceneView) {
            self.parent = parent
        }

        func install(on view: SCNView) {
            trackedView = view
            let area = NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                      owner: self,
                                      userInfo: nil)
            view.addTrackingArea(area)
            trackingArea = area
        }

        func teardown() {
            if let view = trackedView, let area = trackingArea {
                view.removeTrackingArea(area)
            }
            trackedView = nil
            trackingArea = nil
        }

        /// Re-applies callout visibility only when the request actually changed —
        /// hover fires on every mouse move.
        @discardableResult
        func applyLabels(bundle: SpatialSceneBundle, mode: SpatialLabelMode, hovered: String?) -> Bool {
            let signature = "\(currentToken)|\(mode.rawValue)|\(hovered ?? "")"
            guard signature != labelSignature else { return false }
            labelSignature = signature
            SpatialAnnotationRenderer.apply(mode: mode, hovered: hovered, bundle: bundle)
            return true
        }

        func applyAutoRotation(_ enabled: Bool, on view: SCNView) {
            guard let root = view.scene?.rootNode.childNode(withName: "content", recursively: false) else {
                return
            }
            let key = "idle-rotation"
            if enabled {
                guard root.action(forKey: key) == nil else { return }
                root.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)), forKey: key)
            } else {
                root.removeAction(forKey: key)
            }
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            let point = recognizer.location(in: view)
            guard let selection = selection(at: point, in: view) else { return }
            parent.onSelect(selection)
        }

        @objc(mouseMoved:)
        func mouseMoved(with event: NSEvent) {
            guard let view = trackedView else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            let hit = selection(at: point, in: view)
            let identifier = hit.map(String.init(describing:))
            guard identifier != lastHovered else { return }
            lastHovered = identifier
            parent.onHover(hit)
        }

        @objc(mouseExited:)
        func mouseExited(with event: NSEvent) {
            lastHovered = nil
            parent.onHover(nil)
        }

        private func selection(at point: CGPoint, in view: SCNView) -> SpatialSelection? {
            let results = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true
            ])
            for result in results {
                var node: SCNNode? = result.node
                while let current = node {
                    if let name = current.name {
                        if let value = name.stripping("file:") { return .file(value) }
                        if let value = name.stripping("section:") { return .section(value) }
                        if let value = name.stripping("library:") { return .library(value) }
                    }
                    node = current.parent
                }
            }
            return nil
        }
    }
}

/// SCNView swallows first-responder clicks by default; this keeps selection
/// working even when the window is not key.
private final class ClickThroughSCNView: SCNView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension String {
    func stripping(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
