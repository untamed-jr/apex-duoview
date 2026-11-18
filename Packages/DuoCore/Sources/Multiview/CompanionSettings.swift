import Foundation
import Library
import LiveTiming

/// The closed phone's cards the viewer can switch on or off together. A purple sector has no card.
public enum CardGroup: String, CaseIterable, Codable, Sendable {
    case flags, myStopsAndRadio, myPositions, chequered

    /// The group an event's card belongs to; nil for an event with no card (a purple sector).
    public static func of(_ kind: CompanionEventKind) -> CardGroup? {
        switch kind {
        case .yellow, .safetyCar, .vsc, .red: return .flags
        case .pit, .radio, .out: return .myStopsAndRadio
        case .passed: return .myPositions
        case .chequered: return .chequered
        case .purpleSector: return nil
        }
    }
}

/// Which radio messages the Radio page lists.
public enum RadioFilter: Codable, Sendable, Equatable {
    case all, myDriver, driver(String)
}

/// The beta.4 choices (radio, closed phone, haptics), kept between launches. Stored as JSON under
/// keys that start with "companion.". As `MultiviewStore` and `TimingSettings` do: each call is
/// atomic for this instance, and a value that can't be read (or isn't one of the allowed values)
/// gives the starting value. Transcripts are made on the phone only: there is no server choice.
public final class CompanionSettings: @unchecked Sendable {
    static let prefix = "companion."
    static let transcriptsKey = prefix + "transcripts"
    static let autoPlayRadioKey = prefix + "autoPlayRadio"
    static let hingeMixerKey = prefix + "hingeMixer"
    static let hapticsKey = prefix + "haptics"
    static let showHapticsOnScreenKey = prefix + "showHapticsOnScreen"
    static let rewindSecondsKey = prefix + "rewindSeconds"
    static let lastClosedPageKey = prefix + "lastClosedPage"
    static let scannerDriverKey = prefix + "scannerDriver"
    static let gapPairKey = prefix + "gapPair"
    static let radioFilterKey = prefix + "radioFilter"
    static let closedHintShownKey = prefix + "closedHintShown"
    static func hapticKey(_ kind: HapticKind) -> String { prefix + "haptic." + kind.rawValue }
    static func cardGroupKey(_ group: CardGroup) -> String { prefix + "cardGroup." + group.rawValue }

    /// The seconds the rewind button goes back.
    public static let rewindChoices = [3, 5, 10, 15]
    public static let defaultRewindSeconds = 5

    private let lock = NSLock()
    private let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    /// Radio transcripts, made on the phone. On until switched off.
    public var transcripts: Bool {
        get { bool(Self.transcriptsKey, default: true) }
        set { setBool(Self.transcriptsKey, newValue) }
    }

    /// "Play radio as it happens": the Radio Scanner and Ear-Matched Rivals only. On until switched off.
    public var autoPlayRadio: Bool {
        get { bool(Self.autoPlayRadioKey, default: true) }
        set { setBool(Self.autoPlayRadioKey, newValue) }
    }

    /// The hinge audio mixer. Off until switched on.
    public var hingeMixer: Bool {
        get { bool(Self.hingeMixerKey, default: false) }
        set { setBool(Self.hingeMixerKey, newValue) }
    }

    /// All haptics at once; each kind also has its own switch. On until switched off.
    public var haptics: Bool {
        get { bool(Self.hapticsKey, default: true) }
        set { setBool(Self.hapticsKey, newValue) }
    }

    /// This kind's own switch (it does not look at `haptics`). On until switched off.
    public func hapticOn(_ kind: HapticKind) -> Bool { bool(Self.hapticKey(kind), default: true) }

    public func setHaptic(_ kind: HapticKind, on: Bool) { setBool(Self.hapticKey(kind), on) }

    /// Whether this group of cards shows. On until switched off.
    public func cardGroupOn(_ group: CardGroup) -> Bool { bool(Self.cardGroupKey(group), default: true) }

    public func setCardGroup(_ group: CardGroup, on: Bool) { setBool(Self.cardGroupKey(group), on) }

    /// "Show haptics on screen", a switch of its own. Off until switched on.
    public var showHapticsOnScreen: Bool {
        get { bool(Self.showHapticsOnScreenKey, default: false) }
        set { setBool(Self.showHapticsOnScreenKey, newValue) }
    }

    /// 3, 5, 10 or 15; anything else (set or stored) is 5.
    public var rewindSeconds: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return Self.allowedRewind(read(Int.self, Self.rewindSecondsKey) ?? Self.defaultRewindSeconds)
        }
        set {
            lock.lock(); defer { lock.unlock() }
            write(Self.allowedRewind(newValue), Self.rewindSecondsKey)
        }
    }

    /// The page the closed phone opens on: the one used last, the picture the first time.
    public var lastClosedPage: ClosedPage {
        get { lock.lock(); defer { lock.unlock() }; return read(ClosedPage.self, Self.lastClosedPageKey) ?? .picture }
        set { lock.lock(); defer { lock.unlock() }; write(newValue, Self.lastClosedPageKey) }
    }

    /// The racing number the Radio Scanner is on; nil when none was chosen. nil forgets it.
    public var scannerDriver: String? {
        get { lock.lock(); defer { lock.unlock() }; return read(String.self, Self.scannerDriverKey) }
        set {
            lock.lock(); defer { lock.unlock() }
            if let newValue { write(newValue, Self.scannerDriverKey) } else { store.set(nil, forKey: Self.scannerDriverKey) }
        }
    }

    /// The two racing numbers the Gap page compares; nil when none were chosen, or when what is
    /// stored is not two different numbers. Setting a pair of any other size forgets the stored one
    /// (more than two keep the first two). nil forgets it.
    public var gapPair: [String]? {
        get {
            lock.lock(); defer { lock.unlock() }
            guard let pair = read([String].self, Self.gapPairKey), Self.validPair(pair) else { return nil }
            return pair
        }
        set {
            lock.lock(); defer { lock.unlock() }
            guard let newValue else { store.set(nil, forKey: Self.gapPairKey); return }
            let pair = Array(newValue.prefix(2))
            if Self.validPair(pair) { write(pair, Self.gapPairKey) } else { store.set(nil, forKey: Self.gapPairKey) }
        }
    }

    /// Which radio the Radio page lists; all until chosen.
    public var radioFilter: RadioFilter {
        get { lock.lock(); defer { lock.unlock() }; return read(RadioFilter.self, Self.radioFilterKey) ?? .all }
        set { lock.lock(); defer { lock.unlock() }; write(newValue, Self.radioFilterKey) }
    }

    /// Whether the hint about the closed phone was shown. Off until shown.
    public var closedHintShown: Bool {
        get { bool(Self.closedHintShownKey, default: false) }
        set { setBool(Self.closedHintShownKey, newValue) }
    }

    // MARK: - Private

    private static func allowedRewind(_ value: Int) -> Int {
        rewindChoices.contains(value) ? value : defaultRewindSeconds
    }

    private static func validPair(_ pair: [String]) -> Bool {
        pair.count == 2 && pair[0] != pair[1] && pair.allSatisfy { !$0.isEmpty }
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return read(Bool.self, key) ?? value
    }

    private func setBool(_ key: String, _ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        write(value, key)
    }

    private func read<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
    }
}
