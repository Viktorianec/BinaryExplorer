---
name: ipa-inspector
description: Build or extend a native macOS app that takes iOS .ipa archives apart — ZIP, Mach-O, code signature, provisioning profile, asset catalog — and renders the result as SwiftUI sections plus SceneKit 3D views. Use when working on Binary Explorer, when parsing any of those binary formats by hand in Swift, or when a task needs byte-level knowledge of an iOS app bundle.
---

# IPA Inspector

Everything needed to rebuild or extend **Binary Explorer**: a dependency-free
macOS app that unpacks an `.ipa` and reports what is inside it.

The parsers here are written from the format specs — no third-party packages,
no shelling out to `unzip`/`otool`/`codesign`. That is a deliberate constraint:
the app is sandboxed, and spawning tools from a sandbox is fragile.

## When to use this

- Extending Binary Explorer (this repo).
- Writing a Swift parser for ZIP, Mach-O, an embedded code signature, a
  `.mobileprovision`, or a compiled `Assets.car`.
- Any task that needs the byte layout of an iOS app bundle.

## Architecture

Two layers, strictly separated. `Core/` is pure value types with no UI import
beyond `SwiftUI.Color`; it runs off the main actor. `UI/` never parses.

```
Core/
  ByteReader.swift        Bounds-checked cursor. Every parser reads through it,
                          so a malformed archive yields nil, never a crash.
  ZipArchive.swift        Central directory + store/deflate + ZIP64.
  MachO.swift             Fat headers, slices, load commands, segments, sections.
  CodeSignature.swift     SuperBlob, code directories, entitlements, CMS signers.
  ProvisioningProfile.swift  CMS-wrapped plist + distribution-channel rules.
  AssetCatalog.swift      BOM/CAR structural probe (counts, versions, toolchain).
  FileKind.swift          Classification + the validated colour palette.
  IPAAnalyzer.swift       Pipeline: unpack → walk → parse → roll up.
  InsightEngine.swift     Findings a reviewer would flag.
  AnalysisModel.swift     The immutable result the UI renders.
  Format.swift            One place for byte/date/hex formatting.

UI/
  AppState.swift          Single @MainActor store: analysis, navigation, search.
  RootView.swift          Sidebar + section router + drop target + progress.
  Sections/               One file per section; all read-only over IPAAnalysis.
  Components/             Theme primitives and the resource previewers.
  Scene3D/                TreemapLayout, SceneBuilder, annotations, SCNView wrapper.
```

The analysis pipeline: open the ZIP → record compressed sizes per path →
extract to a scratch directory under `FileManager.temporaryDirectory` → build a
`FileNode` tree from disk → walk `.app` / `.appex` / `.framework` / `.bundle`
recursively into `BundleInfo` → run `InsightEngine`. ~230 ms for a 28 MB archive.

## Format references

Read these before touching a parser. Every offset is one that the shipped code
actually depends on.

| File | Covers |
|------|--------|
| `references/formats.md` | ZIP, Mach-O, code signature, mobileprovision, BOM/CAR — field-by-field |
| `references/pitfalls.md` | The traps. Each one cost a debug cycle; read it first |
| `references/macos-ui.md` | SceneKit, SwiftUI, palette validation, screenshot harness |

## Verification loop

Never trust a hand-written parser without ground truth. This repo's loop:

1. **Ground truth first.** Before writing a parser, capture what the system
   tools say for the sample archive:
   `otool -hv -l`, `codesign -d --entitlements -`, `plutil -p`, `unzip -l`.
2. **Diff the extraction.** `diff -rq` your unpacked payload against
   `unzip`'s. Byte-identical or the ZIP reader is wrong.
3. **Headless harness.** `Core/` compiles standalone — no Xcode needed:
   ```sh
   swiftc -o harness main.swift BinaryExplorer/Core/*.swift \
       BinaryExplorer/UI/Scene3D/TreemapLayout.swift
   ```
   A `main.swift` that prints the parsed analysis catches format bugs in
   seconds instead of through the UI.
4. **Screenshot the UI.** See `references/macos-ui.md` — the harness finds the
   window by `CGWindowListCopyWindowInfo` and captures it with
   `screencapture -l <windowid>`.

## Build

```sh
xcodebuild -project BinaryExplorer.xcodeproj -scheme BinaryExplorer \
    -configuration Debug -destination 'platform=macOS' build
```

Target settings that matter: `SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 14.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, `INFOPLIST_FILE = Info.plist`
(at the repo root, **not** inside the synchronized source folder), and the
sandbox entitlements `app-sandbox` + `files.user-selected.read-only`.

## House rules

- Comments explain *why*, in English, and only where the code cannot.
- Parsers return optionals; they never trap on malformed input.
- The UI renders `IPAAnalysis` and nothing else — no parsing in a view body.
- Colour is bound to `FileKind`, never to rank. The chart palette is validated,
  not eyeballed (`references/macos-ui.md`).
