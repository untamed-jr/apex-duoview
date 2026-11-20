import SwiftUI

/// One clip: the team-colour bar, the code, (where there is no lap header) its lap label, and ▶,
/// or ■ while it plays. A tap plays it, or stops it. A clip new in normal play flashes once,
/// softly (`isNew` for 3 s). Transcripts join the row with build 18.
struct RadioRow: View {
    let row: RadioRowModel
    let playing: Bool
    /// Race Engineer's spot has no lap headers: the label shows on the row.
    var showsLabel = false
    let onTap: @MainActor () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.teamColour(row.teamColour))
                    .frame(width: 3, height: 20)
                Text(row.tla)
                    .font(.footnote)
                    .bold()
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.textPrimary)
                if showsLabel, let label = row.label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(playing ? Theme.accent : Theme.textPrimary)
                    .frame(width: 24)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(row.isNew ? 0.16 : 0))
            }
            .animation(.easeInOut(duration: 0.6), value: row.isNew)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(playing ? "Stops the clip" : "Plays the clip")
    }

    private var accessibilityText: String {
        let lap = row.label.map { ", \($0)" } ?? ""
        return "Radio from \(row.tla)\(lap)"
    }
}
