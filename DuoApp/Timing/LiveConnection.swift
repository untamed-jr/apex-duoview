import F1TV
import Foundation
import LiveTiming
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import Network
#endif

/// How negotiating with F1's live timing hub went.
enum LiveNegotiation: Sendable, Equatable {
    /// The connection token for the socket, and the sticky cookie F1's load balancer set (sent
    /// back on the socket so it reaches the same server).
    case connected(connectionToken: String, cookie: String?)
    /// 401/403: not for this sign-in, or not now. Never a sign-out: the connection tries again.
    case refused(status: Int)
    /// The network failed or F1 answered with some other error.
    case failed
}

/// One WebSocket. SignalR's JSON protocol: text frames, each holding whole or partial SignalR
/// frames (`SignalRFrameBuffer` joins them).
protocol LiveSocket: Sendable {
    func send(_ data: Data) async throws
    /// The next message's bytes; throws once the socket is closed or failed.
    func receive() async throws -> Data
    func close()
}

/// The network under `LiveConnection`: the real one is `URLSessionLiveTransport`; checks use a
/// fake.
protocol LiveTransport: Sendable {
    func negotiate(token: String) async -> LiveNegotiation
    func open(connectionToken: String, cookie: String?, token: String) async -> (any LiveSocket)?
}

/// F1's live timing (SignalR Core at `livetiming.formula1.com/signalrcore`), one connection for
/// the whole app, shared and reference-counted: it runs while anyone listens (`listen()`) and
/// stops 15 s after the last listener goes (a listener back within them, such as the multiview
/// taking over from the single player, keeps the same socket and session).
///
/// - Each try: negotiate (keeping the sticky cookie), open the socket with the F1 TV token as
///   `Authorization: Bearer` and the Android user agent the multiview already uses, the
///   handshake, then Subscribe to the 14 topics (13 without CarData.z while "Speed readouts on
///   mobile data" is off on an expensive connection).
/// - A ping every 15 s. A drop (an error, a close, or 30 s without a word from F1) tries again
///   after 5 s, "Live timing dropped — reconnecting…"; after three refusals (401/403) in a row,
///   every 60 s. A refusal never signs anyone out.
/// - Every subscribe result is recorded as opening messages (`RecordedMessage.messages`), the
///   first and those after a reconnect alike; changes as they come.
/// - The session's recording (`LiveRecorder`): opened on every subscribe result whose
///   SessionInfo `Path` differs from the one recorded; the earlier visit's messages come back
///   from the file and are replayed first. A new `Path` arriving as a change ends the try at
///   once: the next subscribe result starts the new session's file (`LiveFeed` empties itself
///   meanwhile, and starts afresh from that snapshot).
/// - `listen()` replays the current session's messages so far, then the link's state, then
///   everything live, with unbounded buffering (a lost change would corrupt the merged state).
///   CarData.z goes to listeners but is neither kept nor recorded.
///
/// The token is read when needed, goes only to livetiming.formula1.com, and is never logged,
/// printed or put in an error.
actor LiveConnection {
    private let transport: any LiveTransport
    private let recorder: LiveRecorder?
    private let token: @Sendable () async -> String?
    /// UTC now, in ms: the subscribe result's stamp and the silence watchdog.
    private let now: @Sendable () -> UTCms

    private var listeners: [Int: AsyncStream<LiveEvent>.Continuation] = [:]
    private var nextListener = 0
    private var link = LiveLink()
    private var runTask: Task<Void, Never>?
    private var socket: (any LiveSocket)?
    /// The current session's recorded messages, for listeners that come later.
    private var history: [RecordedMessage] = []
    /// The session being recorded (its SessionInfo `Path`); nil before the first subscribe result.
    private var sessionPath: String?
    private var lastHeard: UTCms = 0
    /// "Speed readouts on mobile data", and whether the connection is expensive (nil: not known yet).
    private var allowsExpensive = true
    private var expensive: Bool?
    /// Whether the current try subscribed to CarData.z.
    private var subscribedCarData = true
    /// Set when the try must end at once and start again (the car data choice changed).
    private var restartAttempt: Int?
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif
    /// How long the connection stays up after the last listener leaves.
    private let linger: Duration
    /// The wait after the last listener left; cancelled when one comes back.
    private var lingerTask: Task<Void, Never>?
    /// Which wait is current: bumped by each leave and each listen.
    private var lingerTicket = 0

    /// After the last listener leaves, the connection is kept this long for the next.
    static let lingerAfterLastListener: Duration = .seconds(15)

    init(transport: any LiveTransport, recorder: LiveRecorder?, token: @escaping @Sendable () async -> String?,
         now: @escaping @Sendable () -> UTCms = { UTCms((Date().timeIntervalSince1970 * 1000).rounded()) },
         linger: Duration = LiveConnection.lingerAfterLastListener) {
        self.transport = transport
        self.recorder = recorder
        self.token = token
        self.now = now
        self.linger = linger
    }

    /// The current session's messages so far, the link's state, then everything live. The stream
    /// ends when the listener stops reading it (its task is cancelled); the connection stops when
    /// nobody has listened for `linger`.
    func listen() -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self, bufferingPolicy: .unbounded)
        let id = nextListener
        nextListener += 1
        for message in history { continuation.yield(.message(message)) }
        listeners[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.remove(id) }
        }
        // Back within the linger: the connection that is still up serves this listener.
        lingerTicket &+= 1
        lingerTask?.cancel()
        lingerTask = nil
        if runTask == nil { start() }
        // Just started, the run's first try hasn't begun yet: it is connecting all the same.
        continuation.yield(.link(link.reported == .idle ? .connecting : link.reported, everSubscribed: link.everSubscribed,
                                 refused: link.slowed))
        return stream
    }

    /// How many listen (for checks).
    var listenerCount: Int { listeners.count }

    /// "Speed readouts on mobile data": while off on an expensive connection, CarData.z is left
    /// out of the subscription (a change takes effect by subscribing again).
    func setCarData(allowsExpensive: Bool) {
        self.allowsExpensive = allowsExpensive
        carDataChoiceChanged()
    }

    /// Whether CarData.z is subscribed to: allowed on mobile data, or the connection isn't
    /// expensive. Unknown counts as expensive (as `CarDataLoader`).
    var wantsCarData: Bool {
        allowsExpensive || expensive == false
    }

    // MARK: Listeners

    /// The last listener left: the connection stays up `linger` longer, so a player handing over
    /// to another (single feed to multiview) keeps the socket and the session so far.
    private func remove(_ id: Int) {
        guard listeners.removeValue(forKey: id) != nil, listeners.isEmpty else { return }
        lingerTicket &+= 1
        let ticket = lingerTicket
        let linger = linger
        lingerTask?.cancel()
        lingerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: linger)
            } catch {
                return  // a listener came back
            }
            await self?.stopIfNobodyListens(ticket)
        }
    }

    /// The linger `ticket` ran out: everything stops unless a listener came meanwhile.
    private func stopIfNobodyListens(_ ticket: Int) async {
        guard ticket == lingerTicket, listeners.isEmpty else { return }
        lingerTask = nil
        runTask?.cancel()
        runTask = nil
        socket?.close()
        socket = nil
        link.stopped()
        history = []
        sessionPath = nil
        stopMonitor()
        await recorder?.end()
    }

    private func broadcast(_ event: LiveEvent) {
        for continuation in listeners.values { continuation.yield(event) }
    }

    private func broadcastLink() {
        broadcast(.link(link.reported, everSubscribed: link.everSubscribed, refused: link.slowed))
    }

    // MARK: The run

    private func start() {
        startMonitor()
        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    private enum Ending: Equatable {
        case failed
        case refused
        /// Start again at once: a new session came as a change, or the car data choice changed.
        case restart
    }

    private func run() async {
        var restart = false
        while !Task.isCancelled {
            let attempt = link.connecting(restart: restart)
            // A planned restart says nothing: listeners still hear subscribed.
            if !link.restarting { broadcastLink() }
            // The try closes its own socket: a run superseded while it waited (its listeners
            // gone, a new run started) must never close the new run's.
            let ending = await connect(attempt: attempt)
            guard !Task.isCancelled, link.attempt == attempt else { return }
            restart = ending == .restart
            if restart { continue }
            guard let delay = link.dropped(attempt: attempt, refused: ending == .refused) else { return }
            broadcastLink()
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    /// One try, from negotiating to the socket's end.
    private func connect(attempt: Int) async -> Ending {
        guard let token = await token(), !token.isEmpty else { return .failed }
        await carDataKnown()
        guard link.attempt == attempt else { return .failed }
        let connectionToken: String
        let cookie: String?
        switch await transport.negotiate(token: token) {
        case .connected(let id, let sticky):
            connectionToken = id
            cookie = sticky
        case .refused:
            return .refused
        case .failed:
            return .failed
        }
        guard link.attempt == attempt, !Task.isCancelled,
              let socket = await transport.open(connectionToken: connectionToken, cookie: cookie, token: token)
        else { return .failed }
        guard link.attempt == attempt, !Task.isCancelled else {
            socket.close()
            return .failed
        }
        self.socket = socket
        defer {
            socket.close()
            // Cleared only while this try is current: a newer one may hold its own by now.
            if link.attempt == attempt { self.socket = nil }
        }
        lastHeard = now()
        let carData = wantsCarData
        subscribedCarData = carData
        let topics = carData ? SignalR.topics : SignalR.topics.filter { $0 != "CarData.z" }
        let pinger = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: LiveLink.pingInterval)
                } catch {
                    return
                }
                await self?.keepAlive(attempt: attempt)
            }
        }
        defer { pinger.cancel() }
        var frames = SignalRFrameBuffer()
        var handshook = false
        do {
            try await socket.send(SignalR.handshake())
            while !Task.isCancelled, link.attempt == attempt {
                let data = try await socket.receive()
                guard link.attempt == attempt else { return .failed }
                if restartAttempt == attempt { return .restart }
                lastHeard = now()
                for json in frames.append(data) {
                    guard handshook else {
                        // The handshake's reply: "{}", or an error.
                        guard json["error"].string.isEmpty else { return .failed }
                        handshook = true
                        try await socket.send(SignalR.subscribe(invocationId: "1", topics: topics))
                        continue
                    }
                    switch await handle(json, attempt: attempt) {
                    case .some(let ending): return ending
                    case .none: continue
                    }
                }
            }
        } catch {
            // Closed or failed: the error's text is never passed on.
        }
        return restartAttempt == attempt ? .restart : .failed
    }

    /// One SignalR frame of try `attempt`; an ending when the try must stop.
    private func handle(_ json: JSONValue, attempt: Int) async -> Ending? {
        let message = SignalR.message(json)
        switch message {
        case .snapshot:
            let records = RecordedMessage.messages(from: message, receivedAt: now())
            guard link.subscribed(attempt: attempt) else { return .failed }
            let info = records.first { $0.topic == "SessionInfo" }?.json
            let path = info?["Path"].string ?? ""
            if !path.isEmpty, path != sessionPath {
                // A new session for this run (or the first): its file, and what it already holds.
                let earlier = await recorder?.begin(sessionKey: info?["Key"].int, sessionPath: path) ?? []
                guard link.attempt == attempt else { return .failed }
                sessionPath = path
                history = earlier
                for message in earlier { broadcast(.message(message)) }
            }
            await take(records)
            broadcastLink()
            return nil
        case .feed(let topic, let data, _):
            if topic == "SessionInfo", let current = sessionPath {
                let path = data["Path"].string
                if !path.isEmpty, path != current {
                    // Another session as a change: listeners' feeds empty themselves on it; the
                    // next subscribe result starts the new session.
                    for record in RecordedMessage.messages(from: message, receivedAt: now()) { broadcast(.message(record)) }
                    return .restart
                }
            }
            await take(RecordedMessage.messages(from: message, receivedAt: now()))
            return nil
        case .close:
            return .failed
        case .ping, .other:
            return nil
        }
    }

    /// Keeps, records (in order) and hands on messages of the current session.
    private func take(_ records: [RecordedMessage]) async {
        let kept = sessionPath == nil ? [] : records.filter { LiveRecording.records($0.topic) }
        // Kept and handed on together, before any wait: a listener joining meanwhile gets each
        // message once, from the history or live.
        history.append(contentsOf: kept)
        for record in records { broadcast(.message(record)) }
        if !kept.isEmpty { await recorder?.record(kept) }
    }

    /// The 15 s tick of try `attempt`: a ping, and the socket closed after 30 s of silence (its
    /// receive then throws and the try ends).
    private func keepAlive(attempt: Int) async {
        guard link.attempt == attempt, let socket else { return }
        if LiveLink.silent(lastHeard: lastHeard, now: now()) {
            socket.close()
            return
        }
        try? await socket.send(SignalR.ping())
    }

    // MARK: Car data and the network

    private func carDataChoiceChanged() {
        guard link.phase == .subscribed || link.phase == .connecting, wantsCarData != subscribedCarData,
              let socket else { return }
        restartAttempt = link.attempt
        socket.close()
    }

    /// Waits up to 1 s for the network monitor's first answer, so the first Subscribe already
    /// knows whether the connection is expensive.
    private func carDataKnown() async {
        for _ in 0..<10 where expensive == nil && !allowsExpensive {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The network monitor's answer (internal for checks).
    func pathChanged(expensive: Bool) {
        guard self.expensive != expensive else { return }
        self.expensive = expensive
        carDataChoiceChanged()
    }

    private func startMonitor() {
        #if canImport(Network)
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let expensive = path.isExpensive
            Task { await self?.pathChanged(expensive: expensive) }
        }
        monitor.start(queue: DispatchQueue(label: "live.path", qos: .utility))
        self.monitor = monitor
        #else
        expensive = false
        #endif
    }

    private func stopMonitor() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        expensive = nil
        #endif
    }
}

// MARK: - URLSession

/// The real network: negotiate with a POST, then a `URLSessionWebSocketTask`, both to
/// livetiming.formula1.com only, with the Android user agent. Its own ephemeral session: no
/// stored cookies (the sticky one is passed by hand), and a redirect off the host drops the
/// token (`TimingRedirectGuard`). Errors are never passed on (a transport could put the header
/// in one).
final class URLSessionLiveTransport: LiveTransport {
    static let host = "livetiming.formula1.com"
    static let negotiateURL = URL(string: "https://livetiming.formula1.com/signalrcore/negotiate?negotiateVersion=1")!
    static let socketURL = "wss://livetiming.formula1.com/signalrcore"
    /// A subscribe result mid-race is large: well above URLSession's 1 MB default.
    static let maximumMessageSize = 64 << 20

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: TimingRedirectGuard(), delegateQueue: nil)
    }

    func negotiate(token: String) async -> LiveNegotiation {
        var request = URLRequest(url: Self.negotiateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(Endpoints.androidUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            switch http.statusCode {
            case 200..<300:
                guard let json = try? JSONValue.parse(data), let id = SignalR.negotiateToken(json) else { return .failed }
                return .connected(connectionToken: id, cookie: Self.cookie(from: http))
            case 401, 403:
                return .refused(status: http.statusCode)
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    func open(connectionToken: String, cookie: String?, token: String) async -> (any LiveSocket)? {
        guard var components = URLComponents(string: Self.socketURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: connectionToken)]
        guard let url = components.url, url.host == Self.host else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(Endpoints.androidUserAgent, forHTTPHeaderField: "User-Agent")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = Self.maximumMessageSize
        task.resume()
        return URLSessionLiveSocket(task: task)
    }

    /// The `Cookie` header for the cookies the reply set (the load balancer's sticky one).
    static func cookie(from response: HTTPURLResponse) -> String? {
        guard let url = response.url else { return nil }
        var fields: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String, let value = value as? String { fields[name] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }
}

/// A `URLSessionWebSocketTask` as a `LiveSocket`. The task is thread-safe; it is only sent,
/// received and cancelled.
final class URLSessionLiveSocket: LiveSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: return Data()
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
