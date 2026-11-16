import Foundation
import F1TV

public enum ZPayloadError: Error, Equatable {
    case badBase64
}

/// A `.z` payload: base64 text holding a raw-deflate stream of JSON.
public enum ZPayload {
    public static func decode(_ base64: String) throws -> JSONValue {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw ZPayloadError.badBase64
        }
        return try JSONValue.parse(try Inflate.raw(data))
    }
}
