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
    private static let lastPlayCommandKey = "maestro.lastPlayCommand"

    @Published private(set) var isListening = false
    @Published private(set) var statusText = "In attesa"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastCommand: String?
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var errorMessage: String?
    @Published private(set) var parseDebug = ""
    /// Ultimo comando riproduci eseguito: serve a «riprendi» per ripartire
    /// dallo stesso brano/contesto senza ricominciare una nuova cronologia.
    @Published private(set) var lastPlayCommand: TrackCommand?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.lastPlayCommandKey) {
            lastPlayCommand = try? JSONDecoder().decode(TrackCommand.self, from: data)
        }
    }

    var onIntent: ((VoiceIntent) -> Void)?

    /// Suggerimento contestuale per il riconoscitore (brano in riproduzione).
    var musicNowPlayingHint: String?

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
    /// Playlist estratta dal lessico durante l'ultimo parsing («nella playlist X»).
    private var playlistOverride: String?

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
        // v0.3: contesto lessicale + brano in riproduzione/ultimo comando,
        // così il riconoscitore "indovina" meglio le parole che userai davvero.
        var contextual: [String] = [AppConfig.wakeWord]
        if let nowPlaying = musicNowPlayingHint { contextual.append(nowPlaying) }
        if let last = lastPlayCommand { contextual.append(last.title) }
        contextual += IntentLexicon.allCommandWords
        var seenContext = Set<String>()
        request.contextualStrings = contextual
            .filter { seenContext.insert($0).inserted }
            .prefix(60)
            .map { $0 }

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

        if let error {
            let nsErr = error as NSError
            let isNoSpeech = nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 216

            // 216 = nessun parlato rilevato: NON è un guasto. Riavvio immediato
            // senza backoff (evita la finestra di silenzio in cui i comandi
            // detti subito dopo non vengono captati).
            if isNoSpeech {
                scheduleRestart(delay: 0.05)
                return
            }

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
            guard now.timeIntervalSince(lastPartialSeen) >= AppConfig.stablePartialTimeout else { return }
            lastPartialText = ""
            // Ferma il task e usa il parziale come risultato definitivo:
            // risposta più rapida rispetto all'attesa del «finale» nativo.
            endCurrentRecognition()
            handleFinalTranscript(text, source: "parziale stabile")
            scheduleRestart(delay: AppConfig.restartBaseDelay)
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

    // MARK: - Dispatch del comando riconosciuto

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

        // Ricorda l'ultimo «riproduci»: serve per riprendere lo stesso contesto.
        if case .play(let command) = intent {
            lastPlayCommand = command
            if let data = try? JSONEncoder().encode(command) {
                UserDefaults.standard.set(data, forKey: Self.lastPlayCommandKey)
            }
        }

        let label = intentDescription(intent)
        lastCommand = label
        setStatus("Comando: \(label)")
        parseDebug = "\(source): «\(transcript)» → \(label)"
        onIntent?(intent)
    }

    private func intentKey(_ intent: VoiceIntent) -> String {
        switch intent {
        case .play(let c):
            return "play::\(c.scope.rawValue)::\(c.playlistName ?? "")::\(c.title)"
        default:
            return "\(intent)"
        }
    }

    private func intentDescription(_ intent: VoiceIntent) -> String {
        switch intent {
        case .play(let c):
            switch c.scope {
            case .favorites: return "\(c.title) [Preferiti]"
            case .playlist:  return "\(c.title) [Playlist: \(c.playlistName ?? "?")]"
            case .allLibrary: return c.title
            }
        case .pause: return "pausa"
        case .resume: return "riprendi"
        case .next: return "prossima"
        case .previous: return "precedente"
        case .quit: return "esci"
        case .none: return "-"
        }
    }

    // MARK: - Parsing intenti v3 (lessico IntentLexicon)

    private func extractIntent(from transcript: String) -> VoiceIntent {
        let tokens = TextNormalizer.tokenize(transcript)
        guard !tokens.isEmpty else { return .none }

        var wakeEnd: Int? = nil
        for alias in [AppConfig.wakeWord] + AppConfig.wakeWordAliases + IntentLexicon.wakeWordAliases {
            let aliasTokens = TextNormalizer.tokenize(alias)
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

        playlistOverride = nil
        var index = searchStart
        while index < tokens.count {
            // Salta prefissi di cortesia («maestro per favore riproduci…»)
            if let skipped = matchPoliteness(at: index, tokens: tokens) {
                index += skipped
                continue
            }

            // 1) Frasi di trasporto/uscita (le più lunghe vincono)
            if let (intent, _) = matchTransportPhrase(at: index, tokens: tokens) {
                return intent
            }

            // 2) Verbi di riproduzione, con titolo dopo
            if let len = matchPlayVerb(at: index, tokens: tokens) {
                let cleaned = cleanTitleTokens(Array(tokens[(index + len)...]))
                if cleaned.title.isEmpty && playlistOverride == nil { return .resume }
                var command = TrackCommand(title: cleaned.title, scope: cleaned.scope)
                if let pl = playlistOverride {
                    command = TrackCommand(title: cleaned.title, scope: .playlist, playlistName: pl)
                }
                return .play(command)
            }

            index += 1
        }

        return .none
    }

    private func matchPoliteness(at index: Int, tokens: [String]) -> Int? {
        for phrase in Self.politenessSorted {
            if matches(phrase, at: index, in: tokens) { return phrase.count }
        }
        return nil
    }

    private static func lexiconTokens(_ phrase: [String]) -> [String] {
        phrase.flatMap { $0 == "*" ? ["*"] : TextNormalizer.tokenize($0) }
    }

    /// Frasi del lessico pre-ordinate dalla più lunga alla più corta:
    /// così «prossimo brano» vince sempre su «prossimo».
    private static let transportPhrases: [([String], VoiceIntent)] = {
        var all: [([String], VoiceIntent)] = []
        all += IntentLexicon.pausePhrases.map { (lexiconTokens($0), .pause) }
        all += IntentLexicon.resumePhrases.map { (lexiconTokens($0), .resume) }
        all += IntentLexicon.nextPhrases.map { (lexiconTokens($0), .next) }
        all += IntentLexicon.previousPhrases.map { (lexiconTokens($0), .previous) }
        all += IntentLexicon.quitPhrases.map { (lexiconTokens($0), .quit) }
        return all.sorted { $0.0.count > $1.0.count }
    }()

    private static let politenessSorted: [[String]] =
        IntentLexicon.politenessPrefixes.map(lexiconTokens).sorted { $0.count > $1.count }

    private static let playVerbsSorted: [[String]] =
        IntentLexicon.playVerbs.map(lexiconTokens).sorted { $0.count > $1.count }

    private static let favoritesSuffixesSorted: [[String]] =
        IntentLexicon.favoritesPhrases
            .filter { !$0.contains("*") }
            .map(lexiconTokens)
            .sorted { $0.count > $1.count }

    private static let favoritesPrefixesSorted: [[String]] =
        IntentLexicon.favoritesPhrases
            .filter { $0.last == "*" }
            .map { lexiconTokens(Array($0.dropLast())) + ["*"] }
            .sorted { $0.count > $1.count }

    private static let playlistMarkersSorted: [[String]] =
        IntentLexicon.playlistMarkers.map(lexiconTokens).sorted { $0.count > $1.count }

    private static let titleFillersSorted: [[String]] =
        IntentLexicon.titleFillerStarts.map(lexiconTokens).sorted { $0.count > $1.count }

    private func matchTransportPhrase(at index: Int, tokens: [String]) -> (VoiceIntent, Int)? {
        for (phrase, intent) in Self.transportPhrases {
            if matches(phrase, at: index, in: tokens) {
                return (intent, phrase.count)
            }
        }
        return nil
    }

    private func matches(_ phrase: [String], at index: Int, in tokens: [String]) -> Bool {
        guard !phrase.isEmpty, index + phrase.count <= tokens.count else { return false }
        return Array(tokens[index..<index + phrase.count]) == phrase
    }

    private func matchPlayVerb(at index: Int, tokens: [String]) -> Int? {
        for verb in Self.playVerbsSorted {
            if matches(verb, at: index, in: tokens) { return verb.count }
        }
        return nil
    }

    private func cleanTitleTokens(_ input: [String]) -> (title: String, scope: MusicSearchScope) {
        var titleTokens = input
        var scope: MusicSearchScope = .allLibrary

        // Scope "preferiti": suffisso («… nei miei preferiti») o prefisso
        // («nei preferiti …»).
        for phrase in Self.favoritesSuffixesSorted {
            if titleTokens.count >= phrase.count,
               Array(titleTokens.suffix(phrase.count)) == phrase {
                titleTokens.removeLast(phrase.count)
                scope = .favorites
                break
            }
        }

        if scope == .allLibrary {
            for phrase in Self.favoritesPrefixesSorted where matches(Array(phrase.dropLast()), at: 0, in: titleTokens) {
                titleTokens.removeFirst(phrase.count - 1)
                scope = .favorites
                break
            }
        }

        // Playlist esplicita: «<titolo> nella playlist <nome>».
        outer: for marker in Self.playlistMarkersSorted {
            guard titleTokens.count > marker.count else { continue }
            for start in 0...(titleTokens.count - marker.count) {
                if matches(marker, at: start, in: titleTokens) {
                    let nameTokens = Array(titleTokens[(start + marker.count)...])
                    titleTokens = Array(titleTokens[0..<start])
                    if !nameTokens.isEmpty {
                        playlistOverride = nameTokens.joined(separator: " ")
                    }
                    break outer
                }
            }
        }

        while titleTokens.count >= 2,
              Array(titleTokens.suffix(2)) == ["che", "trovi"] {
            titleTokens.removeLast(2)
        }

        for filler in Self.titleFillersSorted where matches(filler, at: 0, in: titleTokens) {
            titleTokens.removeFirst(filler.count)
            break
        }

        while let last = titleTokens.last,
              IntentLexicon.titleTrailingStopwords.contains(last) {
            titleTokens.removeLast()
        }

        let title = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title, scope)
    }

    private func normalizeText(_ text: String) -> String {
        TextNormalizer.normalize(text)
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
    // MARK: - Riconoscimento vocale
    static let stablePartialTimeout: TimeInterval = 1.2 
}