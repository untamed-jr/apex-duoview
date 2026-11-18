import Foundation

public enum F1TVError: Error, Equatable, Sendable {
    case notSignedIn
    case refused(status: Int)
    case noVideoPlan
    case network(String)
    case server(status: Int, message: String)
    case badResponse(String)
    case protectedContent
    /// F1 TV answered a multiview request with fewer than two feeds, or with DASH streams.
    case multiviewUnavailable
}

extension F1TVError {
    /// A short reason to show after "Couldn't load F1 TV", in F1 TV's own words when it sent any.
    /// Empty when there is nothing more to say than the error's own message.
    public var detail: String {
        switch self {
        case .server(let status, let body):
            let reason = (try? JSONValue.parse(Data(body.utf8))).flatMap(Parsers.f1Reason)
            return reason.map { "error \(status): \($0)" } ?? "error \(status)"
        case .badResponse(let text):
            return text
        default:
            return ""
        }
    }
}
