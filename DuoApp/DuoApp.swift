import F1TV
import SwiftUI

@main
struct DuoApp: App {
    @State private var model = AppModel()
    /// The opening plays once per launch, over the app (which starts loading underneath).
    @State private var openingDone = false
    /// The welcome tour shows once, on the first launch (Settings › Help plays it again).
    @AppStorage("welcomeTourSeen") private var tourSeen = false

    init() {
        AppTips.configure()
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(Theme.textPrimary)
                .foregroundStyle(Theme.textPrimary)
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in
                    // Transcripts only while radio is on screen: not in the background (picture in
                    // picture, audio).
                    model.radio.setAppActive(phase != .background)
                    guard phase == .active else { return }
                    Task { await model.revalidate() }
                }
                // Under the opening, so the opening fades out onto the tour's first card.
                .overlay {
                    if !tourSeen {
                        WelcomeTourView { withAnimation(.easeOut(duration: 0.3)) { tourSeen = true } }
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if !openingDone {
                        OpeningView { openingDone = true }
                            .preferredColorScheme(.dark)
                    }
                }
        }
    }
}
