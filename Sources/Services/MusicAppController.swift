//
//  MusicAppController.swift
//  Bridge verso Musica.app (su macOS SystemMusicPlayer non esiste).
//  Una sola esecuzione AppleScript per chiamata, con catena di match:
//  titolo esatto → contiene titolo → contiene query parziale → libreria.
//  Verifica reale dello stato di riproduzione (niente più falsi successi).
//

import Foundation

final class MusicAppController: Sendable {

    enum PlayResult: Equatable {
        case played(String)
        case notFound
        case playFailed(String)
        case error(String)
    }

    func play(query: String, preferredTitle: String?, inPlaylist playlistName: String?) async -> PlayResult {
        // v0.3: script compilato una sola volta e riusato dalla cache
        // (fa a tempo ~50-200ms di compilazione AppleScript per comando).
        let key = ScriptCache.key(query: query, preferred: preferredTitle ?? "", playlist: playlistName ?? "")

        return await withCheckedContinuation { (continuation: CheckedContinuation<PlayResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = ScriptCache.shared.script(for: key, source: {
                    Self.makeScript(query: query, preferredTitle: preferredTitle, playlistName: playlistName)
                }) else {
                    continuation.resume(returning: PlayResult.error("Impossibile preparare lo script AppleScript."))
                    return
                }

                var error: NSDictionary?

                let descriptor = script.executeAndReturnError(&error)

                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 {
                        continuation.resume(returning: .error(
                            "Permesso Automazione negato: abilitalo in Impostazioni di Sistema → Privacy e Sicurezza → Automazione → Maestro → Musica."
                        ))
                    } else if code == -600 {
                        continuation.resume(returning: .error(
                            "Impossibile avviare Musica.app. Verifica che sia installata e riprova."
                        ))
                    } else {
                        let message = error[NSAppleScript.errorMessage] as? String ?? "errore sconosciuto"
                        continuation.resume(returning: .error("Apple Events (\(code)): \(message)"))
                    }
                    return
                }

                let output = descriptor.stringValue ?? ""

                if output == "NOTFOUND" {
                    continuation.resume(returning: .notFound)
                } else if output.hasPrefix("PLAYFAILED|") {
                    continuation.resume(returning: .playFailed(String(output.dropFirst("PLAYFAILED|".count))))
                } else {
                    continuation.resume(returning: .played(output))
                }
            }
        }
    }

        // MARK: - Trasporto (pausa / ripresa / salta)

    enum TransportResult: Equatable {
        case ok
        case error(String)
    }

    func transport(_ action: TransportAction) async -> TransportResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let command: String
                switch action {
                case .pause: command = "pause"
                case .resume: command = "play"
                case .next: command = "next track"
                case .previous: command = "previous track"
                }

                let source = "tell application \"Music\"\nlaunch\n\(command)\nreturn \"OK\"\nend tell"

                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .error("Script trasporto non valido."))
                    return
                }

                _ = script.executeAndReturnError(&error)

                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 {
                        continuation.resume(returning: .error(
                            "Permesso Automazione negato: abilitalo in Impostazioni di Sistema → Privacy e Sicurezza → Automazione."
                        ))
                    } else if code == -600 {
                        continuation.resume(returning: .error(
                            "Impossibile avviare Musica.app. Verifica che sia installata e riprova."
                        ))
                    } else {
                        let message = error[NSAppleScript.errorMessage] as? String ?? "errore sconosciuto"
                        continuation.resume(returning: .error("Apple Events (\(code)): \(message)"))
                    }
                    return
                }

                continuation.resume(returning: .ok)
            }
        }
    }

    // MARK: - Stato del player

    /// Nome del brano attualmente caricato nel player (vuoto se nessun brano).
    /// Usato dal "resume intelligente" per non spezzare la cronologia.
    func currentTrackName() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let source = """
                tell application "Music"
                    launch
                    try
                        return name of current track
                    on error
                        return ""
                    end try
                end tell
                """
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result.stringValue ?? "")
                }
            }
        }
    }

    // MARK: - Generazione script

    private static func makeScript(query: String, preferredTitle: String?, playlistName: String?) -> String {
        let q = escape(query)
        let pref = escape(preferredTitle ?? "")
        let plist = escape(playlistName ?? "")

        return """
        tell application "Music"
            launch
            set cont to missing value
            if "\(plist)" is not "" then
                try
                    set cont to first playlist whose name is "\(plist)"
                end try
            end if
            if cont is missing value then set cont to library playlist 1

            set cands to {}
            if "\(pref)" is not "" then
                try
                    set cands to (every track of cont whose name is "\(pref)")
                end try
            end if
            if (count of cands) is 0 and "\(pref)" is not "" then
                try
                    set cands to (every track of cont whose name contains "\(pref)")
                end try
            end if
            if (count of cands) is 0 then
                try
                    set cands to (every track of cont whose name is "\(q)")
                end try
            end if
            if (count of cands) is 0 then
                try
                    set cands to (every track of cont whose name contains "\(q)")
                end try
            end if
            if (count of cands) is 0 and "\(plist)" is not "" then
                try
                    set cands to (every track of library playlist 1 whose name contains "\(q)")
                end try
            end if
            if (count of cands) is 0 then return "NOTFOUND"

            set t to item 1 of cands
            play t
            set n to 0
            repeat while n < 12
                if player state is playing then exit repeat
                delay 0.15
                set n to n + 1
            end repeat
            if player state is not playing then return "PLAYFAILED|" & (name of t)
            return name of t
        end tell
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Cache script compilati

/// NSAppleScript la compilazione è lenta (~50-200ms): con una query che si
/// ripete (tipico dei comandi vocali) riusiamo lo script già compilato.
final class ScriptCache: @unchecked Sendable {
    static let shared = ScriptCache()

    private var cache: [String: NSAppleScript] = [:]
    private let lock = NSLock()
    private let maxEntries = 40

    static func key(query: String, preferred: String, playlist: String) -> String {
        "\(playlist)::\(preferred)::\(query)"
    }

    func script(for key: String, source: () -> String) -> NSAppleScript? {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let script = NSAppleScript(source: source()) else { return nil }

        lock.lock()
        if cache.count >= maxEntries { cache.removeAll(keepingCapacity: true) }
        cache[key] = script
        lock.unlock()
        return script
    }
}