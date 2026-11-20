import Multiview
import SwiftUI

/// The "Radio" control, beside Map in the multiview's top bar and over the single-feed player:
/// shows or hides the Radio panel. Only for content with timing; it shows whether or not the
/// session has radio, so it never hints that radio is coming.
struct RadioButton: View {
    let radio: RadioController
    let timing: TimingController
    let onInteraction: @MainActor () -> Void

    var body: some View {
        if timing.showsData {
            let showing = radio.panelShown
            Button {
                onInteraction()
                radio.togglePanel()
            } label: {
                MultiviewChromeLabel(title: RadioModels.button,
                                     systemImage: showing ? "antenna.radiowaves.left.and.right.circle.fill"
                                         : "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(showing ? RadioModels.hide : "Show team radio")
        }
    }
}

/// The Radio panel's content (spec: "Team radio by lap"): the chips (All · My driver · a driver),
/// then the clips oldest at the top, newest at the bottom, under a small header per lap; the
/// list follows new clips. A tap plays a clip while the feeds go quiet; a tap again stops it.
/// Everything comes from `RadioController` at picture time.
struct RadioPanelContent: View {
    let radio: RadioController

    var body: some View {
        VStack(spacing: 0) {
            RadioChips(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            RadioList(radio: radio)
            if let notice = radio.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Theme.flagYellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

/// All · My driver (when you have one) · a driver (a menu of the session's drivers by code).
private struct RadioChips: View {
    let radio: RadioController

    var body: some View {
        let filter = RadioModels.effective(radio.filter, favourite: radio.favourite)
        let picked: String? = {
            if case .driver(let number) = filter { return number }
            return nil
        }()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(RadioModels.allChip, selected: filter == .all) { radio.filter = .all }
                if radio.favourite != nil {
                    chip(RadioModels.myDriverChip, selected: filter == .myDriver) { radio.filter = .myDriver }
                }
                Menu {
                    ForEach(radio.drivers) { driver in
                        Button(driver.tla) { radio.filter = .driver(driver.number) }
                    }
                } label: {
                    chipLabel(picked.map { number in radio.drivers.first { $0.number == number }?.tla ?? number }
                                  ?? RadioModels.driverChip,
                              selected: picked != nil, menu: true)
                }
                .disabled(radio.drivers.isEmpty)
                .accessibilityLabel("Choose a driver")
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            chipLabel(title, selected: selected, menu: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipLabel(_ title: String, selected: Bool, menu: Bool) -> some View {
        HStack(spacing: 3) {
            Text(title)
            if menu {
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .font(.caption)
        .bold()
        .foregroundStyle(selected ? Color.black : Theme.textPrimary)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(selected ? Theme.textPrimary : Color.white.opacity(0.12), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The clips, or the empty line; follows the newest clip as it comes.
private struct RadioList: View {
    let radio: RadioController

    var body: some View {
        let rows = radio.rows
        if rows.isEmpty {
            Text(emptyText)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                if let header = row.header {
                                    Text(header)
                                        .font(.caption2)
                                        .bold()
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.leading, 8)
                                        .padding(.top, 6)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                RadioRow(row: row, playing: radio.playing == row.path) {
                                    toggle(row.path)
                                }
                            }
                            .id(row.path)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .onAppear {
                    if let last = rows.last?.path { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: rows.last?.path) { _, last in
                    guard let last else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyText: String {
        let filter = RadioModels.effective(radio.filter, favourite: radio.favourite)
        let number = RadioModels.driver(of: filter, favourite: radio.favourite)
        let tla = number.map { number in radio.drivers.first { $0.number == number }?.tla ?? number }
        return RadioModels.emptyText(filter: filter, tla: tla)
    }

    private func toggle(_ path: String) {
        if radio.playing == path {
            radio.stop()
        } else {
            radio.play(path: path)
        }
    }
}
