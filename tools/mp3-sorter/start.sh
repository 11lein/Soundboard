#!/usr/bin/env bash
# Doppelklick-Starter für den MP3 Sorter (Linux).
# Hinweis: Im Dateimanager ggf. "Ausführen erlauben" / "Run" wählen.
cd "$(dirname "$0")" || exit 1

# Auf manchen Systemen ist diese Variable gesetzt und würde Electron als Node
# statt als GUI starten – hier entfernen.
unset ELECTRON_RUN_AS_NODE ELECTRON_NO_ATTACH_CONSOLE

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
