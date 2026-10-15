//
//  SpeechManager.swift
//  Ascolto continuo a basso consumo + parser intenti v2 + debug visibile.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: ObservableObject {

    enum PermissionState: Equatable { case unknown, granted, denied }
    enum SpeechError: Error { case noInput }

    private static let permsKey = "maestro.permissions.granted"

    @Published private(set) var isListening = false
    @Published private(set) var statusText = "In attesa"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastCommand: String?
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var errorMessage: String?
    @Published private(set) var parseDebug = ""

    var onIntent: ((VoiceIntent) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?

    private let requestLock = NSLock()
    private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var wantsToListen = false
    private var restartTask: Task<Void, Never>?
    private var consecutiveErrors = 0

    private var lastTriggeredKey: String?
    private var lastTriggeredDate = Date.distantPast
    private var lastUIPublish = Date.distantPast

    private var lastPartialText = ""
    private var lastPartialSeen = Date.distantPast

    // MARK: - Avvio / arresto

    func requestPermissionsAndStart() async {
        wantsToListen = true
        setError(nil)

        // Percorso veloce: permessi già concessi in passato → niente attese.
        if UserDefaults.standard.bool(forKey: Self.permsKey) {
            permissionState = .granted
            beginRecognition()
            return
        }

        setStatus("Verifica permessi...")

        let micGranted = await requestMicrophonePermission()
        let speechStatus = await requestSpeechPermission()

        guard micGranted else {
            permissionState = .denied
            UserDefaults.standard.set(false, forKey: Self.permsKey)
            wantsToListen = false
            setStatus("Microfono non autorizzato")
            setError("Abilita il microfono in Impostazioni di Sistema → Privacy e Sicurezza.")
            return
        }

        guard speechStatus == .authorized else {
            permissionState = .denied
            UserDefaults.standard.set(false, forKey: Self.permsKey)
            wantsToListen = false
            setStatus("Riconoscimento vocale non autorizzato")
            setError("Abilita il riconoscimento vocale in Impostazioni di Sistema → Privacy e Sicurezza.")
            return
        }

        permissionState = .granted
        UserDefaults.standard.set(true, forKey: Self.permsKey)
        beginRecognition()
    }

    func stopListening() {
        wantsToListen = false
        restartTask?.cancel()
        restartTask = nil
        endCurrentRecognition()
        audioEngine?.stop()
        setListening(false)
        setStatus("Inattivo")
    }

    // MARK: - Permessi

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
    }

    // MARK: - Engine audio (una sola volta)

    private func startEngineIfNeeded() throws {
        if let engine = audioEngine {
            if !engine.isRunning { try engine.start() }
            return
        }

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.noInput
        }

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(AppConfig.audioBufferSize),
            format: format
        ) { [weak self] buffer, _ in
            guard let self else { return }
            self.requestLock.lock()
            let request = self.activeRequest
            self.requestLock.unlock()
            request?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    // MARK: - Riconoscimento

    private func cachedRecognizer() -> SFSpeechRecognizer? {
        if let recognizer { return recognizer }

        if let preferred = AppConfig.preferredSpeechLocale,
           let r = SFSpeechRecognizer(locale: Locale(identifier: preferred)),
           r.isAvailable {
            recognizer = r
            return r
        }

        let language = Locale.preferredLanguages.first ?? Locale.current.identifier
        let candidates: [String] = language.lowercased().hasPrefix("en")
            ? ["en-US", "it-IT"]
            : ["it-IT", "en-US"]

        for id in candidates {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable {
                recognizer = r
                return r
            }
        }
        return nil
    }

    private func beginRecognition() {
        guard wantsToListen else { return }

        do {
            try startEngineIfNeeded()
        } catch {
            setStatus("Errore microfono")
            setError("Input audio non disponibile: \(error.localizedDescription)")
            wantsToListen = false
            return
        }

        guard let recognizer = cachedRecognizer(), recognizer.isAvailable else {
            setStatus("Riconoscitore non disponibile")
            setError("SFSpeechRecognizer non disponibile per la lingua corrente.")
            wantsToListen = false
            return
        }

        endCurrentRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .search
        request.contextualStrings = [
            AppConfig.wakeWord, "riproduci", "play", "pausa",
            "riprendi", "prossima", "precedente", "esci", "preferiti"
        ]

        if AppConfig.preferOnDeviceRecognition, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        requestLock.lock()
        activeRequest = request
        requestLock.unlock()

        setListening(true)
        setStatus("In ascolto")
        setError(nil)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func endCurrentRecognition() {
        requestLock.lock()
        activeRequest = nil
        requestLock.unlock()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString

            if result.isFinal {
                consecutiveErrors = 0
                lastTranscript = text
                handleFinalTranscript(text, source: "finale")
                scheduleRestart(delay: AppConfig.restartBaseDelay)
            } else {
                publishTranscriptThrottled(text)
                handleStablePartial(text)
            }
        }

        if error != nil {
            consecutiveErrors += 1
            if consecutiveErrors >= 3 {
                setError("Riconoscimento instabile: nuovo tentativo con backoff.")
            }
            scheduleRestart(delay: backoffDelay())
        }
    }

    private func handleStablePartial(_ text: String) {
        let now = Date()
        if text == lastPartialText {
            guard now.timeIntervalSince(lastPartialSeen) >= 1.0 else { return }
            lastPartialText = ""
            handleFinalTranscript(text, source: "parziale stabile")
        } else {
            lastPartialText = text
            lastPartialSeen = now
        }
    }

    private func backoffDelay() -> Double {
        let exponent = min(Double(consecutiveErrors), 5)
        return min(AppConfig.restartBaseDelay * pow(2, exponent), AppConfig.restartMaxDelay)
    }

    private func scheduleRestart(delay: Double) {
        guard wantsToListen else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.beginRecognition()
        }
    }

    private func publishTranscriptThrottled(_ text: String) {
        let now = Date()
        guard now.timeIntervalSince(lastUIPublish) >= AppConfig.transcriptUIThrottle else { return }
        lastUIPublish = now
        lastTranscript = text
    }

    // MARK: - Parsing intenti v2

    private func handleFinalTranscript(_ transcript: String, source: String) {
        let intent = extractIntent(from: transcript)

        guard intent != .none else {
            parseDebug = "\(source): «\(transcript)» → scartata (serve «\(AppConfig.wakeWord)» + comando)"
            return
        }

        let now = Date()
        let key = intentKey(intent)
        if key == lastTriggeredKey,
           now.timeIntervalSince(lastTriggeredDate) < AppConfig.commandDebounce {
            return
        }
        lastTriggeredKey = key
        lastTriggeredDate = now

        let label = intentDescription(intent)
        lastCommand = label
        setStatus("Comando: \(label)")
        parseDebug = "\(source): «\(transcript)» → \(label)"
        onIntent?(intent)
    }

    private func intentKey(_ intent: VoiceIntent) -> String {
        switch intent {
        case .play(let c): return "play::\(c.scope.rawValue)::\(c.title)"
        default: return "\(intent)"
        }
    }

    private func intentDescription(_ intent: VoiceIntent) -> String {
        switch intent {
        case .play(let c):
            return c.scope == .favorites ? "\(c.title) [Preferiti]" : c.title
        case .pause: return "pausa"
        case .resume: return "riprendi"
        case .next: return "prossima"
        case .previous: return "precedente"
        case .quit: return "esci"
        case .none: return "-"
        }
    }

    private func extractIntent(from transcript: String) -> VoiceIntent {
        let tokens = normalizeText(transcript).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return .none }

        let aliases = [AppConfig.wakeWord] + AppConfig.wakeWordAliases
        var wakeEnd: Int? = nil
        for alias in aliases {
            let aliasTokens = normalizeText(alias).split(separator: " ").map(String.init)
            if let end = findSequence(aliasTokens, in: tokens) {
                wakeEnd = end
                break
            }
        }

        var searchStart = 0
        if AppConfig.requiresWakeWord {
            guard let end = wakeEnd else { return .none }
            searchStart = end
        } else if let end = wakeEnd {
            searchStart = end
        }

        var index = searchStart
        while index < tokens.count {
            // 1) Frasi di trasporto/uscita (le più lunghe vincono)
            if let (intent, _) = matchPhrase(at: index, tokens: tokens) {
                return intent
            }

            // 2) Verbi di riproduzione, con titolo dopo
            if let len = matchPlayVerb(at: index, tokens: tokens) {
                let cleaned = cleanTitleTokens(Array(tokens[(index + len)...]))
                if cleaned.title.isEmpty { return .resume }
                return .play(TrackCommand(title: cleaned.title, scope: cleaned.scope))
            }

            index += 1
        }

        return .none
    }

    private static let phraseIntents: [([String], VoiceIntent)] = [
        (["metti", "in", "pausa"], .pause),
        (["vai", "in", "pausa"], .pause),
        (["riprendi", "la", "riproduzione"], .resume),
        (["prossimo", "brano"], .next),
        (["prossima", "canzone"], .next),
        (["brano", "precedente"], .previous),
        (["torna", "indietro"], .previous),
        (["pausa"], .pause),
        (["stop"], .pause),
        (["riprendi"], .resume),
        (["continua"], .resume),
        (["resume"], .resume),
        (["prossima"], .next),
        (["successiva"], .next),
        (["next"], .next),
        (["precedente"], .previous),
        (["previous"], .previous),
        (["esci"], .quit),
        (["quit"], .quit),
        (["exit"], .quit),
        (["chiuditi"], .quit),
        (["chiudi"], .quit),
        (["spegniti"], .quit)
    ]

    private func matchPhrase(at index: Int, tokens: [String]) -> (VoiceIntent, Int)? {
        for (phrase, intent) in Self.phraseIntents {
            if index + phrase.count <= tokens.count,
               Array(tokens[index..<index + phrase.count]) == phrase {
                return (intent, phrase.count)
            }
        }
        return nil
    }

    private static let playVerbs: [[String]] = [
        ["fai", "partire"], ["fai", "riprodurre"], ["metti", "su"],
        ["riproduci"], ["play"], ["suona"], ["metti"], ["ascolta"], ["avvia"], ["esegui"]
    ]

    private func matchPlayVerb(at index: Int, tokens: [String]) -> Int? {
        for verb in Self.playVerbs {
            if index + verb.count <= tokens.count,
               Array(tokens[index..<index + verb.count]) == verb {
                return verb.count
            }
        }
        return nil
    }

    private func cleanTitleTokens(_ input: [String]) -> (title: String, scope: MusicSearchScope) {
        var titleTokens = input
        var scope: MusicSearchScope = .allLibrary

        let favoriteSuffixes: [[String]] = [
            ["che", "trovi", "nei", "miei", "brani", "preferiti"],
            ["che", "trovi", "tra", "i", "miei", "brani", "preferiti"],
            ["che", "trovi", "nei", "miei", "preferiti"],
            ["che", "trovi", "tra", "i", "miei", "preferiti"],
            ["che", "trovi", "nei", "preferiti"],
            ["che", "trovi", "tra", "i", "preferiti"],
            ["che", "trovi", "dai", "miei", "preferiti"],
            ["che", "trovi", "in", "my", "favorites"],
            ["che", "trovi", "from", "favorites"],
            ["nei", "miei", "brani", "preferiti"],
            ["tra", "i", "miei", "brani", "preferiti"],
            ["nei", "miei", "preferiti"],
            ["tra", "i", "miei", "preferiti"],
            ["dai", "miei", "preferiti"],
            ["nei", "brani", "preferiti"],
            ["tra", "i", "preferiti"],
            ["nei", "preferiti"],
            ["in", "my", "favorites"],
            ["from", "favorites"],
            ["in", "favorites"],
            ["preferiti"],
            ["favoriti"],
            ["favorites"],
            ["favorite"],
            ["liked"]
        ]

        for suffix in favoriteSuffixes.sorted(by: { $0.count > $1.count }) {
            if titleTokens.count >= suffix.count,
               Array(titleTokens.suffix(suffix.count)) == suffix {
                titleTokens.removeLast(suffix.count)
                scope = .favorites
                break
            }
        }

        while titleTokens.count >= 2,
              Array(titleTokens.suffix(2)) == ["che", "trovi"] {
            titleTokens.removeLast(2)
        }

        let fillerStarts: [[String]] = [
            ["il", "brano"], ["la", "canzone"], ["lo", "brano"],
            ["un", "brano"], ["una", "canzone"],
            ["brano"], ["canzone"], ["song"], ["track"], ["musica"]
        ]

        for filler in fillerStarts where titleTokens.starts(with: filler) {
            titleTokens.removeFirst(filler.count)
            break
        }

        let trailingStopWords: Set<String> = [
            "per", "favore", "please", "ora", "adesso", "now",
            "grazie", "thanks", "ehi", "hey",
            "brano", "canzone", "traccia", "song", "track",
            "trovi", "nei", "tra", "dai", "nella", "nel"
        ]

        while let last = titleTokens.last, trailingStopWords.contains(last) {
            titleTokens.removeLast()
        }

        let title = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title, scope)
    }

    private func normalizeText(_ text: String) -> String {
        let folded = text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale.current)

        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)

        return folded
            .components(separatedBy: allowed.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func findSequence(_ sequence: [String], in tokens: [String]) -> Int? {
        guard !sequence.isEmpty else { return 0 }
        guard tokens.count >= sequence.count else { return nil }

        for start in 0...(tokens.count - sequence.count) {
            var found = true
            for offset in 0..<sequence.count where tokens[start + offset] != sequence[offset] {
                found = false
                break
            }
            if found { return start + sequence.count }
        }
        return nil
    }

    // MARK: - Helper UI

    private func setStatus(_ value: String) {
        if statusText != value { statusText = value }
    }

    private func setListening(_ value: Bool) {
        if isListening != value { isListening = value }
    }

    private func setError(_ value: String?) {
        if errorMessage != value { errorMessage = value }
    }
}