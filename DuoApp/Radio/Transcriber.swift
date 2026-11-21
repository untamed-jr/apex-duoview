import AVFoundation
import Foundation
import Speech

/// Turns team radio clips into text with iOS's own speech recognition, on the phone only: there
/// is no server fallback and no microphone (it reads the cached clip files).
///
/// - The engine, best first:
///   - `SpeechTranscriber` in a `SpeechAnalyzer`, fed the file with `analyzeSequence(from:)`;
///   - if `SpeechTranscriber.isAvailable` is false (or it has no English): `DictationTranscriber`
///     the same way;
///   - then `SFSpeechRecognizer`, only where it `supportsOnDeviceRecognition`, with
///     `requiresOnDeviceRecognition = true`.
///   - None of them: `.unavailable`, and clips still play.
/// - The locale: `supportedLocale(equivalentTo:)` for en-GB, then en-US.
/// - A missing model is installed through `AssetInventory.assetInstallationRequest(supporting:)`
///   (a system download from Apple, shared by all apps). It runs in the background;
///   `prepare()` reads `.downloadingModel` until it's done, and a failed download is tried again
///   after a minute.
/// - Hints (`AnalysisContext.contextualStrings`, or the recognizer's `contextualStrings`): the
///   session's names and teams and the radio words, from `TranscriptState.hints(drivers:)`.
/// - Permission (whether the analyzers need it is owner check O1):
///   - `SFSpeechRecognizer` needs speech recognition allowed: that engine asks when it isn't
///     decided, and a denial is `.permissionDenied`.
///   - The analyzer engines never ask up front, and a denial alone doesn't stop them. Only an
///     analyzer run that fails while speech recognition is denied gives `.permissionDenied` (until
///     it's allowed again). A failure that says it wasn't authorized, while iOS hasn't been asked,
///     asks once; an Allow tries that clip again.
///   - Every `SFSpeech…` call is in `LegacySpeech`, so a change to those APIs is one place.
/// - Never logs, and keeps nothing but the engine it found.
actor Transcriber: RadioTranscribing {
    /// The engine `prepare()` found.
    enum Engine: Sendable, Equatable {
        case speech(Locale)
        case dictation(Locale)
        case recognizer(Locale)

        var name: String {
            switch self {
            case .speech: return "SpeechTranscriber"
            case .dictation: return "DictationTranscriber"
            case .recognizer: return "SFSpeechRecognizer (on device)"
            }
        }

        var locale: Locale {
            switch self {
            case .speech(let locale), .dictation(let locale), .recognizer(let locale): return locale
            }
        }

        /// It runs in a `SpeechAnalyzer` and has a model in `AssetInventory`.
        var usesAnalyzer: Bool {
            if case .recognizer = self { return false }
            return true
        }
    }

    /// Asked for in this order.
    static let locales = ["en-GB", "en-US"]
    /// How long after a failed model download it is tried again.
    static let installRetry: Duration = .seconds(60)

    private(set) var engine: Engine?
    /// No engine was found: it won't appear while the app runs.
    private var noEngine = false
    private var modelInstalled = false
    private var installing = false
    private var installFailedAt: ContinuousClock.Instant?
    /// An analyzer run failed while speech recognition was denied: held back until it's allowed.
    private var analyzerDenied = false

    /// Ready, or why not. Quick: a model download goes on in the background.
    func prepare() async -> TranscriberReadiness {
        if noEngine { return .unavailable }
        if engine == nil {
            engine = await Self.findEngine()
            if engine == nil { noEngine = true }
        }
        guard let engine else { return .unavailable }
        let permission = LegacySpeech.permission()
        guard engine.usesAnalyzer else {
            switch permission {
            case .allowed: return .ready
            case .denied: return .permissionDenied
            case .notAsked: return await LegacySpeech.askPermission() == .allowed ? .ready : .permissionDenied
            }
        }
        if analyzerDenied {
            if permission == .denied { return .permissionDenied }
            analyzerDenied = false
        }
        if modelInstalled { return .ready }
        if await Self.isModelInstalled(engine) {
            modelInstalled = true
            return .ready
        }
        let due = installFailedAt.map { ContinuousClock.now - $0 >= Self.installRetry } ?? true
        if !installing, due {
            installing = true
            Task.detached(priority: .utility) { [weak self] in
                let ok = await Transcriber.installModel(engine)
                await self?.installEnded(ok: ok)
            }
        }
        return .downloadingModel
    }

    /// The clip's words; blank when nothing was recognised. Throws `TranscriberError` when
    /// transcripts can't run at all, `CancellationError` when cancelled, else the engine's error.
    func transcribe(fileURL: URL, hints: [String]) async throws -> String {
        guard let engine else { throw TranscriberError.unavailable }
        do {
            return try await Self.run(engine, fileURL: fileURL, hints: hints)
        } catch let error as TranscriberError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            switch LegacySpeech.permission() {
            case .denied:
                // Failed with speech recognition turned off for the app: say so.
                if engine.usesAnalyzer { analyzerDenied = true }
                throw TranscriberError.permissionDenied
            case .notAsked where engine.usesAnalyzer && LegacySpeech.isNotAuthorized(error):
                switch await LegacySpeech.askPermission() {
                case .allowed:
                    // Allowed just now: the clip once more, so asking doesn't cost it its turn.
                    return try await Self.run(engine, fileURL: fileURL, hints: hints)
                case .denied:
                    analyzerDenied = true
                    throw TranscriberError.permissionDenied
                case .notAsked:
                    throw error
                }
            default:
                throw error
            }
        }
    }

    private func installEnded(ok: Bool) {
        installing = false
        installFailedAt = ok ? nil : .now
    }

    // MARK: The engines (off any actor; every Speech object is made and used inside one call)

    /// The best engine with English on this phone, or nil.
    @concurrent
    private static func findEngine() async -> Engine? {
        if SpeechTranscriber.isAvailable {
            for identifier in locales {
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
                else { continue }
                if await AssetInventory.status(forModules: [speechModule(locale)]) != .unsupported {
                    return .speech(locale)
                }
            }
        }
        for identifier in locales {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
            else { continue }
            if await AssetInventory.status(forModules: [dictationModule(locale)]) != .unsupported {
                return .dictation(locale)
            }
        }
        for identifier in locales {
            if let locale = LegacySpeech.onDeviceLocale(identifier) { return .recognizer(locale) }
        }
        return nil
    }

    private static func speechModule(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    private static func dictationModule(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                             reportingOptions: [], attributeOptions: [])
    }

    /// A fresh module for an analyzer engine (a module belongs to one analyzer).
    private static func module(for engine: Engine) -> (any SpeechModule)? {
        switch engine {
        case .speech(let locale): return speechModule(locale)
        case .dictation(let locale): return dictationModule(locale)
        case .recognizer: return nil
        }
    }

    @concurrent
    private static func isModelInstalled(_ engine: Engine) async -> Bool {
        guard let module = module(for: engine) else { return true }
        // Compared, not switched, so a status added later needs no `@unknown default`.
        return await AssetInventory.status(forModules: [module]) == .installed
    }

    @concurrent
    private static func installModel(_ engine: Engine) async -> Bool {
        guard let module = module(for: engine) else { return true }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            return true
        } catch {
            return false
        }
    }

    @concurrent
    private static func run(_ engine: Engine, fileURL: URL, hints: [String]) async throws -> String {
        switch engine {
        case .speech(let locale):
            let module = speechModule(locale)
            return try await analyze(module, fileURL: fileURL, hints: hints) {
                try await module.results.reduce(into: "") { text, result in
                    Transcriber.append(String(result.text.characters), to: &text)
                }
            }
        case .dictation(let locale):
            let module = dictationModule(locale)
            return try await analyze(module, fileURL: fileURL, hints: hints) {
                try await module.results.reduce(into: "") { text, result in
                    Transcriber.append(String(result.text.characters), to: &text)
                }
            }
        case .recognizer(let locale):
            return try await LegacySpeech.recognize(locale: locale, fileURL: fileURL, hints: hints)
        }
    }

    private static func append(_ piece: String, to text: inout String) {
        let piece = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }
        text += text.isEmpty ? piece : " " + piece
    }

    /// `module` in a `SpeechAnalyzer` over the file; `words` reads the module's results. The file
    /// is opened before anything waits on the results, and every way out (an error, a
    /// cancellation) finishes the analyzer, so the results end and nothing is left waiting.
    @concurrent
    private static func analyze(_ module: any SpeechModule, fileURL: URL, hints: [String],
                                words: @escaping @Sendable () async throws -> String) async throws -> String {
        let analyzer = SpeechAnalyzer(modules: [module])
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        return try await withTaskCancellationHandler {
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: fileURL)
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
            async let text = words()
            do {
                // The hints only help: an analyzer that won't take them still transcribes.
                try? await analyzer.setContext(context)
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
            return try await text
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

/// Every call into the older Speech API (`SFSpeechRecognizer`, its permission, its URL request and
/// task) in one place, so a change to those APIs in a new SDK is fixed here only.
private enum LegacySpeech {
    /// Speech recognition for the app, as Settings has it.
    enum Permission: Sendable, Equatable {
        case allowed
        /// Denied, or restricted on this phone.
        case denied
        case notAsked
    }

    static func permission() -> Permission {
        permission(SFSpeechRecognizer.authorizationStatus())
    }

    private static func permission(_ status: SFSpeechRecognizerAuthorizationStatus) -> Permission {
        // Compared, not switched, so a status added later needs no `@unknown default`.
        if status == .authorized { return .allowed }
        if status == .denied || status == .restricted { return .denied }
        return .notAsked
    }

    /// Asks iOS for speech recognition (the Info.plist reason says the app never listens).
    @concurrent
    static func askPermission() async -> Permission {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        return permission(status)
    }

    /// Whether an engine's error says speech recognition wasn't authorized: the recognizer's own
    /// "not authorized" (`kAFAssistantErrorDomain` 1700), or a description that says so (Speech
    /// documents no such code for the analyzers). Anything else never raises the prompt.
    static func isNotAuthorized(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == "kAFAssistantErrorDomain", error.code == 1700 { return true }
        return error.localizedDescription.lowercased().contains("authoriz")
    }

    /// The recognizer's locale for `identifier`, when it recognises on the phone; nil otherwise.
    static func onDeviceLocale(_ identifier: String) -> Locale? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
              recognizer.supportsOnDeviceRecognition
        else { return nil }
        return recognizer.locale
    }

    /// The last fallback: `SFSpeechRecognizer` on the file, on the phone only.
    @concurrent
    static func recognize(locale: Locale, fileURL: URL, hints: [String]) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw TranscriberError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = hints
        let recognition = Recognition()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
                guard recognition.begin(continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let task = recognizer.recognitionTask(with: request) { @Sendable result, error in
                    if let error {
                        recognition.finish(.failure(error))
                    } else if let result, result.isFinal {
                        recognition.finish(.success(result.bestTranscription.formattedString))
                    }
                }
                recognition.attach(task, recognizer: recognizer)
            }
        } onCancel: {
            recognition.cancel()
        }
    }
}

/// One `SFSpeechRecognizer` task: its continuation resumes exactly once (the result, an error or
/// a cancellation, whichever comes first), and a cancellation cancels the task.
private final class Recognition: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?
    private var task: SFSpeechRecognitionTask?
    /// Kept alive while the task runs.
    private var recognizer: SFSpeechRecognizer?
    private var cancelled = false

    /// False when already cancelled.
    func begin(_ continuation: CheckedContinuation<String, any Error>) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.continuation = continuation
            return true
        }
    }

    func attach(_ task: SFSpeechRecognitionTask, recognizer: SFSpeechRecognizer) {
        let cancelNow = lock.withLock {
            if cancelled || continuation == nil { return true }
            self.task = task
            self.recognizer = recognizer
            return false
        }
        if cancelNow { task.cancel() }
    }

    func finish(_ result: Result<String, any Error>) {
        let waiting = lock.withLock {
            let waiting = continuation
            continuation = nil
            task = nil
            recognizer = nil
            return waiting
        }
        waiting?.resume(with: result)
    }

    func cancel() {
        let (waiting, running) = lock.withLock {
            cancelled = true
            let taken = (continuation, task)
            continuation = nil
            task = nil
            recognizer = nil
            return taken
        }
        running?.cancel()
        waiting?.resume(throwing: CancellationError())
    }
}

extension RadioController {
    /// The app's transcriber.
    static func defaultTranscriber() -> any RadioTranscribing {
        Transcriber()
    }
}
