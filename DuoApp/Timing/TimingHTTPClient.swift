import F1TV
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `HTTPClient` for timing: F1's archive (`livetiming.formula1.com`, with the F1 TV token in
/// `Authorization`) and MultiViewer's circuits (no token). Its own ephemeral URLSession, so the
/// video client's 30 s limit doesn't cut off a race's ~17 MB of topics fetched together: 30 s
/// without data on a request, 300 s for a whole file. A redirect to any other host goes without
/// the `Authorization` header, so the token only ever reaches the host it was meant for.
/// Errors never carry the request (it holds the token) or its URL.
final class TimingHTTPClient: HTTPClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: TimingRedirectGuard(), delegateQueue: nil)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw F1TVError.network("Unexpected response")
            }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as F1TVError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw F1TVError.network("Network error")
        } catch {
            throw F1TVError.network("Network error")
        }
    }
}

/// Drops `Authorization` from any redirect that leaves the original request's host (or its
/// https). Holds nothing, so it is safe from URLSession's delegate queue.
final class TimingRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        Self.redirect(request, from: task.originalRequest?.url)
    }

    /// The redirected request, without `Authorization` unless it stays on the same host over https.
    static func redirect(_ request: URLRequest, from original: URL?) -> URLRequest {
        var redirected = request
        let sameHost = original?.host?.lowercased() == request.url?.host?.lowercased()
        let secure = request.url?.scheme?.lowercased() == "https"
        if !(sameHost && secure) {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return redirected
    }
}
