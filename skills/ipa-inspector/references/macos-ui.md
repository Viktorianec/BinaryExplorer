# macOS UI: SceneKit, palette, testing

## The three spatial modes

All three are built by `SceneBuilder` and returned as a `SpatialSceneBundle`
(`scene`, an annotation `index` keyed by node name, and the list of
pre-labelled node names). Every selectable node carries its model identifier in
`node.name`, prefixed `file:`, `section:` or `library:` — that prefix is the
whole hit-testing protocol.

| Mode | Metaphor | Layout |
|------|----------|--------|
| Bundle City | every file is a building | squarified treemap; footprint = share of payload, height = `1.2 + normalized^1.6 * 15` |
| Binary Strata | the executable as layers | segments stacked by file-size share; sections tile each slab as a nested treemap |
| Link Constellation | what dyld loads | three rings by origin — embedded inside, system frameworks, system libraries |

### Treemap

Squarified treemap (Bruls, Huizing & van Wijk): rows are grown while the worst
aspect ratio improves, then flushed. Recursion stops at depth 4 or when a cell
falls below ~0.35 units, which keeps a 191-file payload at a few hundred nodes.

Heights are logarithmic and deliberately compressed. Footprint already encodes
size proportionally; letting height encode it linearly too turns the two files
that own 80 % of an IPA into monoliths that hide everything else.

### Camera

`addCamera(to:distance:height:target:)`. Fit is the thing that keeps going
wrong — derive it from the content, not from a constant:

- City: `distance = board * 1.45`, `height = board * 1.10`, `target = 5`.
- Strata: measure the built tower, then
  `distance = max(radius, towerTop * 2.2)`, `height = towerTop * 0.62`,
  `target = towerTop * 0.45`. Hard-coding this clips the bottom slab.
- Constellation: `distance = radius * 1.75`, `height = radius * 0.95`.

Rule of thumb at a 42° vertical FOV: to fit height *H* you need at least
`H * 1.3` of distance, and the **near** edge of a tilted board subtends far more
than the centre does.

### Lighting

One directional key light with `shadowMode = .deferred` is the only shadow
caster. Ambient stays low (≈135). Rim lights sit high above the board with a
short attenuation range, otherwise they pool on the infinite floor plane. The
floor itself uses `lightingModel = .constant` so it cannot be lit at all —
that, plus fog pulled in to `radius * 1.5 … 3.2`, is what keeps the horizon dark.

### Annotations

`SpatialAnnotationRenderer` pre-renders each callout into an `NSImage`
(rounded pill, colour dot, title, monospaced subtitle) and maps it onto an
`SCNPlane` with a `SCNBillboardConstraint`. The node is parented to the shape it
describes, so it inherits every animation for free.

Three placements:

- `.above` — city. `rank % 8` staggers altitude so neighbours tier instead of
  colliding, and `density` shrinks the pill for small footprints
  (`4.2 / footprint`, clamped to 1…3).
- `.side(dx:dy:)` — strata. Segments call out left, sections right, tiered
  vertically. Reads like an exploded diagram.
- `.offset(SCNVector3)` — constellation. Each label fans radially outward along
  its own body's angle, in three depth tiers; all 73 fit without overlap.

Visibility is a set operation over nodes named `label:<target>`, never a
rebuild. `.hover` lazily attaches a callout for a shape outside the pre-labelled
set. `showsWithAll = false` keeps the long tail (minor Mach-O sections) out of
the "All" mode while still allowing it on hover.

### Interaction contract

- Hover → transient callout + a small inspector card.
- Click → persistent detail panel with the full record and actions
  ("Preview", "In tree", reveal in Finder). Clicking the same shape again
  clears it.
- Selection is a white 12-edge wireframe cage, pulsing, depth-tested.

---

## Palette

Chart colours are computed and validated, never eyeballed. `FileKind` exposes
three things: `color` (charts), `sceneColor` (a brightened variant for SceneKit
emission, where the lit-material rules differ), and `themeIndex` (position in
the validated categorical theme).

The eight-slot theme, stepped in OKLCH at L ≈ 0.50–0.66, C ≈ 0.185, and checked
against the dark surface `#0E111C`:

```
0 #BC3682  media           4 #905C01  assetCatalog
1 #27A83A  localization    5 #00A5B3  structuredData
2 #905CD9  appExtension    6 #C33029  executable
3 #009E92  interface       7 #0069CD  framework
```

The order is the theme order — `FileKind.themeIndex` — and the validator checks
*adjacent* pairs in it, so keep it stable.

Generate candidates by stepping OKLCH → sRGB with chroma reduced until the
colour is in gamut, then verify with the `dataviz` skill's validator — lightness
band, chroma floor, adjacent-pair CVD separation, normal-vision floor and
surface contrast all pass:

```sh
node scripts/validate_palette.js "#BC3682,#27A83A,#905CD9,#009E92,#905C01,#00A5B3,#C33029,#0069CD" \
     --mode dark --surface "#0E111C"
```

Constraints worth remembering: the dark-mode lightness band is **L ∈ [0.48, 0.67]**
and the chroma floor is **C ≥ 0.10**. Bright, saturated colours that look good
on a dark canvas fail the band — and the band is what stops one series
dominating. All-pairs separation is unachievable past ~6 hues because CVD
collapses the red–green axis; adjacent-pair separation plus a direct label and
an icon on every row is the shipping standard.

The long tail of `FileKind` values derives from the same hue families at
different lightness and only appears where a label or icon rides alongside.

---

## Resource previews

`ResourcePreview` routes on `FileKind`:

| Kind | Viewer |
|------|--------|
| image, vector | `NSImage` + zoom slider + checkerboard alpha grid + ImageIO metadata (pixel size, depth, colour model, profile, CgBI detection, `@2x`/`@3x`) |
| propertyList, privacyManifest, interface | `OutlineGroup` tree over the plist, plus a raw XML toggle |
| structuredData, text, localization | line-numbered monospace with a live filter; JSON pretty-printed; `.strings` falls back UTF-8 → UTF-16 |
| font | `CTFontManagerRegisterGraphicsFont` then render a sample at an adjustable size |
| media | `QLPreviewView` |
| assetCatalog | the BOM probe's structural report |
| anything else | hex dump (16 bytes/row) + `strings`-style extraction |

Thumbnails go through `CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceThumbnailMaxPixelSize` — decoding full 4K PNGs into a grid stalls
scrolling.

---

## Screenshot / input harness

Useful for verifying UI work without a human at the keyboard. All of it is
plain Swift + shell; none of it needs accessibility permission except posting
clicks.

**Find the window** (`CGWindowListCopyWindowInfo`, match on owner name — note
it is the *display* name, `Binary Explorer`, not the bundle name):

```swift
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
// filter: owner == "Binary Explorer", layer == 0, height > 400
// print X, Y, Width, Height, kCGWindowNumber
```

**Capture just that window:** `screencapture -x -o -l <windowNumber> out.png`

**Drive the pointer:**

```swift
CGWarpMouseCursorPosition(point)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
```

Click = `.leftMouseDown` then `.leftMouseUp` ~60 ms apart.

**Gotchas:** compute click points from the window's actual bounds (it does not
land in the same place every launch); `open -a` immediately before driving the
pointer so the app is frontmost, or motion events are never delivered; and to
screenshot a specific section, temporarily patch the default in `AppState`,
rebuild, relaunch — SwiftUI state is not scriptable from outside.

**Headless Core harness** — far faster than the UI for parser work:

```sh
swiftc -o harness main.swift BinaryExplorer/Core/*.swift \
    BinaryExplorer/UI/Scene3D/TreemapLayout.swift
./harness
```

`main.swift` calls `IPAAnalyzer.analyze` and prints everything. Compare its
output against `otool -hv -l`, `codesign -d --entitlements -` and `plutil -p`.
