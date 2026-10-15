#!/bin/bash
# Compila Maestro, assembla Maestro.app, firma ad-hoc e avvia.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

BUILD_DIR=".build"
APP="${BUILD_DIR}/Maestro.app"
BIN="${APP}/Contents/MacOS/Maestro"

echo "▶ Compilazione ottimizzata..."
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' | sort)

xcrun swiftc \
  -swift-version 5 \
  -O \
  -whole-module-optimization \
  -parse-as-library \
  -sdk "$SDK" \
  -target "$TARGET" \
  -module-name Maestro \
  "${SOURCES[@]}" \
  -o "$BIN"

echo "▶ Assemblaggio bundle..."
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

echo "▶ Codesign ad-hoc..."
codesign --force --sign - "$APP"

echo "▶ Avvio di Maestro..."
open "$APP"

echo "✔ Fatto. Per chiudere: menu bar → Esci, oppure: pkill -x Maestro"