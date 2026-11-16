import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct DriversTests {
    /// The brief expected 20 cars; 2026 has 11 teams, so the archive lists 22.
    @Test func driversHas22CarsWithColours() throws {
        let drivers = Drivers.parse(try Fixture.json("sp26-race/DriverList.json"))
        #expect(drivers.count == 22)  // check:driversCount
        // check:driversAllHaveSixHexColour
        #expect(drivers.values.allSatisfy { $0.teamColour.count == 6 && $0.teamColour.allSatisfy(\.isHexDigit) })
        #expect(drivers.allSatisfy { $0.key == $0.value.number })
        // check:driver1
        #expect(drivers["1"] == DriverInfo(number: "1", tla: "NOR", firstName: "Lando", lastName: "Norris",
                                           teamName: "McLaren", teamColour: "F47600"))
    }

    @Test func driverListSkipsNonObjectsAndFallsBack() throws {
        let json = try JSONValue.parse(Data(##"{"_kf":true,"99":{"TeamColour":"#zz"},"7":"x"}"##.utf8))
        let drivers = Drivers.parse(json)
        #expect(drivers.keys.sorted() == ["99"])
        #expect(drivers["99"]?.tla == "99")
        #expect(drivers["99"]?.teamColour == "")
        #expect(Drivers.parse(.null).isEmpty)
    }

    @Test func sessionInfoParsesPathAndCircuitKey() throws {
        // check:raceSessionInfo
        let race = try #require(TimingSessionInfo.parse(try Fixture.json("sp26-race/SessionInfo.json")))
        #expect(race == TimingSessionInfo(
            key: 11412, name: "Race", type: "Race",
            path: "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/",
            start: 1_794_157_200_000, gmtOffsetSeconds: -10800, circuitKey: 14,
            meetingName: "São Paulo Grand Prix", year: 2026))
        // check:qualiSessionInfo
        let quali = try #require(TimingSessionInfo.parse(try Fixture.json("sp26-quali/SessionInfo.json")))
        #expect(quali.key == 11408)
        #expect(quali.type == "Qualifying")
        #expect(quali.path == "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-07_Qualifying/")
        #expect(quali.start == 1_794_074_400_000)
        #expect(quali.circuitKey == 14)
    }

    @Test func sessionInfoNeedsAnObjectWithKeyOrPath() throws {
        #expect(TimingSessionInfo.parse(.null) == nil)
        #expect(TimingSessionInfo.parse(try JSONValue.parse(Data(#"{"Name":"Race"}"#.utf8))) == nil)
        let bare = try #require(TimingSessionInfo.parse(try JSONValue.parse(Data(#"{"Path":"2026/x/"}"#.utf8))))
        #expect(bare.year == 2026)
        #expect(bare.start == nil)
        #expect(bare.gmtOffsetSeconds == 0)
    }
}
