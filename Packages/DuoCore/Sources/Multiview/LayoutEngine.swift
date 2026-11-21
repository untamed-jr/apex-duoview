import Foundation
#if canImport(CoreGraphics)
// On Apple platforms CGRect's Equatable conformance lives in CoreGraphics; Foundation alone
// doesn't make it visible. On Linux Foundation defines the CG types itself.
import CoreGraphics
#endif

/// Device posture as the layout engine sees it (the app maps its own posture to this one).
public enum Posture: String, Codable, Sendable, CaseIterable {
    case closed, flat, book, laptop, unknown
}

public struct TileFrame: Equatable, Sendable {
    public var rect: CGRect
    public var visible: Bool

    public init(rect: CGRect, visible: Bool = true) {
        self.rect = rect
        self.visible = visible
    }
}

/// Where a data layout puts its panels, in the same space as the tile frames. A panel the layout
/// doesn't have is nil; every other layout has none.
public struct DataRegions: Equatable, Sendable {
    public var map: CGRect?
    public var tower: CGRect?
    /// Race Engineer's console.
    public var console: CGRect?
    /// Scrub Deck's event strip and lap chart.
    public var deck: CGRect?
    /// Onboard and Logbook's logbook: the whole right screen.
    public var logbook: CGRect?
    /// Rivals' strips, each under its screen's tile.
    public var leftStrip: CGRect?
    public var rightStrip: CGRect?

    public init(map: CGRect? = nil, tower: CGRect? = nil, console: CGRect? = nil, deck: CGRect? = nil,
                logbook: CGRect? = nil, leftStrip: CGRect? = nil, rightStrip: CGRect? = nil) {
        self.map = map
        self.tower = tower
        self.console = console
        self.deck = deck
        self.logbook = logbook
        self.leftStrip = leftStrip
        self.rightStrip = rightStrip
    }

    var rects: [CGRect] { [map, tower, console, deck, logbook, leftStrip, rightStrip].compactMap { $0 } }
}

/// Pure layout engine: 16:9 tiles that use as much of the screen as possible.
/// Geometry is a port of the shapes chosen by `spike/layout_search.py`.
public enum LayoutEngine {
    static let margin: CGFloat = 6
    static let gap: CGFloat = 6
    static let minWidth: CGFloat = 200
    static let aspect: CGFloat = 9.0 / 16.0
    /// Rivals' strip: at least this tall.
    static let minStripHeight: CGFloat = 64

    // MARK: Options

    /// The options without timing data (`hasTiming: false`).
    public static func optionIDs(posture: Posture, feedCount: Int) -> [String] {
        optionIDs(posture: posture, feedCount: feedCount, hasTiming: false)
    }

    /// The posture's options, default first. With timing data the data layouts follow the
    /// others; laptop with one feed then offers only Scrub Deck (the default) and Race Engineer.
    public static func optionIDs(posture: Posture, feedCount: Int, hasTiming: Bool) -> [String] {
        let plain = plainOptionIDs(posture: posture, feedCount: feedCount)
        guard hasTiming else { return plain }
        switch posture {
        case .closed: return plain
        case .flat, .unknown: return plain + ["flat.director"]
        case .book:
            // Rivals needs two feeds, one per screen.
            return plain + ["book.dataScreen", "book.logbook"] + (min(max(feedCount, 1), 4) >= 2 ? ["book.rivals"] : [])
        case .laptop:
            if min(max(feedCount, 1), 4) == 1 { return ["laptop.scrubDeck", "laptop.raceEngineer"] }
            return plain + ["laptop.raceEngineer", "laptop.scrubDeck"]
        }
    }

    private static func plainOptionIDs(posture: Posture, feedCount: Int) -> [String] {
        let n = min(max(feedCount, 1), 4)
        switch posture {
        case .closed:
            // Two or more feeds: two of them stacked, full width (owner, 2026-11-18).
            return n >= 2 ? ["closed.stack"] : ["closed.main"]
        case .flat, .unknown:
            switch n {
            case 1: return ["flat.full"]
            case 2: return ["flat.mainBelow", "flat.twoStacked"]
            case 3: return ["flat.mainBelow", "flat.pyramid"]
            default: return ["flat.mainBelow", "flat.mainBesideBelow", "flat.grid"]
            }
        case .book:
            switch n {
            case 1: return ["book.across", "book.oneSide"]
            case 2: return ["book.perScreen", "book.across"]
            // "One per screen" with 3 or 4 feeds: the first two show, the rest play out of sight
            // (owner, 2026-11-13).
            case 3: return ["book.oneLeftTwoRight", "book.perScreen", "book.across"]
            default: return ["book.twoPerScreen", "book.perScreen", "book.across"]
            }
        case .laptop:
            switch n {
            case 1: return ["laptop.mainUp"]
            case 2: return ["laptop.oneUpOneDown"]
            case 3: return ["laptop.twoStacked", "laptop.twoSideBySide"]
            default: return ["laptop.pyramid"]
            }
        }
    }

    // MARK: Frames

    /// Exactly `feedCount` frames (none for `feedCount <= 0`); index 0 is the main tile. For
    /// `feedCount > 4` the extra tiles are hidden and take the main tile's rect. A zero or negative
    /// screen yields hidden zero rects. An unknown or nil `optionID` means the default of the
    /// options without timing (`optionIDs(posture:feedCount:)`), even where timing is in and
    /// `optionIDs(…, hasTiming: true)` lists a data layout first (laptop with one feed: Scrub
    /// Deck): to get a data layout, pass its id (the app always passes one). An option that does
    /// not fit this screen falls back as described in `compute`.
    public static func frames(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                              feedCount: Int, optionID: String?) -> [TileFrame] {
        guard feedCount > 0 else { return [] }
        guard screen.width > 0, screen.height > 0 else {
            return Array(repeating: TileFrame(rect: .zero, visible: false), count: feedCount)
        }
        let n = min(feedCount, 4)
        var result = compute(screen: screen, foldFrame: foldFrame, posture: posture, n: n, optionID: optionID).tiles
        while result.count < feedCount, let main = result.first {
            result.append(TileFrame(rect: main.rect, visible: false))
        }
        return result
    }

    /// The data panels of the layout `frames` gives for the same arguments: empty unless that is a
    /// data layout (after any fallback), and for no feeds or an empty screen. Regions keep the 6 pt
    /// margins and gaps, are at least 200 pt wide, never overlap a visible tile or each other, and
    /// stay out of the fold.
    public static func dataRegions(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                                   feedCount: Int, optionID: String) -> DataRegions {
        guard feedCount > 0, screen.width > 0, screen.height > 0 else { return DataRegions() }
        return compute(screen: screen, foldFrame: foldFrame, posture: posture,
                       n: min(feedCount, 4), optionID: optionID).regions
    }

    /// The options without timing data (`hasTiming: false`) that fit.
    public static func usableOptionIDs(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                                       feedCount: Int) -> [String] {
        usableOptionIDs(screen: screen, foldFrame: foldFrame, posture: posture, feedCount: feedCount, hasTiming: false)
    }

    /// The options that fit this screen and fold (every visible tile and data region at least
    /// 200 pt wide), in `optionIDs` order of the posture the layout really uses (book or laptop
    /// without a usable fold lay out as flat). Never empty: if nothing fits, the first option.
    public static func usableOptionIDs(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                                       feedCount: Int, hasTiming: Bool) -> [String] {
        let n = min(max(feedCount, 1), 4)
        if posture == .closed { return optionIDs(posture: .closed, feedCount: n, hasTiming: hasTiming) }
        let (effective, fold) = resolve(screen: screen, foldFrame: foldFrame, posture: posture)
        let all = optionIDs(posture: effective, feedCount: n, hasTiming: hasTiming)
        guard screen.width > 0, screen.height > 0 else { return [all[0]] }
        let ok = all.filter { id in
            build(id: id, screen: screen, fold: fold, n: n).map { fits($0, screen: screen) } ?? false
        }
        return ok.isEmpty ? [all[0]] : ok
    }

    /// The laptop lower region (below the fold region), clamped to the screen inset by the margin.
    public static func reservedArea(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                                    feedCount: Int) -> CGRect? {
        guard posture == .laptop, feedCount == 1, screen.width > 0, screen.height > 0 else { return nil }
        let (effective, fold) = resolve(screen: screen, foldFrame: foldFrame, posture: posture)
        guard effective == .laptop, let f = fold else { return nil }
        let whole = CGRect(x: margin, y: margin, width: screen.width - 2 * margin, height: screen.height - 2 * margin)
        let top = f.maxY + gap
        let clamped = CGRect(x: whole.minX, y: top, width: whole.width, height: whole.maxY - top)
            .intersection(whole)
        return clamped.isNull || clamped.width <= 0 || clamped.height <= 0 ? nil : clamped
    }

    public static func screenUse(_ frames: [TileFrame], screen: CGSize) -> Double {
        let total = Double(screen.width * screen.height)
        guard total > 0 else { return 0 }
        let used = frames.filter(\.visible).reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        return used / total
    }

    // MARK: Resolution and fallbacks

    /// Effective posture and sanitised fold: the fold is clipped to the screen; one that misses the
    /// screen or has the wrong orientation for the posture (book needs taller than wide, laptop
    /// wider than tall) counts as nil, and book/laptop then lay out as flat.
    private static func resolve(screen: CGSize, foldFrame: CGRect?, posture: Posture) -> (Posture, CGRect?) {
        let effective: Posture = (posture == .unknown) ? .flat : posture
        guard effective == .book || effective == .laptop, let raw = foldFrame else { return (.flat, nil) }
        let f = raw.intersection(CGRect(origin: .zero, size: screen))
        guard !f.isNull, f.width > 0, f.height > 0 else { return (.flat, nil) }
        if effective == .book && !(f.height > f.width) { return (.flat, nil) }
        if effective == .laptop && !(f.width > f.height) { return (.flat, nil) }
        return (effective, f)
    }

    private static func fits(_ layout: Layout, screen: CGSize) -> Bool {
        let bounds = CGRect(origin: .zero, size: screen).insetBy(dx: -0.01, dy: -0.01)
        return layout.tiles.filter(\.visible).map(\.rect).allSatisfy {
            $0.width >= minWidth - 0.01 && bounds.contains($0)
        } && layout.regions.rects.allSatisfy {
            $0.width >= minWidth - 0.01 && $0.height > 0 && bounds.contains($0)
        }
    }

    /// The options a chosen id is looked up and falls back among: the posture's list with timing
    /// when the id is one of its data options, otherwise the list without, so that nil or an
    /// unknown id still means the usual default.
    private static func candidates(posture: Posture, n: Int, optionID: String?) -> [String] {
        let plain = optionIDs(posture: posture, feedCount: n)
        guard let id = optionID, !plain.contains(id) else { return plain }
        let timed = optionIDs(posture: posture, feedCount: n, hasTiming: true)
        return timed.contains(id) ? timed : plain
    }

    /// Preferred option first, then the posture's other options in order; if none fits, a single
    /// main tile (the 200 pt minimum is relaxed only for it) with the rest hidden.
    private static func compute(screen: CGSize, foldFrame: CGRect?, posture: Posture,
                                n: Int, optionID: String?) -> Layout {
        if posture == .closed {
            // "closed.main" asked by name keeps one tile; anything else is the count's default.
            if n >= 2, optionID != "closed.main" { return Layout(tiles: closedStack(screen: screen, n: n)) }
            return Layout(tiles: closed(screen: screen, n: n))
        }
        let (effective, fold) = resolve(screen: screen, foldFrame: foldFrame, posture: posture)
        let options = candidates(posture: effective, n: n, optionID: optionID)
        let chosen = optionID.flatMap { options.contains($0) ? $0 : nil } ?? options[0]
        for id in [chosen] + options.filter({ $0 != chosen }) {
            if let l = build(id: id, screen: screen, fold: fold, n: n), fits(l, screen: screen) { return l }
        }
        // Last resort.
        let whole = wholeRegion(screen) ?? Region(x: 0, y: 0, w: screen.width, h: screen.height)
        var region = whole
        if effective == .laptop, let f = fold, let (top, _) = halves(whole, f), top.w >= minWidth { region = top }
        let main = one(region)
        return Layout(tiles: (0..<n).map { TileFrame(rect: main, visible: $0 == 0) })
    }

    private static func closed(screen: CGSize, n: Int) -> [TileFrame] {
        let main = one(Region(x: 0, y: 0, w: screen.width, h: screen.height))
        return (0..<n).map { TileFrame(rect: main, visible: $0 == 0) }
    }

    /// The closed phone's Picture page with two or more feeds: the main feed and the next one,
    /// each the full width (no side margin, as the one closed tile), the main one on top, one gap
    /// between them, the pair centred in the height. On a screen too short for two full-width
    /// tiles both shrink to fit it. The other feeds are hidden under the main tile.
    private static func closedStack(screen: CGSize, n: Int) -> [TileFrame] {
        let s = fit(screen.width, max((screen.height - gap) / 2, 0))
        let x = (screen.width - s.width) / 2
        let y = (screen.height - (2 * s.height + gap)) / 2
        let pair = [tile(x, y, s.width), tile(x, y + s.height + gap, s.width)]
        return (0..<n).map { $0 < 2 ? TileFrame(rect: pair[$0]) : TileFrame(rect: pair[0], visible: false) }
    }

    // MARK: Shapes

    struct Region {
        var x, y, w, h: CGFloat
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    /// One option's tiles (exactly n) and its data panels.
    struct Layout {
        var tiles: [TileFrame]
        var regions = DataRegions()
    }

    private static func fit(_ w: CGFloat, _ h: CGFloat) -> CGSize {
        let width = min(w, h / aspect)
        return CGSize(width: width, height: width * aspect)
    }

    private static func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: w * aspect)
    }

    private static func one(_ r: Region) -> CGRect {
        let s = fit(r.w, r.h)
        return tile(r.x + (r.w - s.width) / 2, r.y + (r.h - s.height) / 2, s.width)
    }

    /// Column of `m` equal tiles, centred in the region.
    private static func column(_ r: Region, _ m: Int) -> [CGRect] {
        let s = fit(r.w, (r.h - gap * CGFloat(m - 1)) / CGFloat(m))
        let total = CGFloat(m) * s.height + gap * CGFloat(m - 1)
        return (0..<m).map { i in
            tile(r.x + (r.w - s.width) / 2, r.y + (r.h - total) / 2 + CGFloat(i) * (s.height + gap), s.width)
        }
    }

    /// Row of `m` equal tiles, centred in the region.
    private static func row(_ r: Region, _ m: Int) -> [CGRect] {
        let s = fit((r.w - gap * CGFloat(m - 1)) / CGFloat(m), r.h)
        let total = CGFloat(m) * s.width + gap * CGFloat(m - 1)
        return (0..<m).map { i in
            tile(r.x + (r.w - total) / 2 + CGFloat(i) * (s.width + gap), r.y + (r.h - s.height) / 2, s.width)
        }
    }

    /// 2 x 2 cells centred in the region.
    private static func gridCells(_ r: Region) -> (cells: [CGRect], cell: CGSize, bottomY: CGFloat) {
        let s = fit((r.w - gap) / 2, (r.h - gap) / 2)
        let x0 = r.x + (r.w - (2 * s.width + gap)) / 2
        let y0 = r.y + (r.h - (2 * s.height + gap)) / 2
        let cells = [tile(x0, y0, s.width), tile(x0 + s.width + gap, y0, s.width),
                     tile(x0, y0 + s.height + gap, s.width), tile(x0 + s.width + gap, y0 + s.height + gap, s.width)]
        return (cells, s, y0 + s.height + gap)
    }

    private static func pyramid(_ r: Region) -> [CGRect] {
        let g = gridCells(r)
        return [g.cells[0], g.cells[1], tile(r.x + (r.w - g.cell.width) / 2, g.bottomY, g.cell.width)]
    }

    /// Main tile (as large as fits) with the other `m - 1` tiles in a row below, sweeping the main width.
    private static func mainBelow(_ r: Region, _ m: Int) -> [CGRect]? {
        let k = m - 1
        var best: (area: CGFloat, rects: [CGRect])?
        for i in 1...400 {
            let mw = r.w * CGFloat(i) / 400
            let mh = mw * aspect
            if mh > r.h { break }
            let rh = r.h - mh - gap
            guard rh > 0 else { continue }
            let s = fit((r.w - gap * CGFloat(k - 1)) / CGFloat(k), rh)
            guard s.width >= minWidth - 0.01, mw >= minWidth - 0.01 else { continue }
            let total = CGFloat(k) * s.width + gap * CGFloat(k - 1)
            let y0 = r.y + (r.h - (mh + gap + s.height)) / 2
            var rs = [tile(r.x + (r.w - mw) / 2, y0, mw)]
            for j in 0..<k { rs.append(tile(r.x + (r.w - total) / 2 + CGFloat(j) * (s.width + gap), y0 + mh + gap, s.width)) }
            let a = rs.reduce(0) { $0 + $1.width * $1.height }
            if best == nil || a > best!.area { best = (a, rs) }
        }
        return best?.rects
    }

    /// 4 feeds: main top-left, one tile beside it, two below; sweeping the main width.
    private static func mainBesideBelow(_ r: Region) -> [CGRect]? {
        var best: (area: CGFloat, rects: [CGRect])?
        for i in 1...400 {
            let mw = r.w * CGFloat(i) / 400
            let mh = mw * aspect
            if mh > r.h { break }
            let rw = r.w - mw - gap
            let rh = r.h - mh - gap
            guard rw > 0, rh > 0 else { continue }
            let beside = fit(rw, mh)
            let below = fit((r.w - gap) / 2, rh)
            guard beside.width >= minWidth - 0.01, below.width >= minWidth - 0.01,
                  mw >= minWidth - 0.01 else { continue }
            let y0 = r.y + (r.h - (mh + gap + below.height)) / 2
            let rs = [tile(r.x, y0, mw), tile(r.x + mw + gap, y0, beside.width),
                      tile(r.x, y0 + mh + gap, below.width), tile(r.x + below.width + gap, y0 + mh + gap, below.width)]
            let a = rs.reduce(0) { $0 + $1.width * $1.height }
            if best == nil || a > best!.area { best = (a, rs) }
        }
        return best?.rects
    }

    // MARK: Data shapes

    /// Director's Desk: the tower a full-height column, 200 pt wide, on the right; the main feed
    /// as large as fits left of it with room for a row below; the row is up to two more feeds and
    /// the map in equal slots, each at least 200 pt wide. The feeds sit at the top of their slots
    /// and the map takes its slot's full height. A fourth feed is hidden under the main tile.
    private static func director(_ r: Region, _ n: Int) -> Layout? {
        let towerWidth = minWidth
        let left = r.w - towerWidth - gap
        let k = min(n - 1, 2)
        let slot = (left - gap * CGFloat(k)) / CGFloat(k + 1)
        // The row is at least as tall as a 200 pt tile.
        let mw = min(left, (r.h - gap - minWidth * aspect) / aspect)
        guard slot >= minWidth - 0.01, mw >= minWidth - 0.01 else { return nil }
        let rowY = r.y + mw * aspect + gap
        let rowH = r.y + r.h - rowY
        let feed = fit(slot, rowH)
        var tiles = [TileFrame(rect: tile(r.x + (left - mw) / 2, r.y, mw))]
        for j in 0..<k {
            tiles.append(TileFrame(rect: tile(r.x + CGFloat(j) * (slot + gap) + (slot - feed.width) / 2, rowY, feed.width)))
        }
        while tiles.count < n { tiles.append(TileFrame(rect: tiles[0].rect, visible: false)) }
        let map = CGRect(x: r.x + CGFloat(k) * (slot + gap), y: rowY, width: slot, height: rowH)
        let tower = CGRect(x: r.x + r.w - towerWidth, y: r.y, width: towerWidth, height: r.h)
        return Layout(tiles: tiles, regions: DataRegions(map: map, tower: tower))
    }

    /// Book data screen: the feeds on the left screen (one alone, two stacked, three or four in a
    /// 2 x 2 grid); on the right screen the map on top, as tall as a 16:9 box of that width but at
    /// most half the height, and the tower below it.
    private static func dataScreen(_ l: Region, _ r: Region, _ n: Int) -> Layout? {
        let feeds: [CGRect]
        switch n {
        case 1: feeds = [one(l)]
        case 2: feeds = column(l, 2)
        default: feeds = Array(gridCells(l).cells.prefix(n))
        }
        let mapHeight = min(r.w * aspect, (r.h - gap) / 2)
        guard mapHeight > 0 else { return nil }
        let map = CGRect(x: r.x, y: r.y, width: r.w, height: mapHeight)
        let tower = CGRect(x: r.x, y: r.y + mapHeight + gap, width: r.w, height: r.h - mapHeight - gap)
        return Layout(tiles: feeds.map { TileFrame(rect: $0) }, regions: DataRegions(map: map, tower: tower))
    }

    /// Onboard and Logbook: the main feed on the left screen, the logbook the whole right screen;
    /// the other feeds are hidden under the main tile.
    private static func logbook(_ l: Region, _ r: Region, _ n: Int) -> Layout {
        let main = one(l)
        let tiles = (0..<n).map { TileFrame(rect: main, visible: $0 == 0) }
        return Layout(tiles: tiles, regions: DataRegions(logbook: r.rect))
    }

    /// Rivals: feeds 0 and 1, one per screen, each the largest 16:9 tile that leaves a strip of at
    /// least 64 pt below it. The tile sits at the top of its screen; the strip takes the rest of
    /// the height under it and the tile's width. The other feeds are hidden under the first tile.
    private static func rivals(_ l: Region, _ r: Region, _ n: Int) -> Layout? {
        guard n >= 2 else { return nil }
        func pair(_ region: Region) -> (tile: CGRect, strip: CGRect)? {
            let available = region.h - gap - minStripHeight
            guard available > 0 else { return nil }
            let s = fit(region.w, available)
            let tile = tile(region.x + (region.w - s.width) / 2, region.y, s.width)
            let stripY = tile.maxY + gap
            return (tile, CGRect(x: tile.minX, y: stripY, width: tile.width, height: region.y + region.h - stripY))
        }
        guard let left = pair(l), let right = pair(r) else { return nil }
        let tiles = (0..<n).map { $0 < 2 ? TileFrame(rect: [left.tile, right.tile][$0]) : TileFrame(rect: left.tile, visible: false) }
        return Layout(tiles: tiles, regions: DataRegions(leftStrip: left.strip, rightStrip: right.strip))
    }

    /// Race Engineer and Scrub Deck: the main feed in the top half, the others hidden under it;
    /// the console or deck is the whole bottom half inside the margins.
    private static func laptopData(top: Region, bottom: Region, n: Int, console: Bool) -> Layout {
        let main = one(top)
        let tiles = (0..<n).map { TileFrame(rect: main, visible: $0 == 0) }
        return Layout(tiles: tiles, regions: console ? DataRegions(console: bottom.rect) : DataRegions(deck: bottom.rect))
    }

    // MARK: Option builder

    private static func wholeRegion(_ screen: CGSize) -> Region? {
        let r = Region(x: margin, y: margin, w: screen.width - 2 * margin, h: screen.height - 2 * margin)
        return r.w > 0 && r.h > 0 ? r : nil
    }

    private static func clamp(_ whole: Region, x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) -> Region? {
        let ax = max(x0, whole.x), ay = max(y0, whole.y)
        let bx = min(x1, whole.x + whole.w), by = min(y1, whole.y + whole.h)
        return bx - ax > 0 && by - ay > 0 ? Region(x: ax, y: ay, w: bx - ax, h: by - ay) : nil
    }

    /// Left and right regions around a vertical fold, each clamped to the inset screen.
    private static func sides(_ whole: Region, _ f: CGRect) -> (Region, Region)? {
        guard let l = clamp(whole, x0: whole.x, y0: whole.y, x1: f.minX - gap, y1: whole.y + whole.h),
              let r = clamp(whole, x0: f.maxX + gap, y0: whole.y, x1: whole.x + whole.w, y1: whole.y + whole.h)
        else { return nil }
        return (l, r)
    }

    /// Top and bottom regions around a horizontal fold, each clamped to the inset screen.
    private static func halves(_ whole: Region, _ f: CGRect) -> (Region, Region)? {
        guard let t = clamp(whole, x0: whole.x, y0: whole.y, x1: whole.x + whole.w, y1: f.minY - gap),
              let b = clamp(whole, x0: whole.x, y0: f.maxY + gap, x1: whole.x + whole.w, y1: whole.y + whole.h)
        else { return nil }
        return (t, b)
    }

    /// Frames (and data panels) for one option, or nil when its regions are empty or the id is not
    /// for this fold.
    private static func build(id: String, screen: CGSize, fold: CGRect?, n: Int) -> Layout? {
        guard let whole = wholeRegion(screen) else { return nil }
        func s() -> (Region, Region)? { fold.flatMap { sides(whole, $0) } }
        func h() -> (Region, Region)? { fold.flatMap { halves(whole, $0) } }

        let rects: [CGRect]?
        switch id {
        case "flat.full": rects = [one(whole)]
        case "flat.mainBelow": rects = mainBelow(whole, n)
        case "flat.twoStacked": rects = column(whole, 2)
        case "flat.pyramid": rects = pyramid(whole)
        case "flat.mainBesideBelow": rects = mainBesideBelow(whole)
        case "flat.grid": rects = gridCells(whole).cells
        case "flat.director": return director(whole, n)
        case "book.across":
            guard fold != nil else { return nil }
            let main = one(whole)
            return Layout(tiles: (0..<n).map { TileFrame(rect: main, visible: $0 == 0) })
        case "book.oneSide": rects = s().map { [one($0.0)] }
        case "book.perScreen":
            // Slots 0 and 1, one per screen; with 3 or 4 feeds the others are hidden under the main
            // tile, as in "across".
            guard n >= 2, let halves = s() else { return nil }
            let pair = [one(halves.0), one(halves.1)]
            return Layout(tiles: (0..<n).map { $0 < 2 ? TileFrame(rect: pair[$0]) : TileFrame(rect: pair[0], visible: false) })
        case "book.dataScreen": return s().flatMap { dataScreen($0.0, $0.1, n) }
        case "book.logbook": return s().map { logbook($0.0, $0.1, n) }
        case "book.rivals": return s().flatMap { rivals($0.0, $0.1, n) }
        case "laptop.raceEngineer", "laptop.scrubDeck":
            return h().map { laptopData(top: $0.0, bottom: $0.1, n: n, console: id == "laptop.raceEngineer") }
        case "book.oneLeftTwoRight": rects = s().map { [one($0.0)] + column($0.1, 2) }
        case "book.twoPerScreen": rects = s().map { column($0.0, 2) + column($0.1, 2) }
        case "laptop.mainUp": rects = h().map { [one($0.0)] }
        case "laptop.oneUpOneDown": rects = h().map { [one($0.0), one($0.1)] }
        case "laptop.twoStacked": rects = h().map { [one($0.0)] + column($0.1, 2) }
        case "laptop.twoSideBySide": rects = h().map { [one($0.0)] + row($0.1, 2) }
        case "laptop.pyramid": rects = h().map { [one($0.0)] + pyramid($0.1) }
        default: rects = nil
        }
        guard let rs = rects, rs.count == n else { return nil }
        return Layout(tiles: rs.map { TileFrame(rect: $0) })
    }
}
