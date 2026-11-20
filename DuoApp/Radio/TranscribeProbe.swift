import AVFoundation
import Foundation
import LiveTiming
import Speech
import SwiftUI

/// What "Transcribe a test clip" found (owner check O4): whether iOS's on-device transcriber is
/// available, the locale, whether its model was installed or had to download, how long the clip
/// took, and the text.
struct TranscribeProbeReport: Sendable, Equatable {
    var clip: String
    var available: Bool
    var locale: String
    var model: String
    var seconds: Double?
    var text: String
}

/// Settings › Debug › "Transcribe a test clip" (build 17's probe; removed before release): turns
/// the first cached team radio clip into text on the phone with `SpeechTranscriber`. Every Speech
/// call is in `probe(fileURL:)`, the calls build 18's transcriber will make. Nothing leaves the
/// phone (iOS may download its English model from Apple: a system download).
enum TranscribeProbe {
    /// Asked for in this order.
    static let locales = ["en-GB", "en-US"]
    static let noClip = "No clip cached yet \u{2014} play a team radio clip first."

    /// The first clip in `Caches/radio`, by folder and name; nil when there is none.
    static func firstCachedClip() -> URL? {
        guard let base = RadioFetch.defaultBase else { return nil }
        let manager = FileManager.default
        let folders = ((try? manager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for folder in folders {
            let clips = ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "mp3" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let first = clips.first { return first }
        }
        return nil
    }

    /// Finds the first cached clip and probes it, off the main actor.
    @concurrent
    static func run() async -> TranscribeProbeReport {
        guard let file = firstCachedClip() else {
            return TranscribeProbeReport(clip: "", available: SpeechTranscriber.isAvailable, locale: "", model: "",
                                         seconds: nil, text: noClip)
        }
        return await probe(fileURL: file)
    }

    /// The one function with the Speech calls: availability, the locale (en-GB, then en-US, through
    /// `supportedLocale(equivalentTo:)`), the model (installed, or downloaded now through
    /// `AssetInventory`), then `SpeechTranscriber` in a `SpeechAnalyzer` fed the file with
    /// `analyzeSequence(from:)`, timed.
    @concurrent
    static func probe(fileURL: URL) async -> TranscribeProbeReport {
        var report = TranscribeProbeReport(clip: fileURL.lastPathComponent, available: SpeechTranscriber.isAvailable,
                                           locale: "", model: "", seconds: nil, text: "")
        guard report.available else {
            report.text = "SpeechTranscriber isn't available on this device."
            return report
        }
        var found: Locale?
        for identifier in locales {
            if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) {
                found = locale
                break
            }
        }
        guard let locale = found else {
            report.text = "No English locale is supported."
            return report
        }
        report.locale = locale.identifier(.bcp47)
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [])
        let status = await AssetInventory.status(forModules: [transcriber])
        report.model = describe(status)
        do {
            if status != .installed {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                report.model += " \u{2192} " + describe(await AssetInventory.status(forModules: [transcriber]))
            }
            let started = ContinuousClock.now
            async let words = transcriber.results.reduce(into: "") { text, result in
                text += String(result.text.characters)
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let file = try AVAudioFile(forReading: fileURL)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let text = (try await words).trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsed = ContinuousClock.now - started
            report.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            report.text = text.isEmpty ? TranscriptionQueue.noWords : text
        } catch {
            report.text = "Failed: \(error.localizedDescription)"
        }
        return report
    }

    /// Compared, not switched, so a status added later needs no `@unknown default`.
    private static func describe(_ status: AssetInventory.Status) -> String {
        if status == .installed { return "Installed" }
        if status == .downloading { return "Downloading" }
        if status == .supported { return "Not installed" }
        if status == .unsupported { return "Not supported" }
        return "Unknown"
    }
}

/// The Debug rows: the button, then what the last run found.
struct TranscribeProbeRows: View {
    @State private var running = false
    @State private var report: TranscribeProbeReport?

    var body: some View {
        Button("Transcribe a test clip") {
            running = true
            Task {
                report = await TranscribeProbe.run()
                running = false
            }
        }
        .disabled(running)
        if running {
            LabeledContent("Transcribing") {
                ProgressView()
            }
        }
        if let report {
            if !report.clip.isEmpty {
                LabeledContent("Clip", value: report.clip)
            }
            LabeledContent("Available", value: report.available ? "Yes" : "No")
            if !report.locale.isEmpty {
                LabeledContent("Locale", value: report.locale)
            }
            if !report.model.isEmpty {
                LabeledContent("Model", value: report.model)
            }
            if let seconds = report.seconds {
                LabeledContent("Took", value: seconds.formatted(.number.precision(.fractionLength(1))) + " s")
            }
            Text(report.text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }
}
