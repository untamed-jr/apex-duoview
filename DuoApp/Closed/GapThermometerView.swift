import LiveTiming
import Multiview
import SwiftUI

/// The closed phone's Gap Thermometer, twice a second at picture time: two drivers' codes at
/// either end of a tall bar (the car ahead on top), the gap in large digits, ▼ closing or ▲
/// growing. The bar's colour slides from cool blue (3 s or more) through amber (2 s) to red (1 s
/// or less) by the reading's `heat`.
///
/// - The pair: the remembered one when both are this session's cars, else your driver and the
///   nearer car ahead or behind (`GapPair.defaultPair`), else P1 and P2. Left and right move it
///   along the race order; press and hold to pick both (`GapPairPicker`). Only a swipe or a pick is
///   remembered, so the default keeps following your driver.
/// - The spec's lines: "The Gap Thermometer works in races and sprints.", "Gaps start after the
///   first lap.", "{CODE} in the pits", "{CODE} is out — swipe for another pair".
/// - Sizes come from the page's own size; the type scales with its height.
struct GapThermometerView: View {
    let timing: TimingController
    let companion: CompanionController
    let settings: CompanionSettings
    let size: CGSize
    let onPageSwipe: @MainActor (CompanionModels.Swipe) -> Void
    let onBackground: @MainActor () -> Void

    /// The pair chosen by a swipe or the picker (or remembered); read from Settings once.
    @State private var chosen: [String]?
    @State private var loadedChoice = false
    @State private var picking = false

    var body: some View {
        // 2 Hz: the reading is at picture time, which isn't observed.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { onBackground() }
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in swiped(value.translation) })
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
            if timing.loadedSession?.info.isRace == true { picking = true }
        })
        .onAppear {
            if !loadedChoice {
                chosen = settings.gapPair
                loadedChoice = true
            }
        }
        .sheet(isPresented: $picking) {
            if let session = timing.loadedSession {
                GapPairPicker(session: session, order: ClosedPager.raceOrder(at: timing.pictureTime ?? .min, session: session),
                              start: currentPair.map { [$0.0, $0.1] } ?? []) { pair in
                    chosen = pair
                    settings.gapPair = pair
                }
            }
        }
    }

    private var currentPair: (String, String)? {
        guard let session = timing.loadedSession, let t = timing.pictureTime else { return nil }
        return CompanionModels.gapPair(stored: chosen, favourite: companion.favourite, at: t, session: session)
    }

    @ViewBuilder
    private var content: some View {
        let h = size.height
        VStack(spacing: h * 0.015) {
            Text(CompanionModels.gapTitle)
                .font(.system(size: max(13, h * 0.022), weight: .semibold))
                .fontWidth(.condensed)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, h * 0.06)
            if let session = timing.loadedSession {
                if !session.info.isRace {
                    line(CompanionModels.gapNotRace)
                } else if let t = timing.pictureTime, let pair = currentPair {
                    thermometer(pair, at: t, session: session)
                } else {
                    // No pair yet: no timing at picture time, or fewer than two cars.
                    line(CompanionModels.gapBeforeFirstLap)
                }
            } else {
                LaptopTimingNote(timing: timing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, max(16, size.width * 0.05))
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(17, size.height * 0.032)))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func thermometer(_ pair: (String, String), at t: UTCms, session: LoadedSession) -> some View {
        let reading = GapPair.reading(pair.0, pair.1, at: t, session: session)
        let text = CompanionModels.gapText(reading, drivers: session.drivers)
        let ends = CompanionModels.pairEnds(pair, reading: reading, at: t, session: session)
        let heat: Double?
        switch reading {
        case .gap(_, _, _, _, let value): heat = value
        default: heat = nil
        }
        let colour = heat.map { CompanionModels.heatColour($0) }
        let fill = colour.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Theme.raised
        let h = size.height
        let codeSize = max(26, h * 0.06)
        return VStack(spacing: h * 0.015) {
            code(ends.top, session: session, size: codeSize)
            ZStack {
                Capsule(style: .continuous)
                    .fill(fill.gradient)
                    .frame(width: max(56, size.width * 0.16))
                    .animation(.easeInOut(duration: 0.4), value: heat ?? -1)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    if !text.big.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(text.big)
                                .font(.system(size: max(44, h * 0.14), weight: .heavy).monospacedDigit())
                                .fontWidth(.condensed)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 6)
                            if let arrow = text.arrow {
                                Text(arrow)
                                    .font(.system(size: max(22, h * 0.05), weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 4)
                            }
                        }
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    }
                    if let note = text.note {
                        Text(note)
                            .font(.system(size: max(17, h * 0.032), weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .videoGlass(in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            code(ends.bottom, session: session, size: codeSize)
                .padding(.bottom, h * 0.05)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(ends, text: text, session: session))
        .accessibilityHint("Swipe left or right for another pair. Touch and hold to pick both drivers.")
    }

    private func code(_ number: String, session: LoadedSession, size: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.teamColour(session.drivers[number]?.teamColour ?? ""))
                .frame(width: 6, height: size * 0.85)
            Text(CompanionModels.code(number, drivers: session.drivers))
                .font(.system(size: size, weight: .heavy))
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func spoken(_ ends: (top: String, bottom: String), text: (big: String, note: String?, arrow: String?),
                        session: LoadedSession) -> String {
        let top = CompanionModels.code(ends.top, drivers: session.drivers)
        let bottom = CompanionModels.code(ends.bottom, drivers: session.drivers)
        var words = "\(top) and \(bottom)"
        if !text.big.isEmpty { words += ", \(text.big)" }
        if text.arrow == "\u{25BC}" { words += ", closing" }
        if text.arrow == "\u{25B2}" { words += ", growing" }
        if let note = text.note { words += ". \(note)" }
        return words
    }

    private func swiped(_ translation: CGSize) {
        guard let swipe = CompanionModels.swipe(translation, distance: 50) else { return }
        switch swipe {
        case .up, .down:
            onPageSwipe(swipe)
        case .left, .right:
            // Left moves a place back down the order, as Picture's left is the next feed.
            guard let session = timing.loadedSession, let t = timing.pictureTime, let pair = currentPair,
                  let next = GapPair.shifted(pair, by: swipe == .left ? 1 : -1, at: t, session: session)
            else { return }
            chosen = [next.0, next.1]
            settings.gapPair = [next.0, next.1]
        }
    }
}

/// Press and hold on the Gap Thermometer: pick its two drivers, in race order, with the team
/// colour as the driver pickers show it. Done once two are chosen.
struct GapPairPicker: View {
    let session: LoadedSession
    let order: [String]
    let start: [String]
    let onPick: @MainActor ([String]) -> Void

    @State private var picked: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { number in
                        Button {
                            toggle(number)
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Theme.teamColour(session.drivers[number]?.teamColour ?? ""))
                                    .frame(width: 3, height: 22)
                                Text(title(number)).rowTitle()
                                Spacer()
                                if picked.contains(number) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(picked.contains(number) ? .isSelected : AccessibilityTraits())
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle(CompanionModels.gapTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPick(picked)
                        dismiss()
                    }
                    .disabled(picked.count != 2)
                }
            }
        }
        .onAppear { picked = Array(start.prefix(2)) }
    }

    /// "#12 Antonelli", as `DriverRow` titles a driver.
    private func title(_ number: String) -> String {
        let name = session.drivers[number]?.lastName ?? ""
        return name.isEmpty ? "#\(number)" : "#\(number) \(name)"
    }

    /// Two at most: a third replaces the older pick.
    private func toggle(_ number: String) {
        if let i = picked.firstIndex(of: number) {
            picked.remove(at: i)
        } else {
            picked.append(number)
            if picked.count > 2 { picked.removeFirst() }
        }
    }
}
