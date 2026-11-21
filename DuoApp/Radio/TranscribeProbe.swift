import Foundation
import LiveTiming
import Speech
import SwiftUI

/// What "Transcribe a test clip" found (owner checks O4 and O7): whether `SpeechTranscriber` is
/// available, the engine the transcriber chose and its locale, whether the speech model was ready
/// or had to download, how long the clip took, and the text.
struct TranscribeProbeReport: Sendable, Equatable {
    var clip: String
    var available: Bool
    var engine: String
    var locale: String
    var model: String
    var seconds: Double?
    var text: String
}

/// Settings › Debug › "Transcribe a test clip" (build 17's probe; removed before release): turns
/// the first cached team radio clip into text on the phone through the app's own `Transcriber`,
/// the same engine, model download and fallbacks the Radio panel uses. Nothing leaves the phone
/// (iOS may download its English model from Apple: a system download).
enum TranscribeProbe {
    static let noClip = "No clip cached yet \u{2014} play a team radio clip first."
    /// How long it waits for the model to download.
    static let downloadWait: Duration = .seconds(600)

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
            return TranscribeProbeReport(clip: "", available: SpeechTranscriber.isAvailable, engine: "", locale: "",
                                         model: "", seconds: nil, text: noClip)
        }
        return await probe(fileURL: file)
    }

    /// A fresh `Transcriber`: `prepare()` (waiting out a model download), then the clip, timed,
    /// with the radio words as hints.
    @concurrent
    static func probe(fileURL: URL) async -> TranscribeProbeReport {
        var report = TranscribeProbeReport(clip: fileURL.lastPathComponent, available: SpeechTranscriber.isAvailable,
                                           engine: "", locale: "", model: "", seconds: nil, text: "")
        let transcriber = Transcriber()
        var readiness = await transcriber.prepare()
        report.model = describe(readiness)
        let deadline = ContinuousClock.now + downloadWait
        while readiness == .downloadingModel, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            readiness = await transcriber.prepare()
        }
        if describe(readiness) != report.model { report.model += " \u{2192} " + describe(readiness) }
        if let engine = await transcriber.engine {
            report.engine = engine.name
            report.locale = engine.locale.identifier(.bcp47)
        }
        guard readiness == .ready else {
            report.text = TranscriptState.line(for: readiness) ?? ""
            return report
        }
        let started = ContinuousClock.now
        do {
            let text = try await transcriber.transcribe(fileURL: fileURL, hints: TranscriptState.radioWords)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            report.text = text.isEmpty ? TranscriptionQueue.noWords : text
        } catch {
            report.text = "Failed: \(error.localizedDescription)"
        }
        let elapsed = ContinuousClock.now - started
        report.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return report
    }

    private static func describe(_ readiness: TranscriberReadiness) -> String {
        switch readiness {
        case .ready: return "Ready"
        case .downloadingModel: return "Downloading"
        case .unavailable: return "Not available"
        case .permissionDenied: return "Speech recognition not allowed"
        }
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
            LabeledContent("SpeechTranscriber available", value: report.available ? "Yes" : "No")
            if !report.engine.isEmpty {
                LabeledContent("Engine", value: report.engine)
            }
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
