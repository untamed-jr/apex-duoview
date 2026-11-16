import Foundation
import Library
#if canImport(CoreGraphics)
// On Apple platforms CGRect lives in CoreGraphics; on Linux Foundation defines it.
import CoreGraphics
#endif

/// The viewer's timing choices, kept between launches: the picture offset, each circuit's map
/// turn and pit loss, where panels sit, and a few switches. Stored as JSON under keys that start
/// with "timing.". As `MultiviewStore` does: each call is atomic for this instance, a value that
/// can't be read gives the starting value, and a value that can't be encoded (not a number)
/// leaves the stored one as it was. Changes that read the stored value first (`nudge`,
/// `nudgeTrackerDelay`, `toggleHiddenCard`) are one atomic call each: use them rather than a get
/// then a set.
///
/// Panel and posture names become part of a key ("timing.panelFrame.<posture>.<panel>"): they
/// must not contain "." (or "book" + "a.map" and "book.a" + "map" would share a key). Callers
/// use fixed names such as "map" and "book-wide".
public final class TimingSettings: @unchecked Sendable {
    static let offsetKey = "timing.offsetMs"
    static let showWholeRaceKey = "timing.showWholeRace"
    static let trackerDelayKey = "timing.trackerDelayHalfSeconds"
    static let hiddenCardsKey = "timing.hiddenCards"
    static let speedOnMobileDataKey = "timing.speedOnMobileData"
    /// The fixed keys; the per-circuit and per-panel ones are made by the functions below.
    static let keys = [offsetKey, showWholeRaceKey, trackerDelayKey, hiddenCardsKey, speedOnMobileDataKey]

    static func mapTurnKey(_ circuitKey: Int) -> String { "timing.mapTurn.\(circuitKey)" }
    static func pitLossKey(_ circuitKey: Int) -> String { "timing.pitLossMs.\(circuitKey)" }
    static func panelFrameKey(_ panel: String, posture: String) -> String { "timing.panelFrame.\(posture).\(panel)" }

    /// The tracker delay's range, in half-seconds (0 to 20 s).
    public static let trackerDelayRange = 0...40
    /// How far the picture offset may go either way, in ms: further than any broadcast delay, and
    /// a value read back from a bad store can't put timing hours away.
    public static let offsetLimitMs: Int64 = 60_000

    private let lock = NSLock()
    private let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    // MARK: Picture offset

    /// `PictureClock`'s offset; `PictureClock.defaultOffsetMs` until changed. Kept within
    /// ±`offsetLimitMs` when set and when read.
    public var offsetMs: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return loadOffset() }
        set { lock.lock(); defer { lock.unlock() }; write(Self.clampedOffset(newValue), Self.offsetKey) }
    }

    /// Moves the offset by whole seconds (positive is later), within ±`offsetLimitMs`.
    public func nudge(by seconds: Int) {
        lock.lock(); defer { lock.unlock() }
        let (ms, overflow) = Int64(seconds).multipliedReportingOverflow(by: 1000)
        let step = overflow ? (seconds > 0 ? Int64.max : .min) : ms
        write(Self.clampedOffset(F1Values.add(loadOffset(), step)), Self.offsetKey)
    }

    public func resetOffset() {
        lock.lock(); defer { lock.unlock() }
        write(PictureClock.defaultOffsetMs, Self.offsetKey)
    }

    // MARK: Per circuit

    /// How far the viewer turned this circuit's map, in degrees; 0 until turned.
    public func mapTurn(circuitKey: Int) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let turn = read(Double.self, Self.mapTurnKey(circuitKey)), turn.isFinite else { return 0 }
        return turn
    }

    public func setMapTurn(_ degrees: Double, circuitKey: Int) {
        lock.lock(); defer { lock.unlock() }
        write(degrees, Self.mapTurnKey(circuitKey))
    }

    /// The time a pit stop costs at this circuit, as the viewer set it; nil when unset (or
    /// stored negative).
    public func pitLossMs(circuitKey: Int) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let ms = read(Int64.self, Self.pitLossKey(circuitKey)), ms >= 0 else { return nil }
        return ms
    }

    /// nil forgets it.
    public func setPitLossMs(_ ms: Int64?, circuitKey: Int) {
        lock.lock(); defer { lock.unlock() }
        if let ms { write(ms, Self.pitLossKey(circuitKey)) } else { store.set(nil, forKey: Self.pitLossKey(circuitKey)) }
    }

    // MARK: Panels

    /// Where the viewer put a panel ("map", "leaderboard", ...) in a posture ("portrait",
    /// "landscape", ...); nil when never moved, or when what is stored is not a finite frame
    /// with some width and height.
    public func panelFrame(_ panel: String, posture: String) -> CGRect? {
        lock.lock(); defer { lock.unlock() }
        guard let v = read([Double].self, Self.panelFrameKey(panel, posture: posture)), v.count == 4,
              v.allSatisfy(\.isFinite), v[2] > 0, v[3] > 0 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    /// nil forgets it.
    public func setPanelFrame(_ frame: CGRect?, panel: String, posture: String) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.panelFrameKey(panel, posture: posture)
        guard let frame else { store.set(nil, forKey: key); return }
        // Stored as four plain numbers: a frame that isn't finite then fails to encode.
        write([Double(frame.origin.x), Double(frame.origin.y), Double(frame.size.width), Double(frame.size.height)], key)
    }

    // MARK: Switches

    /// "Show the whole race on the Scrub Deck": data later than the picture, opt-in.
    public var showWholeRace: Bool {
        get { lock.lock(); defer { lock.unlock() }; return read(Bool.self, Self.showWholeRaceKey) ?? false }
        set { lock.lock(); defer { lock.unlock() }; write(newValue, Self.showWholeRaceKey) }
    }

    /// How far the tracker trails the picture, in half-seconds, kept within `trackerDelayRange`
    /// when set and when read. Applied by the multiview sync.
    public var trackerDelayHalfSeconds: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return Self.clampedDelay(read(Int.self, Self.trackerDelayKey) ?? 0)
        }
        set { lock.lock(); defer { lock.unlock() }; write(Self.clampedDelay(newValue), Self.trackerDelayKey) }
    }

    /// Moves the tracker delay by `halfSeconds` (positive is longer), within `trackerDelayRange`.
    /// Returns the new value.
    @discardableResult
    public func nudgeTrackerDelay(by halfSeconds: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let current = Self.clampedDelay(read(Int.self, Self.trackerDelayKey) ?? 0)
        let (sum, overflow) = current.addingReportingOverflow(halfSeconds)
        let value = Self.clampedDelay(overflow ? (halfSeconds > 0 ? Int.max : Int.min) : sum)
        write(value, Self.trackerDelayKey)
        return value
    }

    /// Channel ids whose driver cards the viewer hid.
    public var hiddenCards: Set<Int> {
        get { lock.lock(); defer { lock.unlock() }; return Set(read([Int].self, Self.hiddenCardsKey) ?? []) }
        // Sorted, so the same set is always stored the same way.
        set { lock.lock(); defer { lock.unlock() }; write(newValue.sorted(), Self.hiddenCardsKey) }
    }

    /// Hides this channel's card if it shows, shows it if hidden. Returns whether it is now hidden.
    @discardableResult
    public func toggleHiddenCard(_ channelId: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var cards = Set(read([Int].self, Self.hiddenCardsKey) ?? [])
        let hidden = cards.remove(channelId) == nil
        if hidden { cards.insert(channelId) }
        write(cards.sorted(), Self.hiddenCardsKey)
        return hidden
    }

    /// "Speed readouts on mobile data": the car data behind the speed readouts may download on
    /// an expensive (cellular) connection.
    public var speedOnMobileData: Bool {
        get { lock.lock(); defer { lock.unlock() }; return read(Bool.self, Self.speedOnMobileDataKey) ?? true }
        set { lock.lock(); defer { lock.unlock() }; write(newValue, Self.speedOnMobileDataKey) }
    }

    // MARK: - Private (callers hold the lock)

    private static func clampedDelay(_ value: Int) -> Int {
        min(max(value, trackerDelayRange.lowerBound), trackerDelayRange.upperBound)
    }

    private static func clampedOffset(_ ms: Int64) -> Int64 {
        min(max(ms, -offsetLimitMs), offsetLimitMs)
    }

    private func loadOffset() -> Int64 { Self.clampedOffset(read(Int64.self, Self.offsetKey) ?? PictureClock.defaultOffsetMs) }

    private func read<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// A value that can't be encoded leaves the stored one as it was (never removes the key).
    private func write<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
    }
}
