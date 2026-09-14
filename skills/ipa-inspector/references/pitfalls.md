# Pitfalls

Every entry here was a real bug in this project. Each cost at least one debug
cycle; most were silent — wrong output, no crash, no warning.

---

## Parsing

**ZIP central directory: skip 4, not 8.**
After the comment length at offset 32 come *disk number start* (2) and
*internal attributes* (2) — 4 bytes, not 8. Then external attributes (4) and
the local header offset (4). Skipping 8 shifts everything by four bytes and the
file names come back sliced mid-string (`oad/UX` instead of `Payload/…`).
Symptom: exactly one entry parsed, garbage path, absurd local header offset.

**`/var` is a symlink to `/private/var`.**
`FileManager.temporaryDirectory` hands back `/var/folders/…`; `contentsOfDirectory`
and `enumerator` hand back `/private/var/folders/…`. Computing a relative path
with `url.path.replacingOccurrences(of: root.path + "/", with: "")` then produces
`/privatePayload/Plan.app/…`. Compare **resolved** path components instead:

```swift
let rootComponents = root.resolvingSymlinksInPath().standardized.pathComponents
let urlComponents  = url.resolvingSymlinksInPath().standardized.pathComponents
```

This one hid inside the app because a sandboxed container's `tmp` has no
`/private` alias — it only appeared in the unsandboxed test harness. Anything
keyed by relative path (tree ids, 3D node names, hit testing) breaks.

**Certificate validity uses the Core Foundation epoch.**
`SecCertificateCopyValues` returns `kSecOIDX509V1ValidityNotAfter` as seconds
since 2001-01-01. `Date(timeIntervalSince1970:)` puts every certificate 31 years
in the past.

**Tuples are not `Hashable`.**
`var loadCommands: [(name: String, count: Int)]` silently blocks `Hashable`
conformance on the enclosing struct, and the error surfaces far away
("type 'MachOSlice' does not conform to protocol 'Hashable'"). Use a small struct.

**Advance load commands by `cmdsize` from the command start.**
Reading fields and letting the cursor land where it lands desynchronises on any
command with trailing data. Always `seek(to: commandStart + cmdsize)` and guard
that the cursor moved forward.

---

## SceneKit

**`emission` ignores the colour's alpha.**
`material.emission.contents = color.withAlphaComponent(0.14)` glows at **full**
saturation — the alpha is discarded. Every surface came out washed-out pastel
and the infinite floor plane rendered as a bright lavender sheet. Dim by scaling
the components instead:

```swift
func dimmed(_ factor: CGFloat) -> NSColor {
    guard let rgb = usingColorSpace(.sRGB) else { return self }
    return NSColor(srgbRed: rgb.redComponent * factor,
                   green: rgb.greenComponent * factor,
                   blue: rgb.blueComponent * factor, alpha: 1)
}
```

Diffuse alpha *is* honoured, so `withAlphaComponent` is still right for
transparency.

**A clear `SCNView` lets the SwiftUI background through.**
`view.backgroundColor = .clear` makes the window's gradient bleed into the
scene. Setting `scene.background.contents` does not override it — the view's own
background colour wins. Set `view.backgroundColor` to the intended dark colour.
(Test: set the scene background to magenta. If the frame is not magenta, the
scene background is not what you are seeing.)

**`SCNBox` + `fillMode = .lines` draws triangulation diagonals.**
For a selection cage you want the 12 box edges only. Build the geometry by hand:
8 vertices, 24 indices, `SCNGeometryElement(indices:primitiveType: .line)`.

**Overlay materials need the right depth settings.**
Billboarded callouts: `writesToDepthBuffer = false`, `readsFromDepthBuffer = false`,
`renderingOrder = 100` — they should float above everything. A selection cage
is the opposite: `readsFromDepthBuffer = true` so it hugs its shape instead of
drawing through the scene.

**Re-assigning `view.scene` resets the camera.**
So never rebuild the scene in response to selection or hover. Build once per
visualisation mode and mutate imperatively — toggle `isHidden` on pre-built
label nodes, attach/remove a selection cage. Keep the selection out of whatever
token drives the rebuild.

**Bloom and HDR blow out an already-emissive scene.**
`bloomIntensity 0.32 / threshold 0.92` reads well on a dark stage; `0.55 / 0.78`
turned every face into a glow.

---

## AppKit / SwiftUI

**`@objc func mouseMoved(with:)` on a non-`NSResponder` gets the wrong selector.**
Swift maps it to `mouseMovedWith:`. AppKit only ever sends `mouseMoved:`, so an
`NSTrackingArea` whose owner is a plain `NSObject` (an `NSViewRepresentable.Coordinator`,
say) silently receives nothing. Spell the selector out:

```swift
@objc(mouseMoved:)
func mouseMoved(with event: NSEvent) { … }

@objc(mouseExited:)
func mouseExited(with event: NSEvent) { … }
```

Subclassing `NSResponder` also works, because then they are real overrides.

**Background apps get no `mouseMoved` events.**
`.activeAlways` on the tracking area governs enter/exit, not motion. This only
bites synthetic-input testing: if the app is not frontmost, posting a
`CGEvent(.mouseMoved)` produces nothing. Re-activate with `open -a` immediately
before driving the pointer.

**An asynchronously built scene needs identity comparison, not a token.**
`updateNSView` that swaps `view.scene` only when a string token changes will
never install the real scene if the first render handed it a placeholder under
the *same* token. Compare `installedScene !== bundle.scene`.

**Do not build expensive objects inside a computed property read by `body`.**
A `var bundle: SpatialSceneBundle { … build … }` runs on every redraw and hands
the representable a fresh object each time, so imperative updates land on an
orphan. Build in `.task(id:)` and hold the result in `@State`.

**`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** (Xcode 26's default for new
projects) makes every type in the module main-actor isolated, which fights
parsing on a detached task. Set it to `nonisolated`; SwiftUI views are
main-actor by protocol conformance anyway, and `AppState` carries an explicit
`@MainActor`.

**`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`** means transitive imports
no longer leak. `@Published` / `ObservableObject` need an explicit
`import Combine`; `UTType.fileURL` needs `import UniformTypeIdentifiers`.

**Capturing `weak self` for a `Task` inside an escaping closure.**
`{ [weak self] in Task { @MainActor in self?.f() } }` warns about a captured
`var`. Put the capture list on the `Task`:
`Task { @MainActor [weak self] in self?.f() }`.

---

## Xcode project

**`Info.plist` inside a `PBXFileSystemSynchronizedRootGroup` is copied as a
resource.** Xcode warns "The Copy Bundle Resources build phase contains this
target's Info.plist file". Keep it outside the synchronized folder — at the repo
root — and point `INFOPLIST_FILE` at it. `GENERATE_INFOPLIST_FILE = YES` still
merges the `INFOPLIST_KEY_*` settings into it.

**Converting an iOS target to macOS** by hand: `SDKROOT = macosx`,
`IPHONEOS_DEPLOYMENT_TARGET` → `MACOSX_DEPLOYMENT_TARGET`, delete
`TARGETED_DEVICE_FAMILY` and every `INFOPLIST_KEY_UI*`, add
`COMBINE_HIDPI_IMAGES = YES` and `CODE_SIGN_ENTITLEMENTS`.

**Sandbox entitlements needed:** `com.apple.security.app-sandbox` and
`com.apple.security.files.user-selected.read-only`. Wrap the opened URL in
`startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.

**Document types** (so Finder can open `.ipa`) need a real `Info.plist` with
`CFBundleDocumentTypes` + `UTImportedTypeDeclarations` for
`com.apple.itunes.ipa`, and an `NSApplicationDelegate` implementing
`application(_:open:)`. Set `AppDelegate.state` from `.onAppear` so the delegate
can reach the store.
