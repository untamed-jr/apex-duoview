import SwiftUI

/// The opening (direction A, "Night circuit", owner 2026-11-18): the floodlit wet corner, red and
/// white light trails drawn along the racing line, the neon APEX logo lighting up, then the name,
/// tagline, version and small print. About 1.6 s plus a short hold, once per launch; a tap
/// anywhere skips it. With Reduce Motion it is a plain fade.
///
/// iOS's launch screen is the plain near-black `LaunchBackground`, and the first frame here is the
/// same colour with the artwork fading in, so the hand-over can't be seen.
///
/// Layout follows the screen's shape, not the fold: wide (the inner screen open flat) puts the
/// logo and text on the left half over a dark fade, with the track on the right; tall (laptop
/// pose, or the closed outer screen) puts the logo in the upper half and the small print low.
struct OpeningView: View {
    /// Called once, when the opening has faded out (or was skipped).
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkShown = false
    @State private var trailsDrawn = false
    @State private var logoLit = false
    @State private var nameShown = false
    @State private var finePrintShown = false
    @State private var fadingOut = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let wide = size.width > size.height
            ZStack {
                Theme.background
                artwork(in: size, wide: wide)
                    .opacity(artworkShown ? 1 : 0)
                trails(in: size, wide: wide)
                if wide {
                    wideLayout(size)
                } else {
                    tallLayout(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .opacity(fadingOut ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apex DuoView. Every lap, every angle.")
        .accessibilityHint("Double-tap to skip.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { skip() }
    }

    // MARK: Pieces

    /// The still track, filling the screen, kept to its bottom edge so the corner always shows.
    private func artwork(in size: CGSize, wide: Bool) -> some View {
        Image("OpeningArtwork")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .clipped()
            .overlay(shade(wide: wide))
            .accessibilityHidden(true)
    }

    /// Darkens where the text sits, as in the mockups.
    private func shade(wide: Bool) -> some View {
        let ink = Color(red: 5 / 255, green: 5 / 255, blue: 7 / 255)
        return Group {
            if wide {
                LinearGradient(
                    stops: [
                        .init(color: ink.opacity(0.88), location: 0),
                        .init(color: ink.opacity(0.78), location: 0.38),
                        .init(color: ink.opacity(0), location: 0.56),
                    ],
                    startPoint: .leading, endPoint: .trailing)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: ink.opacity(0.55), location: 0),
                        .init(color: ink.opacity(0.2), location: 0.45),
                        .init(color: ink.opacity(0.8), location: 0.62),
                        .init(color: ink.opacity(0.9), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// Three light trails along the racing line: red, near-white, red, drawn one after another.
    private func trails(in size: CGSize, wide: Bool) -> some View {
        let line = RacingLine(imageRect: Self.artworkRect(in: size))
        return ZStack {
            trail(line.offset(by: -0.008), colour: Self.trailRed, width: 2.6, delay: 0)
            trail(line.offset(by: 0.003), colour: Self.trailWhite, width: 1.4, delay: 0.08)
            trail(line.offset(by: 0.013), colour: Self.trailPink, width: 1.8, delay: 0.15)
        }
        .shadow(color: Self.trailRed.opacity(0.6), radius: 3)
        .mask {
            // In the wide layout the trails stay on the track side, clear of the text.
            if wide {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 0.56)],
                    startPoint: .leading, endPoint: .trailing)
            } else {
                Color.black
            }
        }
        .accessibilityHidden(true)
    }

    private func trail(_ line: RacingLine, colour: Color, width: CGFloat, delay: Double) -> some View {
        line
            .trim(from: 0, to: trailsDrawn ? 1 : 0)
            .stroke(colour, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .animation(reduceMotion ? nil : .timingCurve(0.3, 0.6, 0.2, 1, duration: 0.55).delay(delay),
                       value: trailsDrawn)
    }

    /// The neon APEX, with a red glow that grows as it lights.
    private func wordmark(width: CGFloat) -> some View {
        Image("OpeningWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .shadow(color: Theme.accent.opacity(logoLit ? 0.42 : 0), radius: width * 0.08)
            .scaleEffect(logoLit ? 1 : 0.86)
            .opacity(logoLit ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// "DuoView", with "View" in the app's red.
    private func name(_ style: Font.TextStyle) -> some View {
        HStack(spacing: 0) {
            Text("Duo").foregroundStyle(Theme.textPrimary)
            Text("View").foregroundStyle(Theme.accent)
        }
        .font(.system(style)).bold().fontWidth(.condensed)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var tagline: some View {
        Text("Every lap, every angle.")
            .font(.system(.title3)).fontWeight(.medium)
            .foregroundStyle(Theme.textSecondary)
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.versionLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text("Unofficial app. Not associated with Formula 1 companies. F1, FORMULA ONE and related marks are trade marks of Formula One Licensing B.V.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Requires an F1 TV subscription")
                .font(.caption2).bold()
                .foregroundStyle(Theme.textSecondary)
        }
        .opacity(finePrintShown ? 1 : 0)
    }

    // MARK: Layouts

    /// Open flat: everything on the left half, the track on the right.
    private func wideLayout(_ size: CGSize) -> some View {
        let half = size.width / 2
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                wordmark(width: min(half * 0.5, 260))
                name(.largeTitle)
                    .opacity(nameShown ? 1 : 0)
                    .offset(y: nameShown ? 0 : 8)
            }
            tagline
                .padding(.top, 10)
                .opacity(nameShown ? 1 : 0)
                .offset(y: nameShown ? 0 : 8)
            Spacer(minLength: 0)
            finePrint
                .padding(.bottom, 24)
        }
        .padding(.leading, max(24, size.width * 0.04))
        .padding(.trailing, 24)
        .frame(width: half, height: size.height, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Laptop pose or the closed screen: logo and name in the upper half, small print low.
    private func tallLayout(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            wordmark(width: min(size.width * 0.72, 420))
            name(.largeTitle)
                .padding(.top, 4)
                .opacity(nameShown ? 1 : 0)
                .offset(y: nameShown ? 0 : 8)
            tagline
                .padding(.top, 8)
                .opacity(nameShown ? 1 : 0)
                .offset(y: nameShown ? 0 : 8)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            finePrint
                .padding(.bottom, 28)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(width: size.width, height: size.height)
    }

    // MARK: Timing

    /// The timeline from the mockups: trails 0–0.7 s, logo 0.2–0.9 s, name and tagline
    /// 0.85–1.3 s, version and small print 1.15–1.6 s; then a short hold and a fade.
    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) {
                artworkShown = true
                trailsDrawn = true
                logoLit = true
                nameShown = true
                finePrintShown = true
            }
            await pause(1.4)
            await fadeOut()
            return
        }
        withAnimation(.easeOut(duration: 0.25)) { artworkShown = true }
        trailsDrawn = true
        await pause(0.2)
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)) { logoLit = true }
        await pause(0.65)
        withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.4)) { nameShown = true }
        await pause(0.3)
        withAnimation(.easeOut(duration: 0.45)) { finePrintShown = true }
        await pause(1.0)
        await fadeOut()
    }

    private func skip() {
        guard !finished else { return }
        Task { await fadeOut(duration: 0.2) }
    }

    private func fadeOut(duration: Double = 0.35) async {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: duration)) { fadingOut = true }
        await pause(duration)
        onFinished()
    }

    /// Sleeps; a cancelled task (the view went away) ends the timeline early, which is fine.
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Constants

    private static let trailRed = Color(red: 1, green: 0x2A / 255, blue: 0x3C / 255)
    private static let trailWhite = Color(red: 1, green: 0xE6 / 255, blue: 0xDC / 255)
    private static let trailPink = Color(red: 1, green: 0x4A / 255, blue: 0x58 / 255)

    /// The artwork's pixel size (Design/OpeningArtwork.png, 9:16).
    private static let artworkSize = CGSize(width: 1520, height: 2688)

    /// Where the artwork lands on screen when it fills `size` kept to the bottom edge, so the
    /// trails can follow the track whatever the screen's shape.
    static func artworkRect(in size: CGSize) -> CGRect {
        let scale = max(size.width / artworkSize.width, size.height / artworkSize.height)
        let shown = CGSize(width: artworkSize.width * scale, height: artworkSize.height * scale)
        return CGRect(x: (size.width - shown.width) / 2, y: size.height - shown.height,
                      width: shown.width, height: shown.height)
    }

    /// "v1.0-beta.3", from the bundle like Settings › About.
    private static var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let label = info["DuoBetaLabel"] as? String ?? ""
        return "v" + (label.isEmpty ? version : "\(version)-\(label)")
    }
}

/// The racing line through the artwork's corner, in the artwork's own 0…1 coordinates (measured
/// on Design/OpeningArtwork.png), placed onto the rect the artwork fills on screen.
private struct RacingLine: Shape {
    let imageRect: CGRect
    /// Moves the whole line up or down, as a fraction of the artwork's height.
    var shift: CGFloat = 0

    func offset(by fraction: CGFloat) -> RacingLine {
        RacingLine(imageRect: imageRect, shift: fraction)
    }

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: imageRect.minX + x * imageRect.width,
                    y: imageRect.minY + (y + shift) * imageRect.height)
        }
        var path = Path()
        path.move(to: point(0.10, 1.03))
        path.addCurve(to: point(1.05, 0.755), control1: point(0.22, 0.86), control2: point(0.45, 0.775))
        return path
    }
}
