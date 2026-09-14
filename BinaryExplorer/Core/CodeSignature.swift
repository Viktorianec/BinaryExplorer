//
//  CodeSignature.swift
//  BinaryExplorer
//
//  Reads the embedded code-signature SuperBlob pointed at by LC_CODE_SIGNATURE:
//  code directories, entitlements, and the CMS signer chain.
//

import Foundation
import CryptoKit
import Security

struct CodeDirectoryInfo: Identifiable, Hashable {
    var id: String { "\(identifier)-\(hashType)-\(version)" }
    var identifier: String
    var teamID: String?
    var version: String
    var hashType: String
    var hashSize: Int
    var pageSize: Int
    var codeLimit: UInt64
    var codeSlots: Int
    var specialSlots: Int
    var flags: [String]
    var cdHash: String
    var executableSegmentFlags: UInt64?
}

struct SigningCertificate: Identifiable, Hashable {
    var id: String { summary + serial }
    var summary: String
    var organization: String?
    var serial: String
    var notValidBefore: Date?
    var notValidAfter: Date?

    var role: String {
        let s = summary.lowercased()
        if s.contains("apple root") { return "Root CA" }
        if s.contains("worldwide developer") || s.contains("certification authority") { return "Intermediate CA" }
        if s.contains("distribution") { return "Distribution" }
        if s.contains("development") || s.contains("developer") { return "Development" }
        return "Leaf"
    }
}

struct CodeSignature: Hashable {
    var offset: Int
    var size: Int
    var codeDirectories: [CodeDirectoryInfo]
    var entitlements: [String: Any]?
    var entitlementsXML: String?
    var hasDEREntitlements: Bool
    var hasCMSSignature: Bool
    var certificates: [SigningCertificate]
    var requirementsPresent: Bool

    var primaryDirectory: CodeDirectoryInfo? {
        codeDirectories.first { $0.hashType.contains("256") } ?? codeDirectories.first
    }

    var isAdHoc: Bool {
        codeDirectories.contains { $0.flags.contains("adhoc") }
    }

    var leafCertificate: SigningCertificate? {
        certificates.first { $0.role == "Distribution" || $0.role == "Development" } ?? certificates.first
    }

    static func == (lhs: CodeSignature, rhs: CodeSignature) -> Bool {
        lhs.offset == rhs.offset && lhs.size == rhs.size
            && lhs.codeDirectories == rhs.codeDirectories
            && lhs.certificates == rhs.certificates
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
        hasher.combine(size)
        hasher.combine(codeDirectories)
    }
}

enum CodeSignatureParser {

    private enum BlobMagic {
        static let embeddedSignature: UInt32 = 0xFADE_0CC0
        static let codeDirectory: UInt32 = 0xFADE_0C02
        static let entitlements: UInt32 = 0xFADE_7171
        static let derEntitlements: UInt32 = 0xFADE_7172
        static let requirementSet: UInt32 = 0xFADE_0C01
        static let cms: UInt32 = 0xFADE_0B01
    }

    static func parse(_ data: Data, offset: Int, size: Int) -> CodeSignature? {
        guard size > 8, offset >= 0, offset + 8 <= data.count else { return nil }
        guard data.u32(at: offset, bigEndian: true) == BlobMagic.embeddedSignature else { return nil }

        var r = ByteReader(data, offset: offset + 8)
        guard let blobCount = r.u32(true), blobCount < 64 else { return nil }

        var signature = CodeSignature(offset: offset,
                                      size: size,
                                      codeDirectories: [],
                                      hasDEREntitlements: false,
                                      hasCMSSignature: false,
                                      certificates: [],
                                      requirementsPresent: false)

        for _ in 0..<blobCount {
            guard r.u32(true) != nil, let blobOffset = r.u32(true) else { break }
            let blobStart = offset + Int(blobOffset)
            guard blobStart + 8 <= data.count,
                  let magic = data.u32(at: blobStart, bigEndian: true),
                  let length = data.u32(at: blobStart + 4, bigEndian: true),
                  length >= 8, blobStart + Int(length) <= data.count else { continue }

            switch magic {
            case BlobMagic.codeDirectory:
                if let directory = parseCodeDirectory(data, at: blobStart, length: Int(length)) {
                    signature.codeDirectories.append(directory)
                }
            case BlobMagic.entitlements:
                let payload = data.subdata(in: (data.startIndex + blobStart + 8)..<(data.startIndex + blobStart + Int(length)))
                signature.entitlementsXML = String(data: payload, encoding: .utf8)
                signature.entitlements = try? PropertyListSerialization.propertyList(
                    from: payload, format: nil) as? [String: Any]
            case BlobMagic.derEntitlements:
                signature.hasDEREntitlements = true
            case BlobMagic.requirementSet:
                signature.requirementsPresent = true
            case BlobMagic.cms:
                signature.hasCMSSignature = length > 8
                let payload = data.subdata(in: (data.startIndex + blobStart + 8)..<(data.startIndex + blobStart + Int(length)))
                signature.certificates = certificates(fromCMS: payload)
            default:
                break
            }
        }

        return signature.codeDirectories.isEmpty && signature.entitlements == nil ? nil : signature
    }

    private static func parseCodeDirectory(_ data: Data, at start: Int, length: Int) -> CodeDirectoryInfo? {
        var r = ByteReader(data, offset: start + 8)
        guard let version = r.u32(true), let flags = r.u32(true),
              r.u32(true) != nil,                                     // hashOffset
              let identOffset = r.u32(true),
              let specialSlots = r.u32(true), let codeSlots = r.u32(true),
              let codeLimit = r.u32(true), let hashSize = r.u8(),
              let hashType = r.u8(), r.u8() != nil, let pageShift = r.u8() else { return nil }

        let identifier = cString(data, at: start + Int(identOffset), limit: start + length) ?? "—"

        var teamID: String?
        if version >= 0x2020_0 {
            r.skip(4)                                                 // spare2
            if version >= 0x2010_0 { r.skip(4) }                      // scatterOffset
            if let teamOffset = r.u32(true), teamOffset > 0 {
                teamID = cString(data, at: start + Int(teamOffset), limit: start + length)
            }
        }

        var execSegmentFlags: UInt64?
        if version >= 0x2040_0 {
            var er = ByteReader(data, offset: start + 96)             // execSegBase begins here
            _ = er.u64(true); _ = er.u64(true)
            execSegmentFlags = er.u64(true)
        }

        let blob = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + length))
        let digest: String
        switch hashType {
        case 1:
            digest = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        case 4:
            digest = SHA384.hash(data: blob).prefix(20).map { String(format: "%02x", $0) }.joined()
        default:
            digest = SHA256.hash(data: blob).prefix(20).map { String(format: "%02x", $0) }.joined()
        }

        return CodeDirectoryInfo(identifier: identifier,
                                 teamID: teamID,
                                 version: String(format: "0x%05x", version),
                                 hashType: hashTypeName(hashType),
                                 hashSize: Int(hashSize),
                                 pageSize: pageShift == 0 ? 0 : 1 << Int(pageShift),
                                 codeLimit: UInt64(codeLimit),
                                 codeSlots: Int(codeSlots),
                                 specialSlots: Int(specialSlots),
                                 flags: signatureFlags(flags),
                                 cdHash: digest,
                                 executableSegmentFlags: execSegmentFlags)
    }

    private static func hashTypeName(_ value: UInt8) -> String {
        switch value {
        case 1: return "SHA-1"
        case 2: return "SHA-256"
        case 3: return "SHA-256 (truncated)"
        case 4: return "SHA-384"
        default: return "Hash \(value)"
        }
    }

    private static func signatureFlags(_ flags: UInt32) -> [String] {
        let table: [(UInt32, String)] = [
            (0x0000_0002, "adhoc"), (0x0000_0004, "get-task-allow"),
            (0x0000_0100, "installer"), (0x0000_0200, "forced-lv"),
            (0x0000_0400, "invalid-allowed"), (0x0000_0800, "hard"),
            (0x0000_1000, "kill"), (0x0000_2000, "check-expiration"),
            (0x0000_4000, "restrict"), (0x0000_8000, "enforcement"),
            (0x0001_0000, "library-validation"), (0x0002_0000, "runtime"),
            (0x0004_0000, "linker-signed")
        ]
        return table.filter { flags & $0.0 != 0 }.map(\.1)
    }

    private static func cString(_ data: Data, at offset: Int, limit: Int) -> String? {
        guard offset >= 0, offset < min(limit, data.count) else { return nil }
        var bytes: [UInt8] = []
        var i = data.startIndex + offset
        let end = data.startIndex + min(limit, data.count)
        while i < end, data[i] != 0 {
            bytes.append(data[i])
            i += 1
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - CMS

    /// Pulls the certificate chain out of a PKCS#7 blob using the Security framework.
    static func certificates(fromCMS blob: Data) -> [SigningCertificate] {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return [] }
        let updated = blob.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, blob.count)
        }
        guard updated == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return [] }

        var certs: CFArray?
        guard CMSDecoderCopyAllCerts(decoder, &certs) == errSecSuccess,
              let list = certs as? [SecCertificate] else { return [] }
        return list.map(describe)
    }

    /// Decodes the signed payload of a CMS blob (used for .mobileprovision).
    static func cmsContent(_ blob: Data) -> Data? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        let updated = blob.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, blob.count)
        }
        guard updated == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess else { return nil }
        return content as Data?
    }

    static func describe(_ certificate: SecCertificate) -> SigningCertificate {
        let summary = (SecCertificateCopySubjectSummary(certificate) as String?) ?? "Unknown certificate"
        var serialText = "—"
        if let serial = SecCertificateCopySerialNumberData(certificate, nil) as Data? {
            serialText = serial.map { String(format: "%02X", $0) }.joined(separator: " ")
        }

        var organization: String?
        var notBefore: Date?
        var notAfter: Date?
        let keys = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter,
                    kSecOIDOrganizationName] as CFArray
        if let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any] {
            func date(_ oid: CFString) -> Date? {
                guard let entry = values[oid as String] as? [String: Any],
                      let seconds = entry["value"] as? Double else { return nil }
                // X.509 validity is expressed relative to the Core Foundation epoch.
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            notBefore = date(kSecOIDX509V1ValidityNotBefore)
            notAfter = date(kSecOIDX509V1ValidityNotAfter)
            if let entry = values[kSecOIDOrganizationName as String] as? [String: Any] {
                if let value = entry["value"] as? String {
                    organization = value
                } else if let list = entry["value"] as? [[String: Any]] {
                    organization = list.compactMap { $0["value"] as? String }.first
                }
            }
        }

        return SigningCertificate(summary: summary,
                                  organization: organization,
                                  serial: serialText,
                                  notValidBefore: notBefore,
                                  notValidAfter: notAfter)
    }
}
