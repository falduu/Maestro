//
//  AppConfig.swift
//  Configurazione globale + parametri di efficienza.
//

import Foundation

enum AppConfig {

    // MARK: - Identità

    static let appName = "Maestro"

    /// Wake word. Cambia qui per personalizzarla.
    static let wakeWord = "Maestro"
        /// Alternative fonetiche che il recognizer può sentire al posto della wake word.
    static let wakeWordAliases: [String] = ["ma estro", "mastro"]

    /// Se true, il comando è valido solo dopo la wake word.
    static let requiresWakeWord = true

    /// Forza un locale ("it-IT" / "en-US"). Nil = automatico.
    static var preferredSpeechLocale: String? = nil

    // MARK: - Efficienza

    /// Riconoscimento on-device quando supportato: niente rete,
    /// meno energia, più privacy.
    static let preferOnDeviceRecognition = true

    /// Buffer audio grande = meno callback al secondo = meno CPU.
    static let audioBufferSize: Int = 4096

    /// Ritardo base per riavviare il riconoscimento dopo un risultato finale.
    static let restartBaseDelay: Double = 0.4

    /// Tetto al backoff esponenziale in caso di errori ripetuti.
    static let restartMaxDelay: Double = 8.0

    /// Frequenza massima di aggiornamento UI della trascrizione parziale.
    static let transcriptUIThrottle: Double = 0.25

    /// Antirimbalzo comandi duplicati.
    static let commandDebounce: Double = 3.0

    // MARK: - Musica

    /// Fallback sul catalogo Apple Music se la libreria non ha risultati.
    static let allowCatalogFallback = false    /// Se cerco nei preferiti e non trovo nulla, ricado sulla libreria.
    static let fallbackToLibraryIfFavoritesEmpty = true

    /// Parole che identificano le playlist "preferiti".
    static let favoritesPlaylistKeywords: [String] = [
        "preferiti", "preferite", "brani preferiti",
        "favorites", "favorite", "liked", "favoriti"
    ]

    /// Durata cache delle playlist preferiti (evita ricerche ripetute).
    static let favoritesCacheTTL: TimeInterval = 600

    // MARK: - Riconoscimento vocale

    /// Se un parziale resta invariato per questo tempo (secondi), viene
    /// considerato definitivo: risposta più rapida senza attendere il
    /// risultato «finale» nativo.
    static let stablePartialTimeout: TimeInterval = 1.2
}