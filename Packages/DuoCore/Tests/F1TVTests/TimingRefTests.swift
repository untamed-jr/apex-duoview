import Foundation
import Testing
@testable import F1TV

private func fixture(_ name: String) throws -> JSONValue {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try JSONValue.parse(Data(contentsOf: url))
}

/// Every tile in a page that the catalogue parser reads, wherever it sits.
private func items(in json: JSONValue) -> [CatalogItem] {
    var out: [CatalogItem] = []
    func walk(_ value: JSONValue) {
        switch value {
        case .object(let members):
            if case .object = value["metadata"], let item = Parsers.catalogItem(value) { out.append(item) }
            for member in members.values { walk(member) }
        case .array(let elements):
            for element in elements { walk(element) }
        default:
            break
        }
    }
    walk(json)
    return out
}

@Suite struct TimingRefTests {
    /// Over every titled item in the real pages: only the race replays, practice and
    /// qualifying count; the shows, highlights, radio, analysis, press conferences and season
    /// reviews (several carrying the race's own key, 11412) don't.
    @Test func onlySessionsInTheRealPages() throws {
        var refs: [TimingRef] = []
        for name in ["weekend-saopaulo", "home", "archive-races", "season-1998"] {
            refs += items(in: try fixture(name)).compactMap(\.timingRef)
        }
        let sessions = Set(refs.filter(\.isSession).map(\.title))
        #expect(sessions == [
            "2026 São Paulo Grand Prix", "2025 São Paulo Grand Prix", "2024 São Paulo Grand Prix",
            "2026 Mexico City Grand Prix", "2026 United States Grand Prix", "2021 Abu Dhabi Grand Prix",
            "2026 São Paulo GP - Practice 2", "2026 São Paulo GP - Practice 3", "2026 São Paulo GP - Qualifying",
        ])
        let others = Set(refs.filter { !$0.isSession }.map(\.title))
        for title in ["Pre-Race Show - Brazil", "Post-Race Show - Brazil", "Race Highlights - São Paulo",
                      "Race in 30 - São Paulo", "Radio Rewind - São Paulo", "Qualifying Highlights - São Paulo",
                      "FIA Post-Race Press Conference - São Paulo", "1998 in Review: Australian Grand Prix"] {
            #expect(others.contains(title), "\(title)")
        }
        // Highlights carry the race's key: the title is what tells them apart.
        #expect(refs.contains { $0.title == "Race Highlights - São Paulo" && $0.sessionKey == "11412" })
    }

    @Test func sessionTitleShapes() {
        func ref(_ title: String, key: String? = "11412") -> TimingRef {
            TimingRef(year: 2026, meetingKey: "1299", sessionKey: key, meetingName: "São Paulo Grand Prix", title: title)
        }
        // Shapes no fixture holds yet (sprint weekends): the title after the last " - ".
        for title in ["2026 Miami GP - Sprint", "2026 Miami GP - Sprint Qualifying", "2024 Miami GP - Sprint Shootout",
                      "2026 Miami GP - Practice 1", "2026 Miami GP - race", " 2026 Emilia-Romagna Grand Prix "] {
            #expect(ref(title).isSession, "\(title)")
        }
        for title in ["Sprint Highlights - Miami", "Pre-Sprint Show - Miami", "Grand Prix Sunday", "",
                      "2026 Miami GP - Practice 4", "Inside: 2026 Miami Grand Prix"] {
            #expect(!ref(title).isSession, "\(title)")
        }
        // No key, or not a number: never a session.
        #expect(!ref("2026 São Paulo Grand Prix", key: nil).isSession)
        #expect(!ref("2026 São Paulo Grand Prix", key: " ").isSession)
        #expect(!ref("2026 São Paulo Grand Prix", key: "11412a").isSession)
    }
}
