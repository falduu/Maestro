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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let source = Self.makeScript(query: query, preferredTitle: preferredTitle, playlistName: playlistName)

                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .error("Impossibile preparare lo script AppleScript."))
                    return
                }

                let descriptor = script.executeAndReturnError(&error)

                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 || code == -600 {
                        continuation.resume(returning: .error(
                            "Permesso Automazione negato: abilitalo in Impostazioni di Sistema → Privacy e Sicurezza → Automazione → Maestro → Musica."
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

                let source = "tell application \"Music\"\n\(command)\nreturn \"OK\"\nend tell"

                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .error("Script trasporto non valido."))
                    return
                }

                _ = script.executeAndReturnError(&error)

                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 || code == -600 {
                        continuation.resume(returning: .error(
                            "Permesso Automazione negato: abilitalo in Impostazioni di Sistema → Privacy e Sicurezza → Automazione."
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

    // MARK: - Generazione script

    private static func makeScript(query: String, preferredTitle: String?, playlistName: String?) -> String {
        let q = escape(query)
        let pref = escape(preferredTitle ?? "")
        let plist = escape(playlistName ?? "")

        return """
        tell application "Music"
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
            delay 0.4
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