import LiveTiming
import SwiftUI

/// The timing tower panel: the session header, then every car with timing in running order,
/// refreshed at 2 Hz from the controller (`timing.tower`, at picture time). Columns: position, a
/// team colour bar, the three-letter code, the last lap (or PIT) coloured for pace, the gap ("Leader"
/// in a race, "Fastest" otherwise), the interval, and the tyre (a compound ring with its letter,
/// then laps on the set). In qualifying the knockout zone is shaded and knocked-out cars are
/// dimmed. Your driver and a rival within 1.0 s glow (races only). Tapping a row opens that car's
/// onboard (`onCar`). Narrower than every column needs (a resized panel, Director's Desk's tower
/// column), the interval goes, then the last lap (`TowerColumns`).
struct TowerView: View {
    let timing: TimingController
    /// A row was tapped (its racing number).
    let onCar: @MainActor (String) -> Void

    var body: some View {
        switch timing.status {
        case .ready, .estimated:
            if timing.timingHidden {
                // Live, well before the join: nothing to show yet but why.
                TowerMessage(text: timing.catchUpNote ?? LiveNote.catchingUp, busy: false)
            } else {
                GeometryReader { proxy in
                    let columns = TowerColumns.fitting(proxy.size.width)
                    VStack(spacing: 0) {
                        SessionHeaderView(timing: timing)
                        if let note = timing.catchUpNote {
                            TimingQuietLine(text: note)
                        }
                        TowerColumnTitles(gapHeader: timing.gapHeader, columns: columns)
                        TowerRows(timing: timing, columns: columns, onCar: onCar)
                    }
                }
            }
        case .loading:
            TowerMessage(text: timing.loadingText, busy: true)
        case .unavailable(let reason):
            TowerMessage(text: reason, busy: false)
        case .idle:
            Color.clear
        }
    }
}

/// The rows: their own view, so only it follows `timing.tower`.
private struct TowerRows: View {
    let timing: TimingController
    let columns: TowerColumns
    let onCar: @MainActor (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(timing.tower, id: \.number) { row in
                    Button {
                        onCar(row.number)
                    } label: {
                        TowerRowView(row: row, columns: columns)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TowerRowView.accessibility(row))
                    .accessibilityHint("Opens this car's onboard")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// The column titles.
private struct TowerColumnTitles: View {
    let gapHeader: String
    let columns: TowerColumns

    var body: some View {
        HStack(spacing: TowerLayout.spacing) {
            title("P", width: TowerLayout.position, alignment: .trailing)
            Color.clear.frame(width: TowerLayout.bar)
            title("Driver", width: TowerLayout.code, alignment: .leading)
            if columns.lastLap {
                title("Last lap", width: TowerLayout.lap, alignment: .trailing)
            }
            title(gapHeader, width: TowerLayout.gap, alignment: .trailing)
            if columns.interval {
                title("Int", width: TowerLayout.interval, alignment: .trailing)
            }
            title("Tyre", width: TowerLayout.tyre, alignment: .leading)
        }
        .padding(.horizontal, TowerLayout.inset)
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func title(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2)
            .fontWidth(.condensed)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: alignment)
    }
}

/// The tower's column widths, in points (`TowerColumns` adds them up to choose the columns).
enum TowerLayout {
    static let inset: CGFloat = 6
    static let spacing: CGFloat = 4
    static let position: CGFloat = 18
    static let bar: CGFloat = 3
    static let code: CGFloat = 32
    static let lap: CGFloat = 56
    static let gap: CGFloat = 50
    static let interval: CGFloat = 44
    static let tyre: CGFloat = 38
    static let rowHeight: CGFloat = 22
}

/// One car's row.
struct TowerRowView: View {
    let row: TowerRow
    var columns: TowerColumns = .all
    /// Design pass q7: rows get taller as the iPhone's text size grows (22 pt at the default).
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = TowerLayout.rowHeight

    var body: some View {
        HStack(spacing: TowerLayout.spacing) {
            cell(row.position.map(String.init) ?? "–", width: TowerLayout.position, alignment: .trailing,
                 colour: Theme.textSecondary)
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.teamColour(row.teamColour))
                .frame(width: TowerLayout.bar, height: 14)
            Text(row.tla)
                .font(.caption)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: TowerLayout.code, alignment: .leading)
            if columns.lastLap {
                cell(row.lastLap, width: TowerLayout.lap, alignment: .trailing,
                     colour: row.lastLap == "PIT" ? Theme.flagYellow : TimingColours.lap(row.lastLapPace))
            }
            // Without the last-lap column, PIT shows in the gap's place.
            if !columns.lastLap, row.lastLap == "PIT" {
                cell("PIT", width: TowerLayout.gap, alignment: .trailing, colour: Theme.flagYellow)
            } else {
                cell(row.gap, width: TowerLayout.gap, alignment: .trailing, colour: Theme.textPrimary)
            }
            if columns.interval {
                cell(row.interval, width: TowerLayout.interval, alignment: .trailing, colour: Theme.textSecondary)
            }
            TyreCell(tyre: row.tyre)
                .frame(width: TowerLayout.tyre, alignment: .leading)
        }
        .padding(.horizontal, TowerLayout.inset)
        .frame(height: rowHeight)
        .background(background)
        .overlay {
            if row.battle {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.flagYellow.opacity(0.8), lineWidth: 1)
                    .shadow(color: Theme.flagYellow.opacity(0.7), radius: 4)
                    .allowsHitTesting(false)
            }
        }
        .opacity(row.dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    /// The battle's glow, else qualifying's knockout zone.
    private var background: Color {
        if row.battle { return Theme.flagYellow.opacity(0.16) }
        if row.inKnockoutZone { return Theme.flagRed.opacity(0.14) }
        return .clear
    }

    private func cell(_ text: String, width: CGFloat, alignment: Alignment, colour: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWidth(.condensed)
            .monospacedDigit()
            .foregroundStyle(colour)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: alignment)
    }

    /// What VoiceOver reads for a row.
    static func accessibility(_ row: TowerRow) -> String {
        var parts = [row.position.map { "P\($0)" } ?? "No position", row.tla]
        if !row.lastLap.isEmpty { parts.append(row.lastLap == "PIT" ? "in the pits" : "last lap \(row.lastLap)") }
        if !row.gap.isEmpty { parts.append("gap \(row.gap)") }
        if !row.interval.isEmpty { parts.append("interval \(row.interval)") }
        if let tyre = row.tyre { parts.append("\(TimingColours.tyreName(tyre.compound)) tyre, \(tyre.laps) laps") }
        if row.battle { parts.append("battle") }
        if row.inKnockoutZone { parts.append("in the knockout zone") }
        if row.dimmed { parts.append("out") }
        return parts.joined(separator: ", ")
    }
}

/// The compound ring with its letter, then laps on the set.
private struct TyreCell: View {
    let tyre: (compound: Character, laps: Int)?
    /// Design pass q7: the compound letter and its ring grow with the text size.
    @ScaledMetric(relativeTo: .caption2) private var letterSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption2) private var ringSize: CGFloat = 15

    var body: some View {
        if let tyre {
            HStack(spacing: 3) {
                Text(String(tyre.compound))
                    .font(.system(size: letterSize, weight: .heavy))
                    .foregroundStyle(TimingColours.tyre(tyre.compound))
                    .frame(width: ringSize, height: ringSize)
                    .overlay {
                        Circle().strokeBorder(TimingColours.tyre(tyre.compound), lineWidth: 2)
                    }
                Text("\(max(tyre.laps, 0))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

/// Instead of the rows: loading, or why there is none.
private struct TowerMessage: View {
    let text: String
    let busy: Bool

    var body: some View {
        VStack(spacing: 8) {
            if busy {
                ProgressView().tint(Theme.textSecondary)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

/// The pace and tyre colours the tower and the cards share. Plain functions, no actor.
enum TimingColours {
    /// A lap time: purple for the fastest of all, green for a personal best, white otherwise.
    static func lap(_ pace: SectorPace) -> Color {
        switch pace {
        case .overallBest: return Theme.timingPurple
        case .personalBest: return Theme.timingGreen
        case .set, .empty: return Theme.textPrimary
        }
    }

    /// A sector bar: purple, green, yellow, or grey for none yet.
    static func sector(_ pace: SectorPace) -> Color {
        switch pace {
        case .overallBest: return Theme.timingPurple
        case .personalBest: return Theme.timingGreen
        case .set: return Theme.flagYellow
        case .empty: return Theme.textTertiary
        }
    }

    static func tyre(_ compound: Character) -> Color {
        switch compound {
        case "S": return Theme.tyreSoft
        case "M": return Theme.tyreMedium
        case "H": return Theme.tyreHard
        case "I": return Theme.tyreIntermediate
        case "W": return Theme.tyreWet
        default: return Theme.textSecondary
        }
    }

    static func tyreName(_ compound: Character) -> String {
        switch compound {
        case "S": return "soft"
        case "M": return "medium"
        case "H": return "hard"
        case "I": return "intermediate"
        case "W": return "wet"
        default: return String(compound)
        }
    }
}
