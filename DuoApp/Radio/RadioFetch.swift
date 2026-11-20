import F1TV
import Foundation
import LiveTiming

/// What fetching a clip's MP3 came to.
enum RadioFetchResult: Sendable, Equatable {
    case data(Data)
    /// F1 refused it, with the sign-in too (or there was no sign-in to try), or it isn't there.
    case refused
    /// The network failed, or F1 answered with another error.
    case failed
}

/// Fetching and keeping team radio clips (pure: Foundation and DuoCore only, no actor).
///
/// - A clip is fetched first **without** the F1 TV sign-in, as Android does. Only a 401 or 403
///   brings a second try, once, with `Authorization: Bearer`, to the same URL, and only when that
///   URL is F1's archive over https. Nothing else ever gets the token.
/// - A refusal is `.refused`, never a sign-out; the app says "Couldn't load this clip".
/// - Clips are kept in `Caches/radio/{sessionKey}/`, named by the clip's last path segment (never
///   anything from a request), and deleted after 7 days.
/// - Never logs; errors from the transport are dropped, not passed on (they could hold the header).
enum RadioFetch {
    /// How long a kept clip (and the session's transcripts) stays.
    static let maxAge: TimeInterval = 7 * 24 * 3600

    /// `Caches/radio`; nil if the system gives no caches folder.
    static var defaultBase: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("radio", isDirectory: true)
    }

    /// `base/{sessionKey}/{the clip path's last segment}`. Both parts are reduced to letters,
    /// digits, ".", "-" and "_" (anything else becomes "_"), so neither can leave the folder.
    static func cacheURL(base: URL, sessionKey: String, clipPath: String) -> URL {
        let name = clipPath.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return folder(base: base, sessionKey: sessionKey)
            .appendingPathComponent(safeName(name, fallback: "clip.mp3"), isDirectory: false)
    }

    /// The session's folder under `base`.
    static func folder(base: URL, sessionKey: String) -> URL {
        base.appendingPathComponent(safeName(sessionKey, fallback: "session"), isDirectory: true)
    }

    /// The clip's MP3: without the sign-in first; on 401 or 403 once more with it, to this URL
    /// only (and only if it is F1's archive over https).
    @concurrent
    static func fetch(_ url: URL, http: any HTTPClient, token: @Sendable () async -> String?) async -> RadioFetchResult {
        guard let first = await get(url, http: http, bearer: nil) else { return .failed }
        switch first.status {
        case 200..<300:
            return .data(first.body)
        case 401, 403:
            guard isArchive(url), let token = await token(), !token.isEmpty else { return .refused }
            guard let second = await get(url, http: http, bearer: token) else { return .failed }
            switch second.status {
            case 200..<300: return .data(second.body)
            case 401, 403, 404: return .refused
            default: return .failed
            }
        case 404:
            return .refused
        default:
            return .failed
        }
    }

    /// Older than 7 days (a file from the future isn't).
    static func expired(modified: Date, now: Date) -> Bool {
        now.timeIntervalSince(modified) > maxAge
    }

    /// Deletes the files under `base` older than 7 days, then any session folder left empty.
    /// Run at launch, off the main actor.
    static func deleteExpired(in base: URL, now: Date) {
        let manager = FileManager.default
        guard let sessions = try? manager.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return }
        for session in sessions {
            guard let files = try? manager.contentsOfDirectory(
                at: session, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            else { continue }
            var left = files.count
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, expired(modified: modified, now: now) {
                    if (try? manager.removeItem(at: file)) != nil { left -= 1 }
                }
            }
            if left == 0 { try? manager.removeItem(at: session) }
        }
    }

    // MARK: Private

    /// F1's archive (`RadioClips.audioBase`) over https: the only place the token may go.
    static func isArchive(_ url: URL) -> Bool {
        guard let base = URL(string: RadioClips.audioBase) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == base.host?.lowercased()
            && url.port == base.port && url.path.hasPrefix(base.path)
    }

    private static func get(_ url: URL, http: any HTTPClient, bearer: String?) async -> HTTPResponse? {
        var headers = ["User-Agent": Endpoints.userAgent]
        if let bearer { headers["Authorization"] = "Bearer " + bearer }
        do {
            return try await http.send(HTTPRequest(method: "GET", url: url, headers: headers))
        } catch {
            // Never passed on: a transport could have put the header in its error.
            return nil
        }
    }

    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")

    private static func safeName(_ text: String, fallback: String) -> String {
        let name = String(text.map { allowed.contains($0) ? $0 : "_" })
        return name.isEmpty || name.allSatisfy({ $0 == "." }) ? fallback : name
    }
}
