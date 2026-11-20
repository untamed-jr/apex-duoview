import SwiftUI
import UIKit

/// The welcome tour (owner, 2026-11-20: all five cards kept, first launch only, real screenshots).
/// Five swipeable cards after the opening screen, each one picture and one line, with Skip on every
/// card but the last. Settings › Help › "How to use" plays it again.
///
/// Layout follows the screen's shape: wide (open flat) puts the picture on the left half and the
/// words on the right, as the fold splits them; tall (laptop pose, closed) stacks them.
struct WelcomeTourView: View {
    /// Called when the tour is skipped or finished.
    let onDone: () -> Void

    @State private var page = 0

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()
                TabView(selection: $page) {
                    ForEach(WelcomeCard.all) { card in
                        cardView(card, wide: wide)
                            .tag(card.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Skip on the left, the page dots in the middle, Next on the right: one row at the bottom,
    /// clear of the closed screen's camera and status bar at the top right.
    private var bottomBar: some View {
        let last = page == WelcomeCard.all.count - 1
        return HStack(spacing: 12) {
            Button("Skip", action: onDone)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint("Closes the tour")
                .opacity(last ? 0 : 1)
                .disabled(last)
            Spacer(minLength: 8)
            PageDots(count: WelcomeCard.all.count, current: page)
            Spacer(minLength: 8)
            Button {
                if last {
                    onDone()
                } else {
                    withAnimation(.snappy) { page += 1 }
                }
            } label: {
                Text(WelcomeCard.all[page].button).padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func cardView(_ card: WelcomeCard, wide: Bool) -> some View {
        if wide {
            HStack(spacing: 0) {
                TourPicture(card: card)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                words(card)
                    .padding(.horizontal, 40)
                    .padding(.top, 48)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 0) {
                TourPicture(card: card)
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .frame(maxHeight: .infinity)
                words(card)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func words(_ card: WelcomeCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(card.title)
                .heading(.largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text(card.line)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The tour's page dots: the current one is a short bar.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(current + 1) of \(count)")
    }
}

/// One card's words and picture.
struct WelcomeCard: Identifiable {
    let id: Int
    let title: String
    let line: String
    /// The screenshot's asset name; until it exists, `symbol` stands in.
    let image: String
    let symbol: String
    let button: String

    static let all: [WelcomeCard] = [
        WelcomeCard(id: 0, title: "Every lap, every angle.",
                    line: "Apex DuoView plays F1 TV on your iPhone Duo, several feeds at once. Sign in with your F1 TV account. Live races and onboards need a video plan; multiview needs F1 TV Premium.",
                    image: "Tour1", symbol: "play.rectangle.on.rectangle", button: "Next"),
        WelcomeCard(id: 1, title: "Fold it, the view changes",
                    line: "Flat shows up to four feeds. Half-open like a book or a laptop, video sits on one half and timing on the other. Closed, the outer screen keeps playing.",
                    image: "Tour2", symbol: "rectangle.split.2x1", button: "Next"),
        WelcomeCard(id: 2, title: "Pick your feeds",
                    line: "Tap Feeds to choose the world feed, onboards, pit lane, tracker or data. The speaker on a feed moves the sound to it; SOUND marks the one you hear.",
                    image: "Tour3", symbol: "rectangle.grid.2x2", button: "Next"),
        WelcomeCard(id: 3, title: "Tap a car",
                    line: "Open the map or the tower and tap a car to put its onboard on screen. Hold a car on the map to see its pit window.",
                    image: "Tour4", symbol: "map", button: "Next"),
        WelcomeCard(id: 4, title: "Live, or from the start",
                    line: "Live sessions show in Race Weekend: watch live, or from the start. Every past race is in Archive, and Continue watching picks up where you stopped.",
                    image: "Tour5", symbol: "dot.radiowaves.left.and.right", button: "Start watching"),
    ]
}

/// The card's screenshot. PLACEHOLDER until the "after" screenshots exist (taken on the phone after
/// the Las Vegas race): a symbol on a dark panel, labelled as such.
private struct TourPicture: View {
    let card: WelcomeCard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if UIImage(named: card.image) != nil {
            Image(card.image)
                .resizable()
                .scaledToFit()
                .clipShape(shape)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 12) {
                Image(systemName: card.symbol)
                    .font(.system(.largeTitle))
                    .foregroundStyle(Theme.textSecondary)
                Text("Screenshot coming after the race")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface, in: shape)
            .accessibilityHidden(true)
        }
    }
}
