import Foundation

/// The pieces of a FairPlay licence request in the shape F1 TV's own web player sends (its
/// Bitmovin config, read 2026-11-19): `spc=<base64 SPC>&assetId=<key ID>` as
/// application/octet-stream, where the key ID is the 32 characters after `skd://`.
public enum FairPlay {
    /// F1 TV's certificate when its config names none.
    public static let defaultCertificateURL = URL(string: "https://f1tv.formula1.com/fairplay01.der")!

    /// The 32-character key ID after `skd://` in a key request's identifier; nil when it isn't one.
    public static func assetId(fromKeyURI uri: String) -> String? {
        guard let rest = afterScheme(uri), rest.count >= 32 else { return nil }
        return String(rest.prefix(32))
    }

    /// How many characters follow `skd://` (for a message when `assetId` fails); nil without it.
    public static func keyIDLength(fromKeyURI uri: String) -> Int? {
        afterScheme(uri)?.count
    }

    public static func licenseBody(spc: Data, assetId: String) -> Data {
        Data("spc=\(spc.base64EncodedString())&assetId=\(assetId)".utf8)
    }

    /// The key response from the licence reply: base64 text (optionally in `<ckc>` tags) is
    /// decoded, anything else is taken as it is. Nil when the reply is empty.
    public static func ckc(fromResponse body: Data) -> Data? {
        if let text = String(data: body, encoding: .utf8) {
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if trimmed.lowercased().hasPrefix("<ckc>"), trimmed.lowercased().hasSuffix("</ckc>") {
                trimmed = String(trimmed.dropFirst(5).dropLast(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil,
               let decoded = Data(base64Encoded: trimmed), !decoded.isEmpty {
                return decoded
            }
        }
        return body.isEmpty ? nil : body
    }

    private static func afterScheme(_ uri: String) -> Substring? {
        guard uri.lowercased().hasPrefix("skd://") else { return nil }
        return uri.dropFirst(6)
    }
}

/// Why a FairPlay key couldn't be had. Messages never carry a link or a token.
public enum FairPlayError: Error, Equatable, Sendable {
    /// The certificate didn't load: its HTTP status, or 0 for an empty one.
    case certificate(status: Int)
    /// The key request's identifier wasn't `skd://` plus 32 characters (nil: no `skd://`).
    case keyID(length: Int?)
    /// The licence service refused: its status and F1 TV's own reason.
    case license(status: Int, reason: String)
    case emptyLicense

    public var message: String {
        switch self {
        case .certificate(let status):
            return status == 0
                ? "F1 TV's FairPlay certificate was empty"
                : "F1 TV's FairPlay certificate didn't load (error \(status))"
        case .keyID(let length):
            return length.map { "unexpected key ID (\($0) characters after skd://)" } ?? "unexpected key ID (no skd://)"
        case .license(let status, let reason):
            return reason.isEmpty ? "licence error \(status)" : "licence error \(status): \(reason)"
        case .emptyLicense:
            return "F1 TV sent an empty licence"
        }
    }
}
