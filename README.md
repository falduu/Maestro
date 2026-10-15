# Maestro

Assistente vocale dalla barra dei menu per controllare Musica su macOS 14+.

## Funzioni

| Area | Funzione | Esempi |
| --- | --- | --- |
| Riproduzione | Cerca un titolo nella libreria e lo avvia | “Maestro riproduci Imagine”; “Maestro fammi ascoltare Imagine” |
| Preferiti | Cerca un brano nelle playlist riconosciute come preferiti | “Maestro suona Imagine nei miei preferiti” |
| Playlist | Cerca nella playlist indicata | “Maestro metti Imagine nella playlist Rock” |
| Trasporto | Pausa, ripresa, brano successivo o precedente | “Maestro metti in pausa”; “Maestro riprendi”; “Maestro cambia canzone” |
| Ascolto | Avvia/ferma il microfono e mostra trascrizione, comando e stato | Pulsante microfono nel pannello |
| Test manuale | Cerca un titolo scritto senza usare la voce | “Test rapido” nel pannello |
| Permessi | Mostra e apre le impostazioni di Microfono, Voce e Apple Music | Sezione “Permessi” nel pannello |
| Uscita | Chiude Maestro | “Maestro esci” o pulsante “Esci” |

La wake word “Maestro” è richiesta. La lingua segue le preferenze di macOS,
con italiano e inglese come lingue previste. Il riconoscimento on-device viene
richiesto quando il dispositivo lo supporta.

## Vocabolario

Le frasi sono normalizzate prima del confronto: maiuscole, accenti e punteggiatura
non sono significativi. Le frasi composte sono confrontate come sequenze di parole.

| Intento | Parole e frasi riconosciute | Forma d'uso |
| --- | --- | --- |
| Riproduci | riproduci, riprodurre, suona, suonami, metti, mettimi, fai partire, fammi partire, fammi sentire, fammi ascoltare, avvia, cerca e riproduci, play, put on, queue up | `Maestro <azione> <titolo>` |
| Pausa | pausa, metti in pausa, metti la musica in pausa, ferma la musica, sospendi la riproduzione, stop, mute | `Maestro <frase>` |
| Riprendi | riprendi, continua, riparti, riprendi la musica, continua la riproduzione, togli la pausa, resume, unpause | `Maestro <frase>` |
| Successivo | prossimo brano, prossima canzone, brano dopo, cambia canzone, salta, avanti, next, skip | `Maestro <frase>` |
| Precedente | brano precedente, canzone precedente, traccia precedente, torna indietro, ripeti, previous, go back | `Maestro <frase>` |
| Preferiti | nei miei preferiti, tra i miei brani preferiti, dai preferiti, favorites, liked | `Maestro <azione> <titolo> <preferiti>` |
| Playlist | nella playlist, nella mia playlist, in the playlist, from playlist | `Maestro <azione> <titolo> nella playlist <nome>` |
| Uscita | esci, chiudi, chiudi tutto, spegniti, quit, exit, goodbye | `Maestro <frase>` |

Esempi completi:

- “Maestro, per favore, metti su Imagine”
- “Maestro, riproduci la canzone Imagine nei miei brani preferiti”
- “Maestro, fammi ascoltare Imagine nella playlist Rock”
- “Maestro, sospendi la musica”
- “Maestro, continua da dove avevo interrotto”
- “Maestro, salta alla traccia successiva”
- “Maestro, torna al brano precedente”

Il vocabolario sorgente è organizzato per intento in
`Sources/Core/IntentLexicon.swift`. Le correzioni fonetiche sono centralizzate
nello stesso file. Le espressioni specifiche sono preferibili a sinonimi vaghi:
parole generiche possono essere parte del titolo di un brano o di una frase
normale.

## Velocità e continuità

- Maestro prova prima una ricerca AppleScript diretta in Musica; se non trova il brano, usa MusicKit per affinare la ricerca e riprova.
- Il confronto esatto del titolo precede quello parziale, per ridurre le corrispondenze sbagliate.
- Musica viene avviata se è chiusa. Gli script AppleScript compilati e i preferiti vengono riutilizzati in cache.
- “Riprendi” invia il comando di riproduzione al player corrente, invece di selezionare di nuovo il brano. L'ultimo comando vocale viene salvato localmente e usato solo se il player non ha un brano corrente.
- Un comando “riproduci <titolo>” seleziona un nuovo brano; per proseguire la coda già attiva usare “riprendi”. Maestro non ricostruisce la cronologia interna di Apple Music.
- La ricerca nel catalogo Apple Music è disattivata per impostazione predefinita; vengono consultate libreria, preferiti o playlist secondo il comando.
- L'ascolto vocale resta attivo, limita gli aggiornamenti della trascrizione e applica un debounce ai comandi ripetuti.

## Build e avvio

```sh
./Scripts/build.sh
```

Per generare e aprire il progetto Xcode:

```sh
xcodegen generate && open Maestro.xcodeproj
```

## Reset permessi

```sh
tccutil reset Microphone com.francescofalduto.maestro
tccutil reset SpeechRecognition com.francescofalduto.maestro
tccutil reset MediaLibrary com.francescofalduto.maestro
```