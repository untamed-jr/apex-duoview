import LiveTiming
import SwiftUI

/// The line at the top of the tower, at picture time (2 Hz): "Lap 23/71" in a race or the
/// session clock otherwise, the track status, and the weather (air and track temperature, with a
/// rain mark while it rains). Reads only `timing.header`.
struct SessionHeaderView: View {
    let timing: TimingController

    var body: some View {
        let header = timing.header
        HStack(spacing: 8) {
            if !header.progress.isEmpty {
                Text(header.progress)
                    .font(.caption)
                    .bold()
                    .fontWidth(.condensed)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(TimingText.status(header.status))
                .font(.caption2)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(Self.statusColour(header.status))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if header.raining {
                Image(systemName: "cloud.rain.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Raining")
            }
            if !header.weather.isEmpty {
                Text(header.weather)
                    .font(.caption2)
                    .fontWidth(.condensed)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.raised.opacity(0.6))
        .accessibilityElement(children: .combine)
    }

    /// Green for a clear track, the flag colours otherwise.
    static func statusColour(_ status: TrackStatusKind) -> Color {
        switch status {
        case .clear: return Theme.timingGreen
        case .red: return Theme.flagRed
        case .yellow, .safetyCar, .safetyCarInThisLap, .vsc, .vscEnding: return Theme.flagYellow
        }
    }
}
