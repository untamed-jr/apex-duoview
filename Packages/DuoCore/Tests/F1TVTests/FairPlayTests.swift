import Foundation
import Testing
@testable import F1TV

/// FairPlay for live sessions, in the shape F1 TV's own web player sends (its Bitmovin config,
/// read 2026-11-19): POST `spc=<base64 SPC>&assetId=<32-char key ID>` as application/octet-stream
/// with the ascendon and entitlement tokens, to the PLAY reply's `laURL`.
@Suite struct FairPlayTests {
    private let keyID = "00112233445566778899aabbccddeeff"

    // MARK: Pure helpers

    @Test func assetIdIsThe32CharactersAfterSkd() {
        #expect(FairPlay.assetId(fromKeyURI: "skd://\(keyID)") == keyID)
        #expect(FairPlay.assetId(fromKeyURI: "skd://\(keyID)ffff?x=1") == keyID)
        #expect(FairPlay.assetId(fromKeyURI: "SKD://\(keyID)") == keyID)
    }

    @Test func assetIdNeedsSkdAndEnoughCharacters() {
        #expect(FairPlay.assetId(fromKeyURI: "skd://abc") == nil)
        #expect(FairPlay.assetId(fromKeyURI: "https://\(keyID)") == nil)
        #expect(FairPlay.assetId(fromKeyURI: "") == nil)
        #expect(FairPlay.keyIDLength(fromKeyURI: "skd://abc") == 3)
        #expect(FairPlay.keyIDLength(fromKeyURI: "https://x") == nil)
    }

    @Test func licenseBodyMatchesTheWebPlayer() {
        let spc = Data([0xFB, 0xFF, 0x00, 0x10])
        let body = String(decoding: FairPlay.licenseBody(spc: spc, assetId: keyID), as: UTF8.self)
        #expect(body == "spc=+/8AEA==&assetId=\(keyID)")
    }

    @Test func ckcAcceptsRawBase64AndTagged() {
        let ckc = Data([1, 2, 3, 250, 251])
        #expect(FairPlay.ckc(fromResponse: ckc) == ckc)
        #expect(FairPlay.ckc(fromResponse: Data(ckc.base64EncodedString().utf8)) == ckc)
        #expect(FairPlay.ckc(fromResponse: Data("<ckc>\(ckc.base64EncodedString())</ckc>\n".utf8)) == ckc)
        #expect(FairPlay.ckc(fromResponse: Data()) == nil)
        #expect(FairPlay.ckc(fromResponse: Data("  \n".utf8)) == nil)
    }

    // MARK: PLAY

    @Test func fairPlayLiveIsPlayableWidevineIsProtected() throws {
        func reply(_ drm: String) throws -> JSONValue {
            try JSONValue.parse(Data(#"{"resultCode":"OK","resultObj":{"url":"https://example.com/live.m3u8","streamType":"SDR_HD_CMAFFP_SINGLE","drmType":"\#(drm)","laURL":"https://f1tv.formula1.com/3.0/R/ENG/WEB_HLS/ALL/CONTENT/LA/\#(drm)?x=1"}}"#.utf8))
        }
        let fair = try Parsers.play(try reply("fairplay"))
        #expect(fair.drmType == "fairplay")
        #expect(fair.isFairPlay)
        #expect(fair.licenseURL != nil)
        #expect(!(try Parsers.play(try reply("widevine"))).isFairPlay)
    }

    @Test func replaysStayClear() throws {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/play-1000010431-WEB_HLS.json")
        let info = try Parsers.play(try JSONValue.parse(try Data(contentsOf: url)))
        #expect(info.licenseURL == nil)
        #expect(!info.isFairPlay)
    }

    @Test func coordinatorPassesFairPlayAndRefusesWidevine() async throws {
        for (drm, protected) in [("fairplay", false), ("widevine", true)] {
            let http = FakeHTTPClient()
            await http.respond(pathSuffix: "/config", json: "{}")
            await http.respond(pathSuffix: "/USER/ENTITLEMENT", json: #"{"resultObj":{"entitlementToken":"ENT"}}"#)
            await http.respond(pathSuffix: "/USER/LOCATION", json: #"{"resultObj":{"userLocation":[{"entitlement":"PREMIUM","groupId":5}]}}"#)
            await http.respond(pathSuffix: "/CONTENT/PLAY", json: #"{"resultCode":"OK","resultObj":{"url":"https://example.com/live.m3u8","streamType":"X","drmType":"\#(drm)","laURL":"https://f1tv.formula1.com/LA/\#(drm)"}}"#)
            let session = F1TVSession(http: http)
            _ = try await session.signIn(token: "SUB")
            let coordinator = PlayCoordinator(session: session)
            if protected {
                await #expect(throws: F1TVError.protectedContent) { try await coordinator.play(contentId: 1, channelId: nil) }
            } else {
                let info = try await coordinator.play(contentId: 1, channelId: nil)
                #expect(info.isFairPlay)
            }
        }
    }

    // MARK: Session

    private func signedIn(_ http: FakeHTTPClient, config: String = "{}") async throws -> F1TVSession {
        await http.respond(pathSuffix: "/config", json: config)
        await http.respond(pathSuffix: "/USER/ENTITLEMENT", json: #"{"resultObj":{"entitlementToken":"ENT"}}"#)
        await http.respond(pathSuffix: "/USER/LOCATION", json: #"{"resultObj":{"userLocation":[{"entitlement":"PREMIUM","groupId":5}]}}"#)
        let session = F1TVSession(http: http)
        _ = try await session.signIn(token: "SUB")
        return session
    }

    @Test func licenseRequestIsAPostWithTokensAndBody() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        let ckc = Data([9, 8, 7])
        await http.respond(pathSuffix: "/CONTENT/LA/fairplay", body: Data(ckc.base64EncodedString().utf8))
        let license = URL(string: "https://f1tv.formula1.com/3.0/R/ENG/WEB_HLS/ALL/CONTENT/LA/fairplay?sig=abc")!
        let got = try await session.fairPlayLicense(spc: Data([1, 2]), keyURI: "skd://\(keyID)", licenseURL: license)
        #expect(got == ckc)
        let sent = try #require(await http.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url == license)
        #expect(sent.headers["ascendontoken"] == "SUB")
        #expect(sent.headers["entitlementtoken"] == "ENT")
        #expect(sent.headers["Content-Type"] == "application/octet-stream")
        #expect(sent.body.map { String(decoding: $0, as: UTF8.self) } == "spc=AQI=&assetId=\(keyID)")
    }

    @Test func refusedLicenseIsAFairPlayErrorAndKeepsTheSignIn() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        await http.respond(pathSuffix: "/CONTENT/LA/fairplay", status: 403,
                           json: #"{"resultCode":"ERR","message":"Not entitled","errorDescription":"403-1"}"#)
        let license = URL(string: "https://f1tv.formula1.com/x/CONTENT/LA/fairplay?sig=secret")!
        await #expect(throws: FairPlayError.license(status: 403, reason: "Not entitled (403-1)")) {
            try await session.fairPlayLicense(spc: Data([1]), keyURI: "skd://\(keyID)", licenseURL: license)
        }
        #expect(await session.isSignedIn)
    }

    @Test func badKeyIDIsReportedByLength() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        await #expect(throws: FairPlayError.keyID(length: 5)) {
            try await session.fairPlayLicense(spc: Data([1]), keyURI: "skd://12345", licenseURL: URL(string: "https://f1tv.formula1.com/LA")!)
        }
    }

    @Test func emptyLicenseIsAnError() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        await http.respond(pathSuffix: "/LA", body: Data())
        await #expect(throws: FairPlayError.emptyLicense) {
            try await session.fairPlayLicense(spc: Data([1]), keyURI: "skd://\(keyID)", licenseURL: URL(string: "https://f1tv.formula1.com/LA")!)
        }
    }

    @Test func certificateComesFromConfigAndIsCached() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http, config: #"{"bitmovin":{"drm":{"certUrl":"https://f1tv.formula1.com/fairplay02.der"}}}"#)
        await http.respond(pathSuffix: "/fairplay02.der", body: Data([0x30, 0x82]))
        #expect(try await session.fairPlayCertificate() == Data([0x30, 0x82]))
        #expect(try await session.fairPlayCertificate() == Data([0x30, 0x82]))
        let fetches = await http.requests.filter { $0.url.path.hasSuffix("/fairplay02.der") }
        #expect(fetches.count == 1)
    }

    @Test func certificateDefaultsToF1sFile() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        await http.respond(pathSuffix: "/fairplay01.der", body: Data([0x30]))
        #expect(try await session.fairPlayCertificate() == Data([0x30]))
    }

    @Test func certificateFailureSaysSo() async throws {
        let http = FakeHTTPClient()
        let session = try await signedIn(http)
        await http.respond(pathSuffix: "/fairplay01.der", status: 404, body: Data())
        await #expect(throws: FairPlayError.certificate(status: 404)) { try await session.fairPlayCertificate() }
    }

    @Test func messagesNeverCarryTheLink() {
        let all: [FairPlayError] = [.certificate(status: 404), .certificate(status: 0), .keyID(length: 5), .keyID(length: nil),
                                    .license(status: 403, reason: "Not entitled"), .license(status: 500, reason: ""), .emptyLicense]
        for error in all {
            #expect(!error.message.isEmpty)
            #expect(!error.message.contains("http"))
        }
        #expect(FairPlayError.license(status: 403, reason: "Not entitled").message.contains("403"))
    }
}
