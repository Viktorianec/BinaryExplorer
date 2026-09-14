# Binary formats

Field offsets below are the ones the shipped parsers depend on. Everything is
little-endian unless a row says otherwise.

---

## 1. ZIP (the `.ipa` container)

An `.ipa` is a plain ZIP. Read it from the end: the central directory is
authoritative, local headers are not (their size fields may be zeroed when a
data descriptor follows).

### End of central directory (EOCD)

Signature `0x06054B50`. Scan backwards from `count - 22`; a trailing comment can
push it up to 65,535 bytes earlier.

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | signature `0x06054B50` |
| 4 | 2 | this disk number |
| 6 | 2 | disk with central directory |
| 8 | 2 | entries on this disk |
| **10** | 2 | **total entries** |
| 12 | 4 | central directory size |
| **16** | 4 | **central directory offset** |
| 20 | 2 | comment length |

### Central directory header

Signature `0x02014B50`, one per entry, laid out back to back.

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | signature `0x02014B50` |
| 4 | 2 | version made by |
| 6 | 2 | version needed |
| 8 | 2 | general purpose flags (bit 11 = UTF-8 name) |
| 10 | 2 | compression method (0 = store, 8 = deflate) |
| 12 | 2 | modification time (DOS) |
| 14 | 2 | modification date (DOS) |
| 16 | 4 | CRC-32 |
| 20 | 4 | compressed size |
| 24 | 4 | uncompressed size |
| 28 | 2 | file name length |
| 30 | 2 | extra field length |
| 32 | 2 | comment length |
| **34** | **2** | **disk number start** |
| **36** | **2** | **internal attributes** |
| **38** | **4** | **external attributes** |
| **42** | **4** | **local header offset** |
| 46 | n | file name, then extra, then comment |

> The bold rows are where a hand-rolled reader goes wrong. After the comment
> length at 32 you skip **4** bytes (disk + internal attrs), not 8. Getting this
> wrong reads the local-header offset out of the file-name bytes and every path
> comes back shifted — the symptom is entries like `oad/UX` instead of
> `Payload/…`.

External attributes carry the Unix mode in the **high 16 bits**:
`(externalAttributes >> 16) & 0xFFFF`. That is how you know the app binary was
executable (`& 0o111`) and must be restored with `setAttributes`.

### Local file header

Signature `0x04034B50`. Only two fields matter, because the sizes come from the
central directory:

| Offset | Size | Field |
|--------|------|-------|
| 26 | 2 | file name length |
| 28 | 2 | extra field length |

Payload starts at `headerStart + 30 + nameLength + extraLength`. Note the extra
field length here often differs from the central directory's — always re-read it.

### ZIP64

Sentinels: `0xFFFF` for counts, `0xFFFFFFFF` for sizes and offsets.

- Locator `0x07064B50`, 20 bytes immediately before the EOCD; the ZIP64 EOCD
  offset is at locator + 8 (8 bytes).
- ZIP64 EOCD `0x06064B50`: total entries at +32 (8 bytes), central directory
  offset at +40 (8 bytes).
- Per-entry: extra field header ID `0x0001`, then uncompressed / compressed /
  local-offset as 8-byte values **only for the fields that were sentinelled**,
  in that order.

### Decompression

`Compression.framework` decodes **raw** deflate — the stream in a ZIP entry has
no zlib wrapper, and `COMPRESSION_ZLIB` is exactly right for it:

```swift
compression_decode_buffer(dst, expectedSize, src, input.count, nil, COMPRESSION_ZLIB)
```

Allocate the destination at the uncompressed size from the central directory.

### Path safety

Reject entries containing `..` and anything whose resolved destination escapes
the extraction root. An `.ipa` is untrusted input.

---

## 2. Mach-O

### Magics

| Value | Meaning |
|-------|---------|
| `0xCAFEBABE` / `0xCAFEBABF` | fat header, 32-/64-bit entries — **always big-endian** |
| `0xFEEDFACF` / `0xCFFAEDFE` | 64-bit Mach-O, host / swapped |
| `0xFEEDFACE` / `0xCEFAEDFE` | 32-bit Mach-O, host / swapped |

Since iOS 11 a store binary is a single thin `arm64` slice; older ones are fat.

### Mach header (64-bit)

`magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved` —
all `uint32`, 32 bytes total (28 for 32-bit, no `reserved`).

CPU types seen in iOS bundles: `0x0100000C` arm64 (subtype 1 = arm64e),
`0x0200000C` arm64_32 (watchOS), `0x0000000C` arm (9 = armv7, 11 = armv7s,
12 = armv7k), `0x01000007` x86_64 (simulator).

Header flags worth surfacing: `MH_PIE 0x200000` (Apple requires it),
`MH_TWOLEVEL 0x80`, `MH_BINDS_TO_WEAK 0x800`, `MH_APP_EXTENSION_SAFE 0x800000`.

### Load commands

Each is `cmd (uint32), cmdsize (uint32)`, then payload. Always advance by
`cmdsize` from the command's own start — never by what you read.

| cmd | Name | What to pull out |
|-----|------|------------------|
| `0x19` / `0x01` | `LC_SEGMENT_64` / `LC_SEGMENT` | segname[16], vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags |
| `0x0C` | `LC_LOAD_DYLIB` | name offset (relative to command start), timestamp, current version, compat version |
| `0x80000018` | `LC_LOAD_WEAK_DYLIB` | same layout |
| `0x8000001F` | `LC_REEXPORT_DYLIB` | same layout |
| `0x0D` | `LC_ID_DYLIB` | the install name of a framework |
| `0x8000001C` | `LC_RPATH` | path offset |
| `0x0E` | `LC_LOAD_DYLINKER` | `/usr/lib/dyld` |
| `0x1B` | `LC_UUID` | 16 raw bytes → `UUID(uuid:)` |
| `0x32` | `LC_BUILD_VERSION` | platform, minos, sdk, ntools |
| `0x24`/`0x25`/`0x2F`/`0x30` | `LC_VERSION_MIN_*` | legacy minos/sdk (macOS/iOS/tvOS/watchOS) |
| `0x2A` | `LC_SOURCE_VERSION` | one `uint64`, packed a.b.c.d.e |
| `0x21` / `0x2C` | `LC_ENCRYPTION_INFO(_64)` | cryptoff, cryptsize, cryptid |
| `0x1D` | `LC_CODE_SIGNATURE` | dataoff, datasize → the SuperBlob |
| `0x02` | `LC_SYMTAB` | symoff, **nsyms**, stroff, strsize |
| `0x0B` | `LC_DYSYMTAB` | 18 `uint32`s; `nindirectsyms` is the 17th |
| `0x80000028` | `LC_MAIN` | entryoff, stacksize |
| `0x80000033` / `0x80000034` | exports trie / chained fixups | presence is the signal |

Version words are packed `xxxx.yy.zz`: `major = v >> 16`, `minor = (v >> 8) & 0xFF`,
`patch = v & 0xFF`. `LC_SOURCE_VERSION` packs five fields as
`a(24).b(10).c(10).d(10).e(10)`.

Platform ids: 1 macOS, 2 iOS, 3 tvOS, 4 watchOS, 6 Mac Catalyst, 7 iOS Simulator,
11 visionOS.

### Sections

Inside a segment, `nsects` records of 80 bytes (68 for 32-bit):
`sectname[16], segname[16], addr, size, offset, align, reloff, nreloc, flags,
reserved1, reserved2, reserved3`.

`flags & 0xFF` is the section *type*: `0x1` = `S_ZEROFILL`, `0xC` =
`S_THREAD_LOCAL_ZEROFILL`. Those occupy VM but no file bytes, so their `offset`
is meaningless — label them "zero-fill" rather than printing a bogus offset.

Language detection comes straight from section names: `__swift5_*` means Swift,
`__objc_*` means the Objective-C runtime is in play.

### FairPlay

`LC_ENCRYPTION_INFO_64` is present in store-bound builds. `cryptid == 0` means
the load command is there but **disarmed** — the binary is fully readable. A
non-zero `cryptid` means `cryptsize` bytes at `cryptoff` are ciphertext and
static analysis needs a decrypted dump from a device.

---

## 3. Embedded code signature

Pointed at by `LC_CODE_SIGNATURE`. **Every integer in this blob is big-endian.**

### SuperBlob — `0xFADE0CC0`

```
magic (4) | length (4) | count (4) | [ type (4), offset (4) ] × count
```

Blob offsets are relative to the SuperBlob start, not the file.

| Magic | Blob |
|-------|------|
| `0xFADE0C02` | CodeDirectory |
| `0xFADE7171` | entitlements, as an XML plist |
| `0xFADE7172` | DER entitlements |
| `0xFADE0C01` | requirement set (the designated requirement) |
| `0xFADE0B01` | CMS/PKCS#7 signature |

### CodeDirectory

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | magic `0xFADE0C02` |
| 4 | 4 | length |
| 8 | 4 | version |
| 12 | 4 | flags |
| 16 | 4 | hashOffset |
| 20 | 4 | identOffset → C string, relative to blob start |
| 24 | 4 | nSpecialSlots |
| 28 | 4 | nCodeSlots |
| 32 | 4 | codeLimit |
| 36 | 1 | hashSize |
| 37 | 1 | hashType (1 SHA-1, 2 SHA-256, 3 SHA-256-truncated, 4 SHA-384) |
| 38 | 1 | platform |
| 39 | 1 | pageSize as a shift — real size is `1 << pageShift` (16 KB on arm64) |
| 40 | 4 | spare2 |

Then, gated on `version`:

- `>= 0x20100`: `scatterOffset` (4)
- `>= 0x20200`: `teamOffset` (4) → C string
- `>= 0x20400`: `execSegBase`, `execSegLimit`, `execSegFlags` at byte 96

**CDHash** is the digest of the *entire* CodeDirectory blob (length bytes from
its start) under `hashType`, displayed truncated to 20 bytes. It must match
`codesign -d -vvv`'s `CDHash=`.

Signature flags: `0x2` adhoc, `0x4` get-task-allow, `0x200` forced-lv,
`0x1000` kill, `0x10000` library-validation, `0x20000` runtime,
`0x40000` linker-signed.

### CMS blob → certificates

Do not write an ASN.1 parser. macOS ships `CMSDecoder`:

```swift
CMSDecoderCreate(&decoder)
CMSDecoderUpdateMessage(decoder, base, blob.count)
CMSDecoderFinalizeMessage(decoder)
CMSDecoderCopyAllCerts(decoder, &certs)   // [SecCertificate]
CMSDecoderCopyContent(decoder, &content)  // the signed payload
```

Per certificate, `SecCertificateCopySubjectSummary`,
`SecCertificateCopySerialNumberData`, and `SecCertificateCopyValues` for
`kSecOIDX509V1ValidityNotBefore/NotAfter` and `kSecOIDOrganizationName`.

> Validity dates come back as a `Double` on the **Core Foundation epoch** —
> `Date(timeIntervalSinceReferenceDate:)`, not `timeIntervalSince1970`. Using the
> wrong epoch shifts every certificate by 31 years.

---

## 4. `embedded.mobileprovision`

A CMS-wrapped XML plist. Decode with `CMSDecoderCopyContent`; fall back to
scanning for `<?xml` … `</plist>` when the decoder declines the signature
algorithm.

Keys worth reading: `Name`, `UUID`, `AppIDName`, `TeamName`, `TeamIdentifier`,
`Platform`, `CreationDate`, `ExpirationDate`, `TimeToLive`, `ProvisionedDevices`,
`ProvisionsAllDevices`, `IsXcodeManaged`, `Entitlements`, `DeveloperCertificates`
(an array of DER blobs → `SecCertificateCreateWithData`).

Distribution channel is derived, not stored:

| Condition | Channel |
|-----------|---------|
| `ProvisionsAllDevices == true` | Enterprise (In-House) |
| `ProvisionedDevices` non-empty, `get-task-allow == true` | Development |
| `ProvisionedDevices` non-empty, `get-task-allow == false` | Ad Hoc |
| no device list, has `application-identifier` | App Store |

An App Store download legitimately has **no** profile — Apple strips it during
processing. Absence is not a defect.

---

## 5. `Assets.car` (CoreUI / BOM)

Individual renditions are only decodable through CoreUI, which is private. The
*structure* is readable, and that is enough to report rendition counts, versions
and the producing toolchain.

### BOM header — all big-endian

```
magic "BOMStore" (8) | version (4) | numberOfBlocks (4)
| indexOffset (4) | indexLength (4) | varsOffset (4) | varsLength (4)
```

- **Block table** at `indexOffset`: `count (4)`, then `count + 1` entries of
  `{ address (4), length (4) }`, indexed from 1.
- **Variables** at `varsOffset`: `count (4)`, then per variable
  `{ blockIndex (4), nameLength (1), name[nameLength] }`.

Variables present in a modern catalog: `CARHEADER`, `RENDITIONS`, `FACETKEYS`,
`BITMAPKEYS`, `KEYFORMAT`, `APPEARANCEKEYS`, `EXTENDED_METADATA`, sometimes
`COLORS`, `EXTERNAL_KEYS`.

### CARHEADER block — little-endian after the tag

```
tag 'CTAR' (4) | coreuiVersion (4) | storageVersion (4) | storageTimestamp (4)
| renditionCount (4) | mainVersionString[128] | versionString[256]
| uuid (16) | associatedChecksum (4) | schemaVersion (4) | colorSpaceID (4)
| keySemantics (4)
```

`versionString` is the useful one — it names the Xcode build that compiled the
catalog, e.g. `Xcode 26.6 (17F113) via AssetCatalogSimulatorAgent`.

### Tree blocks — big-endian

```
tag "tree" (4) | version (4) | child block index (4) | blockSize (4) | pathCount (4)
```

`pathCount` is the leaf count, which is all you need:
`RENDITIONS` → rendition count, `FACETKEYS` → named-asset count,
`APPEARANCEKEYS` → appearance count.

Sanity check on the sample archive: 15.6 MB catalog, 623 renditions across
154 named assets, 3 appearances.

---

## 6. Info.plist and bundle layout

`PropertyListSerialization` reads Apple's binary plists natively — no special
handling needed.

Canonical layout, and what each part is for:

```
Payload/                        the only top-level folder
  <App>.app/                    flat bundle; no Contents/MacOS layer on iOS
    Info.plist                  binary plist manifest
    <CFBundleExecutable>        the Mach-O
    Assets.car                  compiled asset catalog
    AppIcon*.png                loose icon renditions (see below)
    _CodeSignature/CodeResources   per-file hash manifest + sealing rules
    embedded.mobileprovision    stripped from App Store copies
    Frameworks/                 embedded .framework / .dylib, each signed
    PlugIns/                    .appex extensions, each with its own Info.plist
    Watch/<App>.app/            companion watchOS app (its own PlugIns/)
    *.lproj/                    one per language; defines the store's language list
    *.bundle/                   SPM / CocoaPods resource bundles
    PkgInfo                     eight legacy bytes; nothing reads it
```

**Icons.** Even with an asset catalog, iOS writes the primary icon PNGs loose at
the bundle root so Springboard and the installer can read them without CoreUI.
Collect candidates from `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles`
(and the `~ipad` variant), plus anything named `AppIcon*`/`Icon*`, then pick the
largest by `kCGImagePropertyPixelWidth` via `CGImageSourceCopyPropertiesAtIndex`.

Those PNGs are usually **CgBI** — Apple's optimised variant with a `CgBI` chunk
before `IHDR`, BGRA channel order and premultiplied alpha. macOS ImageIO decodes
them correctly, so `NSImage(contentsOf:)` just works; only non-Apple platforms
need a converter. Detect the variant by looking for `CgBI` in the first 16 bytes
and label it in the UI.

**Privacy manifests.** `PrivacyInfo.xcprivacy` is a plist with
`NSPrivacyTracking`, `NSPrivacyTrackingDomains`, `NSPrivacyCollectedDataTypes`
(array of dicts keyed `NSPrivacyCollectedDataType`) and `NSPrivacyAccessedAPITypes`
(keyed `NSPrivacyAccessedAPIType`). SDKs ship them inside their resource bundles,
so enumerate the whole payload, not just the app root.
