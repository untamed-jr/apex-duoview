import Testing
import Foundation
@testable import Multiview

@Suite struct LayoutEngineTests {
    struct Reference: Decodable {
        struct Entry: Decodable {
            let posture: String
            let feeds: Int
            let id: String
            let visible: Int
            let frames: [[Double]]
        }
        let layouts: [Entry]
    }

    static func loadReference() throws -> Reference {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/layouts-reference.json")
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }

    /// Screen and fold used by the reference JSON.
    static func referenceGeometry(_ posture: Posture) -> (CGSize, CGRect) {
        posture == .laptop
            ? (CGSize(width: 669, height: 951), CGRect(x: 0, y: 456, width: 669, height: 40))
            : (CGSize(width: 951, height: 669), CGRect(x: 456, y: 0, width: 40, height: 669))
    }

    /// A 40 pt fold centred on `screen`; horizontal for laptop, vertical otherwise. The reference
    /// folds are used where the screen matches the reference screen for that posture.
    static func fold(for posture: Posture, screen: CGSize) -> CGRect {
        let ref = referenceGeometry(posture)
        if ref.0 == screen { return ref.1 }
        return posture == .laptop
            ? CGRect(x: 0, y: (screen.height - 40) / 2, width: screen.width, height: 40)
            : CGRect(x: (screen.width - 40) / 2, y: 0, width: 40, height: screen.height)
    }

    @Test func matchesReferenceFrames() throws {
        let ref = try Self.loadReference()
        #expect(!ref.layouts.isEmpty)
        for e in ref.layouts {
            let posture = try #require(Posture(rawValue: e.posture))
            let (screen, fold) = Self.referenceGeometry(posture)
            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                             feedCount: e.feeds, optionID: e.id)
            #expect(frames.count == e.feeds, "\(e.id)/\(e.feeds)")
            let visible = frames.filter(\.visible)
            #expect(visible.count == e.visible, "\(e.id)/\(e.feeds)")
            for (f, r) in zip(visible, e.frames) {
                #expect(abs(f.rect.minX - r[0]) < 0.5, "\(e.id)/\(e.feeds) x")
                #expect(abs(f.rect.minY - r[1]) < 0.5, "\(e.id)/\(e.feeds) y")
                #expect(abs(f.rect.width - r[2]) < 0.5, "\(e.id)/\(e.feeds) w")
                #expect(abs(f.rect.height - r[3]) < 0.5, "\(e.id)/\(e.feeds) h")
            }
        }
    }

    @Test func defaultsAreFirstOption() {
        #expect(LayoutEngine.optionIDs(posture: .book, feedCount: 1).first == "book.across")
        #expect(LayoutEngine.optionIDs(posture: .flat, feedCount: 4).first == "flat.mainBelow")
        #expect(LayoutEngine.optionIDs(posture: .laptop, feedCount: 4) == ["laptop.pyramid"])
        #expect(LayoutEngine.optionIDs(posture: .closed, feedCount: 3) == ["closed.stack"])
        #expect(LayoutEngine.optionIDs(posture: .closed, feedCount: 1) == ["closed.main"])
        #expect(LayoutEngine.optionIDs(posture: .unknown, feedCount: 2) == LayoutEngine.optionIDs(posture: .flat, feedCount: 2))
    }

    @Test func screenUseFloors() {
        // Floors are the spec table's percentages rounded to 0.1%, so compare after rounding to 0.1% (true values are up to 0.04% below).
        for (posture, floor) in [(Posture.flat, 0.906), (.book, 0.696), (.laptop, 0.663)] {
            let (screen, fold) = Self.referenceGeometry(posture)
            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                             feedCount: 4, optionID: nil)
            let use = LayoutEngine.screenUse(frames, screen: screen)
            #expect((use * 1000).rounded() / 1000 >= floor - 1e-9, "\(posture) \(use)")
        }
    }

    static let screens = [CGSize(width: 951, height: 669), CGSize(width: 669, height: 951),
                          CGSize(width: 1020, height: 700)]

    @Test func everyTileIs16x9OnScreenAndWideEnough() {
        for screen in Self.screens {
            let bounds = CGRect(origin: .zero, size: screen)
            for posture in Posture.allCases {
                for n in 1...4 {
                    for id in LayoutEngine.optionIDs(posture: posture, feedCount: n) {
                        let frames = LayoutEngine.frames(screen: screen,
                                                         foldFrame: Self.fold(for: posture, screen: screen),
                                                         posture: posture, feedCount: n, optionID: id)
                        #expect(frames.count == n)
                        #expect(frames.first?.visible == true)
                        for f in frames where f.visible {
                            let tag = "\(posture) \(id) n=\(n) \(screen) \(f.rect)"
                            #expect(bounds.contains(f.rect), "\(tag)")
                            if posture != .closed { #expect(f.rect.width >= 200 - 0.01, "\(tag)") }
                            #expect(abs(f.rect.width * 9 / 16 - f.rect.height) < 0.5, "\(tag)")
                        }
                    }
                }
            }
        }
    }

    @Test func nothingCrossesTheFoldUnlessAcross() {
        for screen in Self.screens {
            for posture in [Posture.book, .laptop] {
                let fold = Self.fold(for: posture, screen: screen)
                for n in 1...4 {
                    for id in LayoutEngine.optionIDs(posture: posture, feedCount: n) where id != "book.across" {
                        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                                         feedCount: n, optionID: id)
                        for f in frames where f.visible {
                            #expect(!f.rect.intersects(fold), "\(id) n=\(n) \(screen) \(f.rect)")
                        }
                    }
                }
            }
        }
    }

    @Test func bookWithoutFoldFallsBackToFlat() {
        let screen = CGSize(width: 951, height: 669)
        for posture in [Posture.book, .laptop] {
            for n in 1...4 {
                let a = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: posture, feedCount: n, optionID: nil)
                let b = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .flat, feedCount: n, optionID: nil)
                #expect(a == b)
            }
        }
    }

    @Test func unknownOrNilOptionMeansDefault() {
        let (screen, fold) = Self.referenceGeometry(.flat)
        let d = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat, feedCount: 3, optionID: nil)
        let u = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat, feedCount: 3, optionID: "nope")
        let first = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat, feedCount: 3, optionID: "flat.mainBelow")
        #expect(d == first)
        #expect(u == first)
    }

    @Test func closedFillsScreen() {
        let screen = CGSize(width: 844, height: 390)
        // One tile asked by name; with two or more feeds the default is the stack (below).
        let frames = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .closed, feedCount: 3, optionID: "closed.main")
        #expect(frames.count == 3)
        #expect(frames[0].visible)
        #expect(abs(frames[0].rect.width - 693.3) < 0.1)
        #expect(abs(frames[0].rect.height - 390) < 0.01)
        #expect(abs(frames[0].rect.midX - 422) < 0.01)
        #expect(frames.dropFirst().allSatisfy { !$0.visible && $0.rect == frames[0].rect })
    }

    /// The outer screen the owner measured (466 × 678 pt), and the same less some safe-area height.
    @Test func closedStackTwoFullWidthMainOnTop() {
        for screen in [CGSize(width: 466, height: 678), CGSize(width: 466, height: 610)] {
            for n in 2...4 {
                for id in [nil, "closed.stack", "nope"] as [String?] {
                    let frames = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .closed, feedCount: n, optionID: id)
                    let tag = "\(screen) n=\(n) \(id ?? "nil")"
                    #expect(frames.count == n, "\(tag)")
                    let top = frames[0].rect, bottom = frames[1].rect
                    #expect(frames[0].visible && frames[1].visible, "\(tag)")
                    // Both tiles the full width, 16:9.
                    #expect(abs(top.width - 466) < 0.01 && abs(bottom.width - 466) < 0.01, "\(tag)")
                    #expect(top.minX == 0 && bottom.minX == 0, "\(tag)")
                    #expect(abs(top.height - 466 * 9 / 16) < 0.01, "\(tag)")
                    // The main one on top, one gap between, both within the height, centred.
                    #expect(top.maxY < bottom.minY, "\(tag)")
                    #expect(abs(bottom.minY - top.maxY - 6) < 0.01, "\(tag)")
                    #expect(top.minY >= 0 && bottom.maxY <= screen.height, "\(tag)")
                    #expect(abs(top.minY - (screen.height - bottom.maxY)) < 0.01, "\(tag)")
                    // Any others hidden under the main tile.
                    #expect(frames.dropFirst(2).allSatisfy { !$0.visible && $0.rect == top }, "\(tag)")
                }
            }
        }
        // One feed keeps the one tile; so does a screen too short for two full-width tiles,
        // where the pair shrinks to fit the height instead.
        let one = LayoutEngine.frames(screen: CGSize(width: 466, height: 678), foldFrame: nil, posture: .closed,
                                      feedCount: 1, optionID: "closed.stack")
        #expect(one.count == 1 && abs(one[0].rect.width - 466) < 0.01)
        let short = CGSize(width: 466, height: 400)
        let pair = LayoutEngine.frames(screen: short, foldFrame: nil, posture: .closed, feedCount: 2, optionID: nil)
        #expect(pair[1].rect.maxY <= 400 + 0.01 && pair[0].rect.width < 466)
        #expect(abs(pair[0].rect.height * 2 + 6 - 400) < 0.01)
        #expect(LayoutEngine.usableOptionIDs(screen: short, foldFrame: nil, posture: .closed, feedCount: 2) == ["closed.stack"])
    }

    @Test func reservedAreaOnlyForLaptopOneFeed() {
        let (screen, fold) = Self.referenceGeometry(.laptop)
        let r = LayoutEngine.reservedArea(screen: screen, foldFrame: fold, posture: .laptop, feedCount: 1)
        #expect(r == CGRect(x: 6, y: 502, width: 657, height: 443))
        #expect(LayoutEngine.reservedArea(screen: screen, foldFrame: fold, posture: .laptop, feedCount: 2) == nil)
        #expect(LayoutEngine.reservedArea(screen: screen, foldFrame: fold, posture: .flat, feedCount: 1) == nil)
        #expect(LayoutEngine.reservedArea(screen: screen, foldFrame: fold, posture: .book, feedCount: 1) == nil)
    }

    // MARK: Degenerate inputs and fallbacks

    static let oddScreens = [CGSize(width: 400, height: 700), CGSize(width: 700, height: 400),
                             CGSize(width: 320, height: 480), CGSize(width: 951, height: 669),
                             CGSize(width: 100, height: 100), CGSize(width: 10, height: 10)]
    static let oddFolds: [CGRect?] = [
        nil,
        CGRect(x: 180, y: 0, width: 40, height: 700),        // vertical, centred on 400 wide
        CGRect(x: 0, y: 330, width: 700, height: 40),        // horizontal
        CGRect(x: 5000, y: 5000, width: 40, height: 700),    // outside every screen
        CGRect(x: -100, y: -100, width: 300, height: 5000),  // overhangs, vertical
        CGRect(x: 300, y: 0, width: 40, height: 5000),       // overhangs bottom
        CGRect(x: 0, y: 0, width: 0, height: 0),
    ]

    @Test func degenerateInputsAlwaysYieldValidFrames() {
        for screen in Self.oddScreens {
            let bounds = CGRect(origin: .zero, size: screen).insetBy(dx: -0.01, dy: -0.01)
            for fold in Self.oddFolds {
                for posture in Posture.allCases {
                    for n in 1...6 {
                        let ids = (LayoutEngine.optionIDs(posture: posture, feedCount: n).map { Optional($0) }) + [nil, "bogus"]
                        for id in ids {
                            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                                             feedCount: n, optionID: id)
                            let tag = "\(posture) \(String(describing: id)) n=\(n) \(screen) \(String(describing: fold))"
                            #expect(frames.count == n, "\(tag)")
                            #expect(frames.first?.visible == true, "\(tag)")
                            for f in frames {
                                #expect(f.rect.width >= 0 && f.rect.height >= 0, "\(tag)")
                                #expect(bounds.contains(f.rect), "\(tag) \(f.rect)")
                                if !f.visible { #expect(f.rect == frames[0].rect, "\(tag)") }
                            }
                            // Multi-tile layouts never enter a usable fold, after any fallback.
                            if let fold, posture == .book || posture == .laptop, frames.filter(\.visible).count > 1 {
                                let clipped = fold.intersection(CGRect(origin: .zero, size: screen))
                                let usable = !clipped.isNull && clipped.width > 0 && clipped.height > 0
                                    && (posture == .book ? clipped.height > clipped.width : clipped.width > clipped.height)
                                if usable {
                                    for f in frames where f.visible { #expect(!f.rect.intersects(clipped), "\(tag)") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func feedCountEdges() {
        let screen = CGSize(width: 951, height: 669)
        #expect(LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .flat, feedCount: 0, optionID: nil).isEmpty)
        #expect(LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .flat, feedCount: -1, optionID: nil).isEmpty)
        let five = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .flat, feedCount: 5, optionID: nil)
        #expect(five.count == 5)
        #expect(five[4].visible == false && five[4].rect == five[0].rect)
        let zero = LayoutEngine.frames(screen: .zero, foldFrame: nil, posture: .flat, feedCount: 3, optionID: nil)
        #expect(zero.count == 3)
        #expect(zero.allSatisfy { !$0.visible && $0.rect == .zero })
    }

    @Test func nothingCrossesTheFoldOnNarrowScreens() {
        // Includes fallbacks: multi-tile layouts stay out of the fold; a lone fallback tile may not.
        for screen in [CGSize(width: 400, height: 700), CGSize(width: 700, height: 400), CGSize(width: 520, height: 900)] {
            for posture in [Posture.book, .laptop] {
                let fold = posture == .laptop
                    ? CGRect(x: 0, y: screen.height / 2 - 20, width: screen.width, height: 40)
                    : CGRect(x: screen.width / 2 - 20, y: 0, width: 40, height: screen.height)
                for n in 1...4 {
                    for id in LayoutEngine.optionIDs(posture: posture, feedCount: n) + [""] where id != "book.across" {
                        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                                         feedCount: n, optionID: id)
                        #expect(frames.count == n)
                        let visible = frames.filter(\.visible)
                        if visible.count > 1 {
                            for f in visible { #expect(!f.rect.intersects(fold), "\(posture) \(id) n=\(n) \(screen) \(f.rect)") }
                        }
                    }
                }
            }
        }
    }

    @Test func usableOptionIDsSkipsUnfittingOptions() {
        let screen = CGSize(width: 400, height: 700)
        let fold = CGRect(x: 180, y: 0, width: 40, height: 700)
        // Halves are 174 wide: no per-side option fits, only across does.
        #expect(LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: .book, feedCount: 4) == ["book.across"])
        #expect(LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: .book, feedCount: 1) == ["book.across"])
        // A roomy screen keeps everything.
        let (s, f) = Self.referenceGeometry(.book)
        #expect(LayoutEngine.usableOptionIDs(screen: s, foldFrame: f, posture: .book, feedCount: 2) == ["book.perScreen", "book.across"])
        // Never empty, even on a tiny screen.
        #expect(LayoutEngine.usableOptionIDs(screen: CGSize(width: 50, height: 50), foldFrame: nil, posture: .flat, feedCount: 4) == ["flat.mainBelow"])
        // Every usable option really lays out as itself with tiles of 200 pt or more.
        for id in LayoutEngine.usableOptionIDs(screen: s, foldFrame: f, posture: .book, feedCount: 4) {
            let fr = LayoutEngine.frames(screen: s, foldFrame: f, posture: .book, feedCount: 4, optionID: id)
            #expect(fr.filter(\.visible).allSatisfy { $0.rect.width >= 200 })
        }
    }

    @Test func bookOnePerScreenWithFourFeeds() {
        let (s, f) = Self.referenceGeometry(.book)
        let two = LayoutEngine.frames(screen: s, foldFrame: f, posture: .book, feedCount: 2, optionID: "book.perScreen")
        for n in [3, 4] {
            let frames = LayoutEngine.frames(screen: s, foldFrame: f, posture: .book, feedCount: n, optionID: "book.perScreen")
            #expect(frames.count == n)
            #expect(Array(frames.prefix(2)) == two, "n=\(n)")
            for hidden in frames.dropFirst(2) {
                #expect(hidden.visible == false && hidden.rect == frames[0].rect, "n=\(n)")
            }
        }
        #expect(LayoutEngine.optionIDs(posture: .book, feedCount: 3) == ["book.oneLeftTwoRight", "book.perScreen", "book.across"])
        #expect(LayoutEngine.optionIDs(posture: .book, feedCount: 4) == ["book.twoPerScreen", "book.perScreen", "book.across"])
        #expect(LayoutEngine.usableOptionIDs(screen: s, foldFrame: f, posture: .book, feedCount: 3) == ["book.oneLeftTwoRight", "book.perScreen", "book.across"])
        #expect(LayoutEngine.usableOptionIDs(screen: s, foldFrame: f, posture: .book, feedCount: 4) == ["book.twoPerScreen", "book.perScreen", "book.across"])
        // Defaults unchanged.
        #expect(LayoutEngine.frames(screen: s, foldFrame: f, posture: .book, feedCount: 4, optionID: nil).filter(\.visible).count == 4)
    }

    @Test func wrongOrientationOrOutsideFoldBehavesAsFlat() {
        let screen = CGSize(width: 951, height: 669)
        let horizontal = CGRect(x: 0, y: 314, width: 951, height: 40)
        let vertical = CGRect(x: 456, y: 0, width: 40, height: 669)
        let outside = CGRect(x: 4000, y: 0, width: 40, height: 669)
        for n in 1...4 {
            let flat = LayoutEngine.frames(screen: screen, foldFrame: nil, posture: .flat, feedCount: n, optionID: nil)
            #expect(LayoutEngine.frames(screen: screen, foldFrame: horizontal, posture: .book, feedCount: n, optionID: nil) == flat)
            #expect(LayoutEngine.frames(screen: screen, foldFrame: outside, posture: .book, feedCount: n, optionID: nil) == flat)
            #expect(LayoutEngine.frames(screen: screen, foldFrame: vertical, posture: .laptop, feedCount: n, optionID: nil) == flat)
            #expect(LayoutEngine.frames(screen: screen, foldFrame: vertical, posture: .unknown, feedCount: n, optionID: nil) == flat)
        }
    }

    @Test func narrowBookFallsBackToAcrossWithoutEnteringTheFold() {
        let screen = CGSize(width: 400, height: 700)
        let fold = CGRect(x: 180, y: 0, width: 40, height: 700)
        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book, feedCount: 4, optionID: nil)
        #expect(frames.count == 4)
        #expect(frames.filter(\.visible).count == 1)
        #expect(frames[0].rect.width >= 200)
    }

    // MARK: Data layouts (beta.3)

    static let dataIDs = ["flat.director", "book.dataScreen", "book.logbook", "book.rivals",
                         "laptop.raceEngineer", "laptop.scrubDeck"]

    static func regionRects(_ r: DataRegions) -> [CGRect] {
        [r.map, r.tower, r.console, r.deck, r.logbook, r.leftStrip, r.rightStrip].compactMap { $0 }
    }

    static func near(_ a: CGRect?, _ b: CGRect, _ tol: CGFloat = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol
            && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }

    static func usableFold(_ fold: CGRect?, posture: Posture, screen: CGSize) -> CGRect? {
        guard let fold, posture == .book || posture == .laptop else { return nil }
        let clipped = fold.intersection(CGRect(origin: .zero, size: screen))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0,
              posture == .book ? clipped.height > clipped.width : clipped.width > clipped.height
        else { return nil }
        return clipped
    }

    @Test func directorTowerColumnAndRow() {
        let (screen, fold) = Self.referenceGeometry(.flat)
        for n in 1...4 {
            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat,
                                             feedCount: n, optionID: "flat.director")
            let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .flat,
                                                   feedCount: n, optionID: "flat.director")
            // Full-height column, 200 wide, at the right edge inside the 6 pt margin.
            #expect(Self.near(regions.tower, CGRect(x: 745, y: 6, width: 200, height: 657)),
                    "n=\(n) \(String(describing: regions.tower))")
            #expect(regions.console == nil && regions.deck == nil)
            let visible = frames.filter(\.visible)
            #expect(visible.count == min(n, 3), "n=\(n)")
            let main = frames[0].rect
            // Main is as wide as the column left of the tower allows (733 = 951 - 2 * 6 - 6 - 200).
            #expect(abs(main.width - 733) < 0.01, "n=\(n) \(main)")
            #expect(abs(main.minY - 6) < 0.01 && abs(main.minX - 6) < 0.01, "n=\(n) \(main)")
            // The row: the other feeds and the map below the main feed, each at least 200 wide.
            for f in visible.dropFirst() {
                #expect(f.rect.width >= 200 - 0.01, "n=\(n) \(f.rect)")
                #expect(abs(f.rect.minY - (main.maxY + 6)) < 0.01, "n=\(n) \(f.rect)")
                #expect(f.rect.maxX <= 745 - 6 + 0.01, "n=\(n) \(f.rect)")
            }
            #expect(regions.map != nil, "n=\(n)")
            if let map = regions.map {
                #expect(map.width >= 200 - 0.01, "n=\(n) \(map)")
                #expect(abs(map.minY - (main.maxY + 6)) < 0.01, "n=\(n) \(map)")
                #expect(abs(map.maxY - 663) < 0.01 && abs(map.maxX - 739) < 0.01, "n=\(n) \(map)")
            }
        }
    }

    @Test func directorFourthFeedHidden() {
        let (screen, fold) = Self.referenceGeometry(.flat)
        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat,
                                         feedCount: 4, optionID: "flat.director")
        #expect(frames.count == 4)
        #expect(frames.prefix(3).allSatisfy { $0.visible })
        #expect(frames[3].visible == false && frames[3].rect == frames[0].rect)
        let three = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .flat,
                                        feedCount: 3, optionID: "flat.director")
        #expect(Array(frames.prefix(3)) == three)
    }

    @Test func dataScreenNothingInFold() {
        let (screen, fold) = Self.referenceGeometry(.book)
        for n in 1...4 {
            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book,
                                             feedCount: n, optionID: "book.dataScreen")
            let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .book,
                                                   feedCount: n, optionID: "book.dataScreen")
            let visible = frames.filter(\.visible)
            #expect(visible.count == n, "n=\(n)")
            // Feeds on the left screen, map and tower on the right; nothing in the fold.
            for f in visible {
                #expect(!f.rect.intersects(fold) && f.rect.maxX <= fold.minX - 6 + 0.01, "n=\(n) \(f.rect)")
            }
            #expect(regions.map != nil && regions.tower != nil, "n=\(n)")
            #expect(regions.console == nil && regions.deck == nil)
            for r in Self.regionRects(regions) {
                #expect(!r.intersects(fold) && r.minX >= fold.maxX + 6 - 0.01 && r.maxX <= 945 + 0.01, "n=\(n) \(r)")
            }
            if let map = regions.map, let tower = regions.tower {
                #expect(abs(map.minY - 6) < 0.01 && map.maxY < tower.minY, "n=\(n)")
                #expect(abs(tower.maxY - 663) < 0.01, "n=\(n) \(tower)")
            }
        }
        // Two feeds are stacked.
        let two = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book, feedCount: 2, optionID: "book.dataScreen")
        #expect(abs(two[0].rect.minX - two[1].rect.minX) < 0.01 && two[0].rect.maxY < two[1].rect.minY)
    }

    @Test func dataScreenFourFeedsGrid219() {
        let (screen, fold) = Self.referenceGeometry(.book)
        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book,
                                         feedCount: 4, optionID: "book.dataScreen")
        #expect(frames.count == 4 && frames.allSatisfy(\.visible))
        for f in frames { #expect(f.rect.width >= 210, "\(f.rect)") }
        // Two columns and two rows.
        #expect(Set(frames.map { ($0.rect.minX * 100).rounded() }).count == 2)
        #expect(Set(frames.map { ($0.rect.minY * 100).rounded() }).count == 2)
        let three = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book,
                                        feedCount: 3, optionID: "book.dataScreen")
        #expect(Array(frames.prefix(3)) == three)
    }

    @Test func laptopOneFeedDefaultsToScrubDeck() {
        let (screen, fold) = Self.referenceGeometry(.laptop)
        #expect(LayoutEngine.optionIDs(posture: .laptop, feedCount: 1, hasTiming: true)
                == ["laptop.scrubDeck", "laptop.raceEngineer"])
        #expect(LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: .laptop,
                                             feedCount: 1, hasTiming: true)
                == ["laptop.scrubDeck", "laptop.raceEngineer"])
        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .laptop,
                                         feedCount: 1, optionID: "laptop.scrubDeck")
        let mainUp = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .laptop,
                                         feedCount: 1, optionID: "laptop.mainUp")
        #expect(frames == mainUp)
        let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .laptop,
                                               feedCount: 1, optionID: "laptop.scrubDeck")
        #expect(regions == DataRegions(deck: CGRect(x: 6, y: 502, width: 657, height: 443)))
    }

    @Test func raceEngineerConsoleIsBottomHalf() {
        let (screen, fold) = Self.referenceGeometry(.laptop)
        let bottom = CGRect(x: 6, y: 502, width: 657, height: 443)
        for id in ["laptop.raceEngineer", "laptop.scrubDeck"] {
            for n in 1...4 {
                let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .laptop,
                                                 feedCount: n, optionID: id)
                let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .laptop,
                                                       feedCount: n, optionID: id)
                if id == "laptop.raceEngineer" {
                    #expect(regions == DataRegions(console: bottom), "n=\(n)")
                } else {
                    #expect(regions == DataRegions(deck: bottom), "n=\(n)")
                }
                // The main feed alone in the top half; the others hidden under it.
                #expect(frames.count == n)
                #expect(frames[0].visible && frames[0].rect.maxY <= fold.minY - 6 + 0.01, "n=\(n)")
                #expect(abs(frames[0].rect.width - 657) < 0.01, "n=\(n) \(frames[0].rect)")
                for f in frames.dropFirst() { #expect(!f.visible && f.rect == frames[0].rect, "n=\(n)") }
            }
        }
        #expect(LayoutEngine.optionIDs(posture: .laptop, feedCount: 2, hasTiming: true)
                == ["laptop.oneUpOneDown", "laptop.raceEngineer", "laptop.scrubDeck"])
    }

    @Test func noDataOptionsWithoutTiming() {
        for posture in Posture.allCases {
            for n in 0...6 {
                let plain = LayoutEngine.optionIDs(posture: posture, feedCount: n)
                #expect(plain == LayoutEngine.optionIDs(posture: posture, feedCount: n, hasTiming: false))
                #expect(plain.allSatisfy { !Self.dataIDs.contains($0) }, "\(posture) n=\(n)")
                let timed = LayoutEngine.optionIDs(posture: posture, feedCount: n, hasTiming: true)
                if posture == .laptop && min(max(n, 1), 4) == 1 {
                    #expect(timed == ["laptop.scrubDeck", "laptop.raceEngineer"])
                } else {
                    // Data options are appended after the existing ones.
                    #expect(Array(timed.prefix(plain.count)) == plain, "\(posture) n=\(n)")
                    let extra = Array(timed.dropFirst(plain.count))
                    switch posture {
                    case .closed: #expect(extra.isEmpty)
                    case .flat, .unknown: #expect(extra == ["flat.director"])
                    case .book:
                        #expect(extra == ["book.dataScreen", "book.logbook"] + (min(max(n, 1), 4) >= 2 ? ["book.rivals"] : []))
                    case .laptop: #expect(extra == ["laptop.raceEngineer", "laptop.scrubDeck"])
                    }
                }
                for p in [Posture.flat, .book, .laptop] {
                    let (screen, fold) = Self.referenceGeometry(p)
                    let usable = LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: posture, feedCount: n)
                    #expect(usable == LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: posture,
                                                                    feedCount: n, hasTiming: false))
                    #expect(usable.allSatisfy { !Self.dataIDs.contains($0) }, "\(posture) n=\(n)")
                }
            }
        }
        // On the reference screens every data option fits.
        let (s, f) = Self.referenceGeometry(.flat)
        #expect(LayoutEngine.usableOptionIDs(screen: s, foldFrame: f, posture: .flat, feedCount: 4, hasTiming: true)
                == ["flat.mainBelow", "flat.mainBesideBelow", "flat.grid", "flat.director"])
        let (bs, bf) = Self.referenceGeometry(.book)
        #expect(LayoutEngine.usableOptionIDs(screen: bs, foldFrame: bf, posture: .book, feedCount: 4, hasTiming: true)
                == ["book.twoPerScreen", "book.perScreen", "book.across", "book.dataScreen", "book.logbook", "book.rivals"])
        let (ls, lf) = Self.referenceGeometry(.laptop)
        #expect(LayoutEngine.usableOptionIDs(screen: ls, foldFrame: lf, posture: .laptop, feedCount: 3, hasTiming: true)
                == ["laptop.twoStacked", "laptop.twoSideBySide", "laptop.raceEngineer", "laptop.scrubDeck"])
    }

    @Test func dataRegionsNeverOverlapTiles() {
        let screens = Self.screens + Self.oddScreens + [CGSize(width: 520, height: 900)]
        for screen in screens {
            let bounds = CGRect(origin: .zero, size: screen).insetBy(dx: -0.01, dy: -0.01)
            let folds = Self.oddFolds + [Self.fold(for: .book, screen: screen), Self.fold(for: .laptop, screen: screen)]
            for fold in folds {
                for posture in Posture.allCases {
                    let usable = Self.usableFold(fold, posture: posture, screen: screen)
                    for n in 1...6 {
                        let ids = Self.dataIDs + LayoutEngine.optionIDs(posture: posture, feedCount: n, hasTiming: true) + ["bogus"]
                        for id in ids {
                            let tag = "\(posture) \(id) n=\(n) \(screen) \(String(describing: fold))"
                            let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                                             feedCount: n, optionID: id)
                            let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: posture,
                                                                   feedCount: n, optionID: id)
                            let rects = Self.regionRects(regions)
                            #expect(frames.count == n, "\(tag)")
                            #expect(frames.first?.visible == true, "\(tag)")
                            if !Self.dataIDs.contains(id) { #expect(rects.isEmpty, "\(tag)") }
                            for (i, r) in rects.enumerated() {
                                #expect(bounds.contains(r), "\(tag) \(r)")
                                #expect(r.width >= 200 - 0.01 && r.height > 0, "\(tag) \(r)")
                                for f in frames where f.visible { #expect(!r.intersects(f.rect), "\(tag) \(r) \(f.rect)") }
                                for other in rects.dropFirst(i + 1) { #expect(!r.intersects(other), "\(tag) \(r) \(other)") }
                                if let usable { #expect(!r.intersects(usable), "\(tag) \(r)") }
                            }
                            // A data layout keeps its feed tiles out of the fold too.
                            if !rects.isEmpty, let usable {
                                for f in frames where f.visible { #expect(!f.rect.intersects(usable), "\(tag) \(f.rect)") }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func usableDataOptionsLayOutAsThemselves() {
        for screen in Self.screens {
            for posture in Posture.allCases {
                let fold = Self.fold(for: posture, screen: screen)
                for n in 1...4 {
                    let usable = LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: posture,
                                                              feedCount: n, hasTiming: true)
                    for id in usable where Self.dataIDs.contains(id) {
                        let tag = "\(posture) \(id) n=\(n) \(screen)"
                        let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: posture,
                                                         feedCount: n, optionID: id)
                        let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: posture,
                                                               feedCount: n, optionID: id)
                        #expect(!Self.regionRects(regions).isEmpty, "\(tag)")
                        // Tiles: 16:9, at least 200 wide, inside the 6 pt margins; regions likewise.
                        for f in frames where f.visible {
                            #expect(f.rect.width >= 200 - 0.01, "\(tag) \(f.rect)")
                            #expect(abs(f.rect.width * 9 / 16 - f.rect.height) < 0.5, "\(tag) \(f.rect)")
                        }
                        for r in frames.filter(\.visible).map(\.rect) + Self.regionRects(regions) {
                            #expect(r.minX >= 6 - 0.01 && r.minY >= 6 - 0.01, "\(tag) \(r)")
                            #expect(r.maxX <= screen.width - 6 + 0.01 && r.maxY <= screen.height - 6 + 0.01, "\(tag) \(r)")
                        }
                    }
                }
            }
        }
        // Every data option fits the reference screens with every feed count.
        for (posture, ids) in [(Posture.flat, ["flat.director"]), (.book, ["book.dataScreen", "book.logbook"]),
                               (.laptop, ["laptop.raceEngineer", "laptop.scrubDeck"])] {
            let (screen, fold) = Self.referenceGeometry(posture)
            for n in 1...4 {
                let usable = LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: posture,
                                                          feedCount: n, hasTiming: true)
                for id in ids { #expect(usable.contains(id), "\(id) n=\(n)") }
            }
        }
    }

    @Test func dataOptionFallsBackWithoutRegions() {
        // A data option that doesn't fit falls back like any other, and then has no data regions.
        let narrow = CGSize(width: 400, height: 700)
        #expect(LayoutEngine.dataRegions(screen: narrow, foldFrame: nil, posture: .flat, feedCount: 4,
                                         optionID: "flat.director") == DataRegions())
        #expect(!LayoutEngine.usableOptionIDs(screen: narrow, foldFrame: nil, posture: .flat, feedCount: 4, hasTiming: true)
            .contains("flat.director"))
        // An id for another posture means the default, as any unknown id does.
        let (s, f) = Self.referenceGeometry(.flat)
        #expect(LayoutEngine.frames(screen: s, foldFrame: f, posture: .flat, feedCount: 3, optionID: "laptop.scrubDeck")
                == LayoutEngine.frames(screen: s, foldFrame: f, posture: .flat, feedCount: 3, optionID: nil))
        #expect(LayoutEngine.dataRegions(screen: s, foldFrame: f, posture: .flat, feedCount: 3,
                                         optionID: "laptop.scrubDeck") == DataRegions())
        // No feeds or no screen: no regions.
        #expect(LayoutEngine.dataRegions(screen: s, foldFrame: f, posture: .flat, feedCount: 0,
                                         optionID: "flat.director") == DataRegions())
        #expect(LayoutEngine.dataRegions(screen: .zero, foldFrame: f, posture: .flat, feedCount: 2,
                                         optionID: "flat.director") == DataRegions())
        // Five feeds lay out as four.
        #expect(LayoutEngine.dataRegions(screen: s, foldFrame: f, posture: .flat, feedCount: 5, optionID: "flat.director")
                == LayoutEngine.dataRegions(screen: s, foldFrame: f, posture: .flat, feedCount: 4, optionID: "flat.director"))
    }

    // MARK: Onboard and Logbook, and Rivals

    static func bookFrames(_ n: Int, _ id: String, screen: CGSize? = nil)
        -> (frames: [TileFrame], regions: DataRegions, screen: CGSize, fold: CGRect) {
        let (refScreen, refFold) = Self.referenceGeometry(.book)
        let screen = screen ?? refScreen
        let fold = screen == refScreen ? refFold : Self.fold(for: .book, screen: screen)
        return (LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book, feedCount: n, optionID: id),
                LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .book, feedCount: n, optionID: id),
                screen, fold)
    }

    @Test func logbookRightScreen() {
        for n in 1...5 {
            let (frames, regions, _, fold) = Self.bookFrames(n, "book.logbook")
            #expect(frames.count == n)
            #expect(frames[0].visible)
            #expect(frames.dropFirst().allSatisfy { !$0.visible && $0.rect == frames[0].rect }, "n=\(n)")
            // Left screen (x 6...450): the largest 16:9, vertically centred.
            let t = frames[0].rect
            let height: CGFloat = 444.0 * 9.0 / 16.0
            #expect(Self.near(t, CGRect(x: 6.0, y: 6.0 + (657.0 - height) / 2.0, width: 444.0, height: height)), "\(t)")
            // The logbook is the whole right screen inside the margins.
            #expect(Self.near(regions.logbook, CGRect(x: fold.maxX + 6, y: 6, width: 951 - 6 - (fold.maxX + 6), height: 657)),
                    "\(String(describing: regions.logbook))")
            #expect(regions.map == nil && regions.tower == nil && regions.leftStrip == nil && regions.rightStrip == nil)
        }
    }

    @Test func rivalsTwoTilesTwoStrips() {
        for n in 2...5 {
            let (frames, regions, _, fold) = Self.bookFrames(n, "book.rivals")
            #expect(frames.count == n)
            #expect(frames[0].visible && frames[1].visible)
            #expect(frames.dropFirst(2).allSatisfy { !$0.visible && $0.rect == frames[0].rect }, "n=\(n)")
            let (a, b) = (frames[0].rect, frames[1].rect)
            #expect(a.maxX <= fold.minX - 6 + 0.01 && b.minX >= fold.maxX + 6 - 0.01)
            // Reference screen: 444 and 443 wide, 657 tall; width-limited tile 444 x 249.75, strip takes the rest.
            #expect(abs(a.width - 444) < 0.01 && abs(b.width - 443) < 0.01, "\(a) \(b)")
            guard let ls = regions.leftStrip, let rs = regions.rightStrip else { Issue.record("strips missing"); return }
            for (tile, strip) in [(a, ls), (b, rs)] {
                #expect(abs(tile.height - tile.width * 9 / 16) < 0.01)
                #expect(abs(strip.minY - (tile.maxY + 6)) < 0.01, "gap")
                #expect(abs(strip.maxY - (657 + 6)) < 0.01, "strip fills the rest")
                #expect(strip.height >= 64 - 0.01)
                #expect(strip.width >= 200 && abs(strip.minX - tile.minX) < 0.01)
            }
            #expect(regions.logbook == nil && regions.map == nil)
        }
        // A short screen: the strip is 64 pt and the tile is height-limited.
        let short = CGSize(width: 951, height: 300)
        let (frames, regions, _, _) = Self.bookFrames(2, "book.rivals", screen: short)
        #expect(abs(frames[0].rect.height - (300 - 12 - 6 - 64)) < 0.01, "\(frames[0].rect)")
        #expect(abs((regions.leftStrip?.height ?? 0) - 64) < 0.01)
    }

    @Test func rivalsNeedsTwoFeeds() {
        #expect(!LayoutEngine.optionIDs(posture: .book, feedCount: 1, hasTiming: true).contains("book.rivals"))
        #expect(LayoutEngine.optionIDs(posture: .book, feedCount: 1, hasTiming: true).contains("book.logbook"))
        for n in 2...4 {
            let ids = LayoutEngine.optionIDs(posture: .book, feedCount: n, hasTiming: true)
            #expect(Array(ids.suffix(2)) == ["book.logbook", "book.rivals"], "n=\(n)")
        }
        // Asked for with one feed it is not built: no strips.
        let (_, regions, _, _) = Self.bookFrames(1, "book.rivals")
        #expect(regions == DataRegions())
    }

    @Test func nothingInFold() {
        for screen in Self.screens + Self.oddScreens {
            let fold = Self.fold(for: .book, screen: screen)
            guard let usable = Self.usableFold(fold, posture: .book, screen: screen) else { continue }
            for id in ["book.logbook", "book.rivals"] {
                for n in 1...4 {
                    // Only where the layout fits; otherwise another option stands in for it.
                    guard LayoutEngine.usableOptionIDs(screen: screen, foldFrame: fold, posture: .book,
                                                       feedCount: n, hasTiming: true).contains(id) else { continue }
                    let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book, feedCount: n, optionID: id)
                    let regions = LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .book, feedCount: n, optionID: id)
                    let tag = "\(id) n=\(n) \(screen)"
                    for r in Self.regionRects(regions) + frames.filter(\.visible).map(\.rect) {
                        #expect(!r.intersects(usable), "\(tag) \(r)")
                        #expect(r.minX >= 6 - 0.01 && r.minY >= 6 - 0.01, "\(tag) \(r)")
                        #expect(r.maxX <= screen.width - 6 + 0.01 && r.maxY <= screen.height - 6 + 0.01, "\(tag) \(r)")
                    }
                }
            }
        }
    }

    @Test func regionsNeverOverlapTiles() {
        for screen in Self.screens + Self.oddScreens {
            let fold = Self.fold(for: .book, screen: screen)
            for id in ["book.logbook", "book.rivals"] {
                for n in 1...4 {
                    let frames = LayoutEngine.frames(screen: screen, foldFrame: fold, posture: .book, feedCount: n, optionID: id)
                    let rects = Self.regionRects(LayoutEngine.dataRegions(screen: screen, foldFrame: fold, posture: .book,
                                                                          feedCount: n, optionID: id))
                    let tag = "\(id) n=\(n) \(screen)"
                    for (i, r) in rects.enumerated() {
                        #expect(r.width >= 200 - 0.01 && r.height > 0, "\(tag) \(r)")
                        for f in frames where f.visible { #expect(!r.intersects(f.rect), "\(tag) \(r) \(f.rect)") }
                        for o in rects.dropFirst(i + 1) { #expect(!r.intersects(o), "\(tag)") }
                    }
                }
            }
        }
    }

    @Test func plainListsUnchanged() {
        let today: [Posture: [Int: [String]]] = [
            .book: [1: ["book.across", "book.oneSide"], 2: ["book.perScreen", "book.across"],
                    3: ["book.oneLeftTwoRight", "book.perScreen", "book.across"],
                    4: ["book.twoPerScreen", "book.perScreen", "book.across"]],
            .flat: [1: ["flat.full"], 2: ["flat.mainBelow", "flat.twoStacked"],
                    3: ["flat.mainBelow", "flat.pyramid"], 4: ["flat.mainBelow", "flat.mainBesideBelow", "flat.grid"]],
            .laptop: [1: ["laptop.mainUp"], 2: ["laptop.oneUpOneDown"],
                      3: ["laptop.twoStacked", "laptop.twoSideBySide"], 4: ["laptop.pyramid"]],
        ]
        for (posture, byCount) in today {
            for (n, ids) in byCount {
                #expect(LayoutEngine.optionIDs(posture: posture, feedCount: n) == ids, "\(posture) n=\(n)")
                #expect(LayoutEngine.optionIDs(posture: posture, feedCount: n, hasTiming: false) == ids)
            }
        }
        #expect(LayoutEngine.optionIDs(posture: .closed, feedCount: 3) == ["closed.stack"])
        // Unknown posture lists as flat.
        #expect(LayoutEngine.optionIDs(posture: .unknown, feedCount: 2) == ["flat.mainBelow", "flat.twoStacked"])
    }
}
