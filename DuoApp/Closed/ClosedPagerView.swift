import Multiview
import SwiftUI

/// The closed phone's pages, over the multiview's closed layout: Picture (the layout itself, its
/// tiles and horizontal swipe unchanged), Radio Scanner and Gap Thermometer. Up and down move
/// between them (dots on the right edge, which also take a tap); left and right are each page's
/// own (the feed, the driver, the pair). The event card shows at the top of every page.
///
/// The feeds keep playing, with sound, on every page: the Radio and Gap pages cover the tiles
/// (opaque, over them), they never hide or stop them, so no player or video layer changes.
///
/// Drawn in the multiview's full-screen space; `bounds` is the safe area there, which the pages'
/// content keeps to. Sizes come from it, and the type scales with its height.
struct ClosedPagerView: View {
    let companion: CompanionController
    let radio: RadioController
    let timing: TimingController
    let settings: CompanionSettings
    let page: ClosedPage
    /// The Duo itself is closed (not a narrow phone): the card says "Unfold to see".
    let foldable: Bool
    /// The first time: "Swipe up or down for Picture, Radio and Gap".
    let showsHint: Bool
    let bounds: CGRect
    let onPage: @MainActor (ClosedPage) -> Void
    let onPageSwipe: @MainActor (CompanionModels.Swipe) -> Void
    /// A tap on a page's background: the controls, as on the black around the tiles.
    let onBackground: @MainActor () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .picture:
                Color.clear.allowsHitTesting(false)
            case .radio:
                cover {
                    RadioScannerView(radio: radio, timing: timing, settings: settings, size: bounds.size,
                                     onPageSwipe: onPageSwipe, onBackground: onBackground)
                }
            case .gap:
                cover {
                    GapThermometerView(timing: timing, companion: companion, settings: settings, size: bounds.size,
                                       onPageSwipe: onPageSwipe, onBackground: onBackground)
                }
            }
            PageDots(page: page, height: bounds.height, onPage: onPage)
                .position(x: bounds.maxX - 14, y: bounds.midY)
            if showsHint {
                Text(CompanionModels.pagerHint)
                    .font(.system(size: max(15, bounds.height * 0.024), weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .frame(width: max(bounds.width - 48, 0))
                    .position(x: bounds.midX, y: bounds.maxY - max(48, bounds.height * 0.1))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            EventCardsView(companion: companion, timing: timing, foldable: foldable, height: bounds.height)
                .frame(width: bounds.width)
                .offset(x: bounds.minX, y: bounds.minY + 8)
        }
        .animation(.snappy, value: companion.cards)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    /// A page over the tiles: the background to the screen's edges, the content in the safe area.
    private func cover<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            Theme.background
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content()
                .frame(width: bounds.width, height: bounds.height)
                .offset(x: bounds.minX, y: bounds.minY)
        }
        .transition(.opacity)
    }
}

/// Three dots on the right edge, the page's filled; each a button to that page.
private struct PageDots: View {
    let page: ClosedPage
    let height: CGFloat
    let onPage: @MainActor (ClosedPage) -> Void

    var body: some View {
        let dot = max(7, height * 0.012)
        VStack(spacing: dot * 1.4) {
            ForEach(ClosedPage.allCases, id: \.self) { each in
                Button {
                    onPage(each)
                } label: {
                    Circle()
                        .fill(each == page ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: dot, height: dot)
                        .frame(width: 22, height: dot * 2.4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.name(each))
                .accessibilityAddTraits(each == page ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(.vertical, 6)
        .videoGlass(in: Capsule())
    }

    static func name(_ page: ClosedPage) -> String {
        switch page {
        case .picture: return "Picture"
        case .radio: return CompanionModels.scannerTitle
        case .gap: return CompanionModels.gapTitle
        }
    }
}
