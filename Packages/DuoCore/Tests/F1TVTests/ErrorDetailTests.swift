import Foundation
import Testing
@testable import F1TV

/// What the app shows after "Couldn't load F1 TV": F1 TV's own reason when it sent one.
@Suite struct ErrorDetailTests {
    private func json(_ text: String) throws -> JSONValue { try JSONValue.parse(Data(text.utf8)) }

    @Test func serverErrorShowsStatusAndF1Reason() {
        let body = #"{"resultCode":"ERR","message":"Content not available","errorDescription":"404-10013"}"#
        #expect(F1TVError.server(status: 404, message: body).detail == "error 404: Content not available (404-10013)")
    }

    @Test func serverErrorWithoutJSONShowsStatusOnly() {
        #expect(F1TVError.server(status: 500, message: "<html>oops</html>").detail == "error 500")
        #expect(F1TVError.server(status: 502, message: "").detail == "error 502")
    }

    @Test func badResponseShowsItsText() {
        #expect(F1TVError.badResponse("F1 TV sent no video link").detail == "F1 TV sent no video link")
    }

    @Test func otherErrorsHaveNoDetail() {
        #expect(F1TVError.multiviewUnavailable.detail == "")
        #expect(F1TVError.notSignedIn.detail == "")
    }

    @Test func okRepliesHaveNoF1Reason() throws {
        #expect(Parsers.f1Reason(try json(#"{"resultCode":"OK","message":"200","errorDescription":""}"#)) == nil)
        #expect(Parsers.f1Reason(try json(#"{"resultObj":{}}"#)) == nil)
    }

    @Test func f1ReasonUsesMessageThenDescription() throws {
        #expect(Parsers.f1Reason(try json(#"{"resultCode":"ERR","message":"","errorDescription":"Not entitled"}"#)) == "Not entitled")
        #expect(Parsers.f1Reason(try json(#"{"resultCode":"ERR","message":"500","errorDescription":"500-1"}"#)) == "500 (500-1)")
        let long = String(repeating: "x", count: 300)
        #expect(Parsers.f1Reason(try json(#"{"resultCode":"ERR","message":"\#(long)"}"#))?.count == 120)
    }

    /// A 200 reply that is really an error (no stream, `resultCode` not OK) says what F1 TV said.
    @Test func playErrorReplyCarriesF1Reason() throws {
        let reply = try json(#"{"resultCode":"ERR","message":"Content not available on this platform","errorDescription":"400-10010","resultObj":{}}"#)
        #expect(throws: F1TVError.badResponse("F1 TV said: Content not available on this platform (400-10010)")) {
            try Parsers.play(reply)
        }
        #expect(throws: F1TVError.badResponse("F1 TV said: Content not available on this platform (400-10010)")) {
            try Parsers.multiPlay(reply)
        }
    }

    @Test func playWithoutURLSaysSoPlainly() throws {
        #expect(throws: F1TVError.badResponse("F1 TV sent no video link")) {
            try Parsers.play(try json(#"{"resultCode":"OK","resultObj":{}}"#))
        }
    }
}
