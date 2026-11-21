import SwiftUI

/// After Unfold to See's jump: "Rewound to Safety car · Lap 23 — Back to where you were", for
/// 15 s (the companion drops it on its tick). A tap goes back: to the place the jump left from,
/// or the live edge if it was there. In every posture, at the top of the multiview.
struct BackChip: View {
    let companion: CompanionController

    var body: some View {
        if let chip = companion.backChip {
            Button {
                companion.back()
            } label: {
                Text(CompanionModels.backChipText(chip.title))
                    .font(.footnote.bold())
                    .fontWidth(.condensed)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityHint("Goes back to where you were before the jump")
        }
    }
}
