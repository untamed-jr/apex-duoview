import F1TV
import SwiftUI

/// Settings: account, multiview, the track map, team radio, a live fold readout, About, credits,
/// and Debug (the fold simulator and build 17's "Transcribe a test clip").
/// Shown in the system sheet on a narrow screen, and in the app's own `SettingsPanel` on a wide
/// one, so it closes through `onDone` rather than the environment's dismiss action.
struct SettingsView: View {
    let model: AppModel
    let fold: FoldState
    let onDone: () -> Void
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    private var fake: FakeFoldProvider { FakeFoldProvider(state: fold) }
    /// Help: the welcome tour again, and the first-time tips.
    @State private var showTour = false
    @State private var tipsReset = false
    @AppStorage(AppTips.showKey) private var showTips = true
    /// "Clear watch history" asks first, then says it's done.
    @State private var confirmClearHistory = false
    @State private var historyCleared = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection.listRowBackground(Theme.surface)
                MultiviewSettingsSection(model: model).listRowBackground(Theme.surface)
                TimingSettingsSection(timing: model.timing).listRowBackground(Theme.surface)
                RadioSettingsSection(settings: model.companion).listRowBackground(Theme.surface)
                foldSection.listRowBackground(Theme.surface)
                watchingSection.listRowBackground(Theme.surface)
                helpSection.listRowBackground(Theme.surface)
                aboutSection.listRowBackground(Theme.surface)
                creditsSection.listRowBackground(Theme.surface)
                debugSection.listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .fullScreenCover(isPresented: $showTour) {
            WelcomeTourView { showTour = false }
        }
    }

    // MARK: Watching

    /// Owner request (FP1 night): Continue watching and the watched marks can be cleared.
    private var watchingSection: some View {
        Section {
            Button("Clear watch history", role: .destructive) { confirmClearHistory = true }
                .disabled(historyCleared)
                .confirmationDialog("Clear watch history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) {
                        model.recents.removeAll()
                        model.history.removeAll()
                        historyCleared = true
                    }
                } message: {
                    Text("Continue watching and the watched marks are cleared. Your account and settings stay.")
                }
            if historyCleared {
                Text("Watch history cleared.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Watching").sectionLabel()
        } footer: {
            Text("To remove one video from Continue watching, touch and hold its tile.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Help

    private var helpSection: some View {
        Section {
            Button("How to use") { showTour = true }
            Toggle("Show tips", isOn: $showTips)
                .tint(Theme.accent)
            Button("Reset tips") {
                UserDefaults.standard.set(true, forKey: AppTips.resetKey)
                tipsReset = true
            }
            .disabled(tipsReset)
            if tipsReset {
                Text("The tips come back the next time you open the app.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Help").sectionLabel()
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            switch model.auth {
            case .signedIn(let account):
                LabeledContent("Signed in", value: account.tier)
                Button("Sign out", role: .destructive) {
                    onDone()
                    onSignOut()
                }
            case .signingIn:
                LabeledContent("Signing in") {
                    ProgressView()
                }
            case .signedOut:
                Button("Sign in", action: onSignIn)
            }
        } header: {
            Text("Account").sectionLabel()
        }
    }

    // MARK: Fold

    private var foldSection: some View {
        Section {
            LabeledContent("Posture", value: fold.posture.label)
            LabeledContent("Hinge", value: Self.hingeText(fold))
            LabeledContent("Hinge angle", value: Self.angleText(fold.hingeAngle))
            LabeledContent("Fold", value: Self.frameText(fold.foldFrame))
            LabeledContent("Screen", value: Self.sizeText(fold.rootSize))
            LabeledContent("Safe edges", value: Self.insetsText(fold.safeInsets))
            LabeledContent("Source", value: fold.source == .fake ? "Simulated" : "Device")
        } header: {
            Text("Fold").sectionLabel()
        } footer: {
            Text("Hinge is what the device reports, even while simulating. Fold is the fold's "
                + "frame in screen points from the top-left corner. With a vertical fold in "
                + "portrait it should read y 0 and the screen's full height.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                LogoTile(size: 44, glow: false)
                Text(versionText)
            }
        } header: {
            Text("About").sectionLabel()
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let label = info["DuoBetaLabel"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? "?"
        let full = label.isEmpty ? version : "\(version)-\(label)"
        // The code the install script built from, so two builds with the same number can be told apart.
        let code = (info["DuoSourceCode"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return "Apex DuoView v\(full) (build \(build)\(code.isEmpty ? "" : " · \(code)"))"
    }

    // MARK: Credits

    private struct Credit: Identifiable, Sendable {
        let name: String
        let detail: String
        let url: URL
        var id: String { name }
    }

    // URLs match README.md's Credits section.
    private static let credits: [Credit] = [
        Credit(
            name: "Apexview", detail: "mikeyyy0 · MIT licence",
            url: URL(string: "https://github.com/mikeyyy0/apexview")!),
        Credit(
            name: "eXhumer/f1tv-api", detail: "MIT licence",
            url: URL(string: "https://github.com/eXhumer/f1tv-api")!),
        Credit(
            name: "eXhumer/eXViewer", detail: "MIT licence",
            url: URL(string: "https://github.com/eXhumer/eXViewer")!),
        Credit(
            name: "FastF1", detail: "MIT licence",
            url: URL(string: "https://github.com/theOehrly/Fast-F1")!),
        Credit(
            name: "MultiViewer", detail: "Public circuit data",
            url: URL(string: "https://multiviewer.app")!),
    ]

    private var creditsSection: some View {
        Section {
            ForEach(Self.credits) { credit in
                Link(destination: credit.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(credit.name)
                        Text(credit.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens in Safari")
            }
        } header: {
            Text("Credits and licences").sectionLabel()
        }
    }

    // MARK: Debug

    // Shown in every build during the betas so testers can simulate a fold; hidden at launch.
    private var debugSection: some View {
        Section {
            Toggle("Simulate fold", isOn: Binding(
                get: { fold.source == .fake },
                set: { on in
                    if on { fake.start() } else { fake.stop() }
                }))
            .tint(Theme.accent)
            Picker("Posture", selection: Binding(
                get: { fold.posture },
                set: { fake.setPosture($0) })
            ) {
                ForEach(Posture.allCases, id: \.self) { posture in
                    Text(posture.label).tag(posture)
                }
            }
            .disabled(!fake.isActive)
            VStack(alignment: .leading) {
                LabeledContent("Hinge angle", value: Self.angleText(fold.hingeAngle))
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { fold.hingeAngle ?? FakeFoldProvider.defaultAngle },
                        set: { fake.setAngle($0) }),
                    in: FakeFoldProvider.angleRange,
                    step: 1
                ) {
                    Text("Hinge angle")
                } minimumValueLabel: {
                    Text("0°").accessibilityHidden(true)
                } maximumValueLabel: {
                    Text("180°").accessibilityHidden(true)
                }
                .accessibilityValue(Self.angleText(fold.hingeAngle ?? FakeFoldProvider.defaultAngle))
                .tint(Theme.accent)
            }
            .disabled(!fake.isActive)
            // Build 17's probe (owner check O4); removed before release.
            TranscribeProbeRows()
        } header: {
            Text("Debug").sectionLabel()
        } footer: {
            Text("Simulating replaces the device's fold readings until you turn it off. Transcribe a test "
                + "clip turns the first team radio clip you played into text on this iPhone.")
        }
    }

    // MARK: Formatting

    private static func frameText(_ frame: CGRect?) -> String {
        guard let frame else { return "None" }
        return "x \(points(frame.minX)), y \(points(frame.minY)), "
            + "\(points(frame.width)) × \(points(frame.height))"
    }

    /// The device's own hinge report: not reported yet, no hinge, or status and angle.
    private static func hingeText(_ fold: FoldState) -> String {
        guard fold.hingeReported else { return "Not reported yet" }
        guard let hinge = fold.systemHinge else { return "None (this device has no hinge)" }
        return "\(hinge.status.label), \(angleText(hinge.angleDegrees))"
    }

    /// Top, left, bottom, right, in points.
    private static func insetsText(_ insets: ScreenInsets) -> String {
        "top \(points(insets.top)), left \(points(insets.leading)), "
            + "bottom \(points(insets.bottom)), right \(points(insets.trailing))"
    }

    private static func sizeText(_ size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "Not measured yet" }
        return "\(points(size.width)) × \(points(size.height))"
    }

    private static func angleText(_ degrees: Double?) -> String {
        guard let degrees else { return "None" }
        return "\(degrees.formatted(.number.precision(.fractionLength(0))))°"
    }

    private static func points(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0)))
    }
}
