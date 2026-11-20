import SwiftUI
import TipKit

/// First-time tips (owner, 2026-11-20: all five kept). Each shows once, where its feature is, and
/// closes with ✕. Settings › Help turns them off ("Show tips") or brings them back ("Reset tips",
/// from the next launch, because TipKit can only reset before it starts).
enum AppTips {
    /// UserDefaults: tips on (the default) or off.
    static let showKey = "showTips"
    /// UserDefaults: set by "Reset tips"; the next launch clears what TipKit remembers.
    static let resetKey = "resetTipsOnLaunch"

    /// Once, when the app starts.
    @MainActor
    static func configure() {
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// The first multiview with the phone open flat (multiview only attaches it while flat).
struct LaptopPoseTip: Tip {
    var title: Text { Text("Try laptop pose") }
    var message: Text? { Text("Fold the phone like a laptop for Race Engineer: video on top, the console below.") }
    var image: Image? { Image(systemName: "laptopcomputer") }
}

/// The first time the Map button shows.
struct TapCarTip: Tip {
    var title: Text { Text("Tap a car") }
    var message: Text? { Text("Tap a car on the map or the tower to put its onboard on screen.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// The first time the multiview controls fade out (on the small handle that stays).
struct ControlsHiddenTip: Tip {
    var title: Text { Text("Controls are hiding") }
    var message: Text? { Text("Tap the picture to bring them back.") }
    var image: Image? { Image(systemName: "hand.point.up") }
}

/// The first Scrub Deck. Defined now; attached with the Scrub Deck drag fix (beta 4 week).
struct ScrubDeckTip: Tip {
    var title: Text { Text("Drag to any lap") }
    var message: Text? { Text("Drag along the Scrub Deck to jump the video to that moment.") }
    var image: Image? { Image(systemName: "arrow.left.and.right") }
}

/// The first time the phone is closed during a video.
struct ClosedPhoneTip: Tip {
    var title: Text { Text("Closed, it keeps playing") }
    var message: Text? { Text("The outer screen keeps the video; open the phone to get the full view back.") }
    var image: Image? { Image(systemName: "iphone") }
}

extension View {
    /// A first-time tip on this control, unless tips are off in Settings. nil shows none.
    func appTip(_ tip: (any Tip)?, arrowEdge: Edge = .top) -> some View {
        modifier(AppTipModifier(tip: tip, arrowEdge: arrowEdge))
    }
}

private struct AppTipModifier: ViewModifier {
    let tip: (any Tip)?
    let arrowEdge: Edge
    @AppStorage(AppTips.showKey) private var show = true

    func body(content: Content) -> some View {
        content.popoverTip(show ? tip : nil, arrowEdge: arrowEdge)
    }
}

/// The closed-phone tip, inline at the bottom of the outer screen, unless tips are off.
struct ClosedPhoneTipView: View {
    @AppStorage(AppTips.showKey) private var show = true
    private let tip = ClosedPhoneTip()

    var body: some View {
        if show {
            TipView(tip)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }
}
