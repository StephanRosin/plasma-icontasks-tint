#!/usr/bin/env bash
# Prueft, ob ein Fork des Widgets aus dem Benutzerverzeichnis ueberhaupt startet.
# Baut NICHT am echten Installationsort und fasst die laufenden Leisten nicht an.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/share/plasma/plasmoids/org.kde.plasma.icontasks"
LOG="$(mktemp)"

if [[ -e "$DEST" ]]; then
    printf 'Abbruch: %s existiert bereits. Erst uninstall.sh laufen lassen.\n' "$DEST" >&2
    exit 2
fi

cleanup() { rm -rf "$DEST"; rm -f "$LOG"; }
trap cleanup EXIT

mkdir -p "$DEST/contents/ui"
cp "$ROOT/skel/metadata.json" "$DEST/metadata.json"
python3 "$ROOT/extract.py" "$DEST/contents/ui" || exit 1

# Ausweg 1 (Task 2, Step 4): Modul per qmldir-Verweis bereitstellen, weil
# X-Plasma-RootPath fehlt und der Typ "Backend" sonst nicht registriert wird.
if [[ -f "$ROOT/skel/tmmodule/qmldir" ]]; then
    mkdir -p "$DEST/contents/ui/tmmodule"
    cp "$ROOT/skel/tmmodule/qmldir" "$DEST/contents/ui/tmmodule/qmldir"
    sed -i \
        's/^import plasma\.applet\.org\.kde\.plasma\.taskmanager as TaskManagerApplet$/import "tmmodule" as TaskManagerApplet/' \
        "$DEST/contents/ui"/*.qml
fi

printf 'Fork liegt unter %s, starte plasmawindowed fuer 8 Sekunden ...\n' "$DEST"
START="$(date '+%Y-%m-%d %H:%M:%S')"
timeout 8 plasmawindowed org.kde.plasma.icontasks >"$LOG" 2>&1

# plasmawindowed schreibt auf diesem System ueber den systemd-Journal-Handler,
# nicht auf stdout/stderr. Ohne diesen Nachtrag waere der Log-Mitschnitt leer
# und die Pruefung unten wuerde faelschlich BESTANDEN melden.
if command -v journalctl >/dev/null 2>&1; then
    journalctl --user --since "$START" _COMM=plasmawindowed --no-pager >>"$LOG" 2>/dev/null
    journalctl --since "$START" _COMM=plasmawindowed --no-pager >>"$LOG" 2>/dev/null
fi

printf '\n--- Ausgabe (stdout/stderr + Journal) ---\n'
cat "$LOG"
printf '\n--- Bewertung ---\n'

if grep -qiE 'is not a type|module .* is not installed|Cannot assign|ReferenceError|error when loading applet' "$LOG"; then
    printf 'FEHLGESCHLAGEN: QML-Fehler, siehe oben.\n'
    printf 'Naechster Schritt laut Plan: Ausweg 1 in Task 2, Step 4.\n'
    exit 1
fi

printf 'BESTANDEN: keine QML-Fehler. Bitte bestaetigen, dass das Fenster Symbole zeigte.\n'
exit 0
