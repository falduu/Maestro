//
//  IntentLexicon.swift
//  Vocabolario centrale degli intenti (v0.3): sinonami e varianti fonetiche
//  per ogni azione. Unico punto in cui aggiungere/esportare espressioni.
//
//  Struttura:
//   - lessico per INTENTO (play, pause, resume, next, previous, quit)
//   - prefissi di SCOPO (preferiti / playlist / album / artista)
//   - filler da rimuovere dal titolo (stopword, cortesie, "il brano", ...)
//   - alias della wake word
//   - dizionario fonetico: corregge gli errori tipici del riconoscitore
//     ("a me stro" → "maestro", "riproduci" storpiato → "riproduci")
//
//  Tutte le liste sono normalizzate lowercase senza punteggiatura:
//  il parser confronta token già passati da TextNormalizer.
//

import Foundation

enum IntentLexicon {

    // MARK: - Wake word

    /// Varianti che il riconoscitore può produrre al posto di «Maestro».
    static let wakeWordAliases: [String] = [
        "maestro", "ma estro", "mastro", "mastro", "meistro", "estro",
        "maestro di musica", "maitro", "mainstro"
    ]

    // MARK: - Verbi di riproduzione (play + titolo)

    /// Sinonimi reggenti: «<verbo> <titolo> [scope]».
    static let playVerbs: [[String]] = [
        // italiano
        ["riproduci"], ["riprodurre"], ["riproducimi"], ["suona"], ["suonami"],
        ["metti"], ["metterei"], ["messi"], ["mettimi"], ["metti su"],
        ["fai partire"], ["fammi partire"], ["fa partire"], ["fai riprodurre"],
        ["fammi sentire"], ["fai sentire"], ["ascolta"], ["ascoltiamo"],
        ["avvia"], ["avviaci"], ["esegui"], ["executivi"], ["partire con"],
        ["dammi"], ["vorrei"], ["voglio"], ["vuoi"], ["possiamo"],
        ["accendi"], ["carica"], ["cerca"], ["trova"], ["giochiamo con"],
        // inglese
        ["play"], ["playing"], ["put on"], ["queue"], ["queue up"],
        ["start"], ["resume playing"], ["listen to"], ["hear"]
    ]

    /// Prefissi di cortesia/filler rimossi prima del verbo.
    static let politenessPrefixes: [[String]] = [
        ["per favore"], ["perpiacere"], ["per piacere"], ["please"],
        ["grazie"], ["prego"], ["ehi"], ["hey"], ["ciao"], ["ok"],
        ["adesso"], ["ora"], ["subito"], ["now"], ["dai"], ["sentiamo"],
        ["vediamo"], ["prova a"], ["provare a"], ["puoi"], ["potresti"],
        ["riusci a"], ["riesci a"]
    ]

    // MARK: - Scope: preferiti

    /// Suffissi/prefissi che indicano i preferiti.
    static let favoritesPhrases: [[String]] = [
        // suffissi italiani
        ["che trovi nei miei brani preferiti"], ["che trovi tra i miei brani preferiti"],
        ["che trovi nei miei preferiti"], ["che trovi tra i miei preferiti"],
        ["che trovi dai miei preferiti"], ["che trovi nei preferiti"],
        ["che trovi tra i preferiti"], ["che trovi sui preferiti"],
        ["che trovi nelle preferite"], ["nei miei brani preferiti"],
        ["tra i miei brani preferiti"], ["sui miei brani preferiti"],
        ["nei miei preferiti"], ["tra i miei preferiti"], ["dai miei preferiti"],
        ["dei miei preferiti"], ["nei brani preferiti"], ["tra i brani preferiti"],
        ["nelle mie preferiti"], ["nei preferiti"], ["tra i preferiti"],
        ["dai preferiti"], ["dei preferiti"], ["sui preferiti"],
        ["in preferiti"], ["nelle preferiti"],
        // forme singole e storpiature
        ["preferiti"], ["preferite"], ["preferit"], ["favoriti"], ["favorite"],
        ["favorites"], ["liked"], ["like"], ["my favorites"], ["in my favorites"],
        ["from favorites"], ["from my favorites"], ["in favorites"],
        // prefissi («nei preferiti <titolo>»)
        ["nei miei preferiti", "*"], ["tra i miei preferiti", "*"],
        ["nei preferiti", "*"], ["tra i preferiti", "*"], ["dai preferiti", "*"],
        ["from favorites", "*"], ["from my favorites", "*"], ["in my favorites", "*"]
    ]

    /// True se la sequenza di token è un'espressione "preferiti".
    static func isFavoritesPhrase(_ tokens: [String]) -> Bool {
        favoritesPhrases.contains { $0 == tokens }
    }

    // MARK: - Scope: playlist / album / artista

    /// Marcatore esplicito di playlist: «play <titolo> nella playlist <nome>».
    static let playlistMarkers: [[String]] = [
        ["nella playlist"], ["nella mia playlist"], ["in playlist"], ["su playlist"],
        ["sulla playlist"], ["dalla playlist"], ["from playlist"], ["in the playlist"],
        ["in playlist"], ["inside playlist"]
    ]

    /// Marcatore artista: «<titolo> di <artista>» / «by <artista>».
    static let artistMarkers: [[String]] = [
        ["di"], ["del"], ["della"], ["dei"], ["degli"], ["delle"],
        ["by"], ["of"], ["cantata da"], ["interpretata da"], ["traccia di"]
    ]

    // MARK: - Trasporto: pausa

    static let pausePhrases: [[String]] = [
        ["metti in pausa"], ["vai in pausa"], ["mettiamoci in pausa"],
        ["pausa"], [" pausa"], ["stai in pausa"], ["blocca"], ["blocca la musica"],
        ["blocca la riproduzione"], ["ferma"], ["ferma la musica"],
        ["ferma la riproduzione"], ["stop"], ["stoppa"], ["smettila"],
        ["smetti"], ["silenzio"], ["ammuttolisci"], ["mute"],
        ["pausa la musica"], ["sospendi"], ["sospendi la riproduzione"],
        ["halt"], ["pause"], ["put it on pause"], ["shut up"]
    ]

    // MARK: - Trasporto: ripresa

    static let resumePhrases: [[String]] = [
        ["riprendi la riproduzione"], ["riprendi la musica"], ["riprendi"],
        ["riprendi"], ["ripristina"], ["continua"], ["continua la musica"],
        ["continua la riproduzione"], ["manda avanti"], ["rimetti"],
        ["rimetti su"], ["rimetti la musica"], ["riavvia"], ["riavvia la musica"],
        ["return"], ["resume"], ["keep playing"], ["go on"], ["carry on"],
        ["unpause"], ["togli la pausa"], ["leva la pausa"], ["via la pausa"]
    ]

    // MARK: - Trasporto: successivo

    static let nextPhrases: [[String]] = [
        ["prossimo brano"], ["prossima canzone"], ["brano successivo"],
        ["canzone successiva"], ["passa al prossimo"], ["passa alla prossima"],
        ["passa al brano successivo"], ["salta al prossimo"], ["salta alla prossima"],
        ["salta brano"], ["salta"], ["avanti"], ["avanti cosi"], ["avanti questo"],
        ["prossimo"], ["prossima"], ["successivo"], ["successiva"], ["next"],
        ["skip"], ["skip this"], ["next track"], ["next song"], ["forward"],
        ["vai avanti"], ["andate avanti"], ["un altro"], ["unaltra"], ["altra"],
        ["ne voglio un altro"], ["sentiamone un altro"]
    ]

    // MARK: - Trasporto: precedente

    static let previousPhrases: [[String]] = [
        ["brano precedente"], ["canzone precedente"], ["torna indietro"],
        ["torna al brano precedente"], ["torna alla canzone precedente"],
        ["torna Indietro"], ["indietro"], ["precedente"], ["previous"],
        ["previous track"], ["previous song"], ["back"], ["go back"],
        ["ultimo brano"], ["l ultimo"], ["era bella questa dimmi il precedente"],
        ["ripeti l ultimo"], ["ripeti quest ultima"], ["ripeti"], ["repeat"],
        ["rewind"], ["vai indietro"], ["riporta indietro"]
    ]

    // MARK: - Uscita

    static let quitPhrases: [[String]] = [
        ["esci"], ["esci maestro"], ["maestro esci"], ["chiuditi"], ["chiudi"],
        ["chiudi tutto"], ["spegniti"], ["spegni maestro"], ["arrenditi"],
        ["disattivati"], ["scollegati"], ["quit"], ["exit"], ["goodbye"],
        ["arrivederci"], ["buonanotte"], ["stop maestro"], ["termina"],
        ["interrompi"], ["interrompi tutto"], ["off"], ["shut down"], ["logout"]
    ]

    // MARK: - Filler nel titolo

    /// Parole iniziali da scartare prima del vero titolo.
    static let titleFillerStarts: [[String]] = [
        ["il brano"], ["la canzone"], ["lo brano"], ["un brano"], ["una canzone"],
        ["il pezzo"], ["la traccia"], ["the song"], ["the track"], ["song"],
        ["track"], ["brano"], ["canzone"], ["musica"], ["pezzo"], ["traccia"]
    ]

    /// Stopword finali da rimuovere dopo il titolo.
    static let titleTrailingStopwords: Set<String> = [
        "per", "favore", "perfavore", "perpiacere", "piacere", "please", "grazie",
        "thanks", "ora", "adesso", "now", "subito", "ehi", "hey", "ciao", "dai",
        "brano", "canzone", "traccia", "song", "track", "trovi", "trovato",
        "nei", "tra", "dai", "dei", "sui", "nella", "nel", "sul", "sulla",
        "in", "from", "with", "feat", "ft"
    ]

    /// Token spuri più comuni prodotti dal riconoscitore su parole italiane.
    static let phoneticCorrections: [String: String] = [
        "ma estro": "maestro",
        "a estro": "estro",
        "riproduce": "riproduci",
        "riproduzione": "riproduci", // solo come verbo iniziale, gestito dal parser
        "riproduci": "riproduci",
        "riprodutti": "riproduci",
        "preferriti": "preferiti",
        "prefferiti": "preferiti",
        "preffiniti": "preferiti",
        "playlist": "playlist",
        "play list": "playlist",
        "plelist": "playlist",
        "succissivo": "successivo",
        "succesivo": "successivo",
        "previcente": "precedente",
        "precdente": "precedente",
        "prossimo": "prossimo",
        "prossummo": "prossimo",
        "pausa": "pausa",
        "paussa": "pausa",
        "posi": "pausa",
        "ripndi": "riprendi",
        "riprandi": "riprendi",
        "ripreni": "riprendi",
        "condua": "continua",
        "continoa": "continua",
        "squlta": "ascolta",
        "secolta": "ascolta",
        "qul": "il"
    ]

    /// Espressioni multi-token da sostituire prima della tokenizzazione.
    static let phraseCorrections: [(String, String)] = [
        ("ma estro", "maestro"),
        ("a estro", "estro"),
        ("play list", "playlist"),
        ("l ultimo", "ultimo"),
        ("un altro", "altro"),
        ("unaltra", "un altra")
    ]

    // MARK: - Contesto per il riconoscitore vocale

    /// Parole chiave del lessico passate a `contextualStrings` di
    /// SFSpeechAudioBufferRecognitionRequest: migliorano il riconoscimento
    /// dei comandi tipici (es. «Maestro» invece di «mastro»).
    static let allCommandWords: [String] = {
        var words = Set<String>()
        words.formUnion(wakeWordAliases.split(separator: " ").map(String.init))
        for group in [playVerbs, politenessPrefixes, favoritesPhrases.filter { !$0.contains("*") },
                      playlistMarkers, pausePhrases, resumePhrases, nextPhrases,
                      previousPhrases, quitPhrases, titleFillerStarts] {
            for phrase in group { words.formUnion(phrase) }
        }
        words.remove("*")
        return Array(words).sorted()
    }()
}
