# Maestro
Assistente vocale da menu bar per Apple Music (macOS 14+).

## Build e avvio da terminale
./Scripts/build.sh

## Build con XcodeGen
xcodegen generate && open Maestro.xcodeproj

## Comandi
- "Maestro riproduci <brano>"
- "Maestro riproduci <brano> nei miei brani preferiti"
- "Maestro play <brano> from favorites"

## Reset permessi
tccutil reset Microphone com.francescofalduto.maestro
tccutil reset SpeechRecognition com.francescofalduto.maestro
tccutil reset MediaLibrary com.francescofalduto.maestro