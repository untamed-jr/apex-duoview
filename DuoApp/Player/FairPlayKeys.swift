import AVFoundation
import F1TV
import Foundation

/// Unlocks one FairPlay stream (a live session) the way Safari does on F1 TV's website: for each
/// key the stream asks for, F1 TV's certificate goes in, the phone makes the key request (SPC),
/// F1 TV's licence service answers it (CKC), and the key goes back to AVFoundation. The video and
/// its keys stay in Apple's protected path; nothing is decrypted or stored here.
///
/// Created before the player item and kept for the whole playback (live streams can renew keys).
/// The licence URL is signed: it is never logged or shown.
final class FairPlayKeys: NSObject, AVContentKeySessionDelegate, @unchecked Sendable {
    // @unchecked: every stored property is immutable, AVContentKeySession is thread-safe, and the
    // last failure is read and written only under `lock`.
    private let keySession: AVContentKeySession
    private let f1: F1TVSession
    private let licenseURL: URL
    private let queue = DispatchQueue(label: "app.apexview.fairplay")
    private let lock = NSLock()
    private var failureText: String?

    init(f1: F1TVSession, licenseURL: URL) {
        keySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        self.f1 = f1
        self.licenseURL = licenseURL
        super.init()
        keySession.setDelegate(self, queue: queue)
    }

    /// Call before the asset goes into a player item.
    func attach(_ asset: AVURLAsset) {
        keySession.addContentKeyRecipient(asset)
    }

    func stop() {
        keySession.expire()
    }

    /// The last reason a key couldn't be had, for the "This feed stopped" message.
    var lastFailure: String? {
        lock.lock()
        defer { lock.unlock() }
        return failureText
    }

    // MARK: AVContentKeySessionDelegate

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest,
                           didFailWithError err: Error) {
        record("the key was rejected (\(Self.code(err)))")
    }

    // MARK: One key

    private func handle(_ keyRequest: AVContentKeyRequest) {
        let box = KeyRequestBox(keyRequest)
        let keyURI = (keyRequest.identifier as? String) ?? ""
        let f1 = f1
        let licenseURL = licenseURL
        Task {
            do {
                let certificate = try await f1.fairPlayCertificate()
                guard let assetId = FairPlay.assetId(fromKeyURI: keyURI) else {
                    throw FairPlayError.keyID(length: FairPlay.keyIDLength(fromKeyURI: keyURI))
                }
                let spc = try await box.makeRequest(certificate: certificate, contentIdentifier: Data(assetId.utf8))
                let ckc = try await f1.fairPlayLicense(spc: spc, keyURI: keyURI, licenseURL: licenseURL)
                box.request.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
            } catch {
                record(Self.describe(error))
                box.request.processContentKeyResponseError(error)
            }
        }
    }

    private func record(_ text: String) {
        lock.lock()
        failureText = text
        lock.unlock()
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? FairPlayError { return error.message }
        if let error = error as? F1TVError, case .network(let reason) = error { return reason }
        if error is F1TVError { return "F1 TV refused the key request" }
        return "the phone couldn't make the key request (\(code(error)))"
    }

    private static func code(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}

/// Carries a key request (not Sendable) into the task that answers it; only that task uses it.
private final class KeyRequestBox: @unchecked Sendable {
    let request: AVContentKeyRequest

    init(_ request: AVContentKeyRequest) {
        self.request = request
    }

    func makeRequest(certificate: Data, contentIdentifier: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            request.makeStreamingContentKeyRequestData(
                forApp: certificate, contentIdentifier: contentIdentifier,
                options: [AVContentKeyRequestProtocolVersionsKey: [1]]
            ) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "AVContentKeyRequest", code: -1))
                }
            }
        }
    }
}
