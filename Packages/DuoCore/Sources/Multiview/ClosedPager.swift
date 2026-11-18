import Foundation
import LiveTiming

/// The pages of the closed phone's cover screen, top to bottom.
public enum ClosedPage: String, CaseIterable, Codable, Sendable {
    case picture, radio, gap
}

/// Moving between the closed phone's pages and drivers.
public enum ClosedPager {
    /// The page a swipe up (`up`) or down leads to: picture, radio, gap, with no wrap. Nil at
    /// either end.
    public static func page(from: ClosedPage, up: Bool) -> ClosedPage? {
        let pages = ClosedPage.allCases
        guard let i = pages.firstIndex(of: from) else { return nil }
        let j = up ? i + 1 : i - 1
        return pages.indices.contains(j) ? pages[j] : nil
    }

    /// The racing numbers in running order at `t`: by timing position, cars without one last,
    /// ties and unknowns by number. Every car timing or DriverList names is in it. Only timing is
    /// read; radio never decides the order.
    public static func raceOrder(at t: UTCms, session: LoadedSession) -> [String] {
        let timing = session.timing.at(t)
        let numbers = Set(timing.keys).union(session.drivers.keys)
        return numbers.sorted { a, b in
            let pa = timing[a]?.position, pb = timing[b]?.position
            switch (pa, pb) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return byNumber(a, b)
            }
        }
    }

    /// The driver after (`forward`) or before `current` in `order`, wrapping round. With no
    /// current driver, or one not in the order, forward gives the first and back the last. Nil for
    /// an empty order.
    public static func driver(after current: String?, forward: Bool, order: [String]) -> String? {
        guard !order.isEmpty else { return nil }
        guard let current, let i = order.firstIndex(of: current) else {
            return forward ? order.first : order.last
        }
        let n = order.count
        return order[(i + (forward ? 1 : n - 1)) % n]
    }

    /// Who the cover shows first: the favourite when they are in `order`, else the leader.
    public static func defaultDriver(favourite: String?, order: [String]) -> String? {
        if let favourite, order.contains(favourite) { return favourite }
        return order.first
    }

    /// By number, numerically when both are numbers.
    private static func byNumber(_ a: String, _ b: String) -> Bool {
        if let x = Int(a), let y = Int(b), x != y { return x < y }
        return a < b
    }
}
