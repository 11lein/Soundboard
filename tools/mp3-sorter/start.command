#!/usr/bin/env bash
# Doppelklick-Starter für den MP3 Sorter (macOS).
# .command-Dateien öffnen beim Doppelklick im Finder ein Terminal.
cd "$(dirname "$0")" || exit 1

if ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm ist nicht installiert. Bitte von https://nodejs.org installieren."
  read -r -p "Enter zum Schließen…" _
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "Installiere Abhängigkeiten (einmalig)…"
  npm install || { echo "npm install fehlgeschlagen."; read -r -p "Enter…" _; exit 1; }
fi

npm start
