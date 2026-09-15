#!/usr/bin/env bash
# Prueft, ob das eigenstaendige Widget mit eigener ID aus dem Benutzerverzeichnis
# ueberhaupt startet, wenn der C++-Typ Backend durch einen QML-Ersatz ersetzt wird.
# Baut NICHT am echten Installationsort und fasst die laufenden Leisten nicht an.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/share/plasma/plasmoids/ch.sterostxc.icontasks-tint"
WIDGET_ID="ch.sterostxc.icontasks-tint"
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

# extract.py zieht auch die urspruengliche qmldir der Ressource mit heraus. Sie
# enthaelt eine "prefer :/qt/qml/plasma/applet/org/kde/plasma/taskmanager/"-Zeile,
# die wegen des impliziten Verzeichnis-Imports von contents/ui dafuer sorgt, dass
# Qt Skripte wie LayoutMetrics.js zuerst in der (hier nicht vorhandenen) qrc-
# Ressource sucht statt auf der Platte. Sie muss weg, sonst schlaegt der Start mit
# "Script qrc:/.../LayoutMetrics.js unavailable" fehl, obwohl die Datei lokal liegt.
rm -f "$DEST/contents/ui/qmldir"

# extract.py legt auch main.xml (KCFG-Schema) und config.qml flach in contents/ui
# ab. Beide gehoeren fuer ein KPackage-Applet nach contents/config/, sonst bleibt
# Plasmoid.configuration.* ueberall undefined (Vergleich mit echten installierten
# Plasmoiden wie org.kde.plasma.systemmonitor bestaetigt diesen Aufbau).
# ConfigAppearance.qml/ConfigBehavior.qml bleiben in contents/ui, da config.qml sie
# mit einfachem Dateinamen referenziert.
mkdir -p "$DEST/contents/config"
mv "$DEST/contents/ui/main.xml"  "$DEST/contents/config/main.xml"
mv "$DEST/contents/ui/config.qml" "$DEST/contents/config/config.qml"

# Lokalen Namensraum anlegen: qmldir, Backend-Ersatz und die beiden JS-Bibliotheken
mkdir -p "$DEST/contents/ui/tmlocal"
cp "$ROOT/skel/tmlocal-qmldir"          "$DEST/contents/ui/tmlocal/qmldir"
cp "$ROOT/patch/Backend.qml"            "$DEST/contents/ui/tmlocal/"
cp "$ROOT/patch/SmartLauncherItem.qml"  "$DEST/contents/ui/tmlocal/"
cp "$DEST/contents/ui/LayoutMetrics.js" "$DEST/contents/ui/TaskTools.js" \
   "$DEST/contents/ui/tmlocal/"

# Den Namensraum umbiegen: aus dem Bibliotheksmodul wird das lokale Verzeichnis
grep -rl 'plasma.applet.org.kde.plasma.taskmanager' "$DEST/contents/ui" \
    --include='*.qml' \
  | xargs sed -i 's|import plasma\.applet\.org\.kde\.plasma\.taskmanager as TaskManagerApplet|import "tmlocal" as TaskManagerApplet|'

printf 'Widget liegt unter %s, starte plasmawindowed fuer 8 Sekunden ...\n' "$DEST"
START="$(date '+%Y-%m-%d %H:%M:%S')"
timeout 8 plasmawindowed "$WIDGET_ID" >"$LOG" 2>&1

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

if grep -qiE 'is not a type|module .* is not installed|Cannot assign|ReferenceError|error when loading applet|Backend\.qml|tmlocal|TypeError|SmartLauncherItem' "$LOG"; then
    printf 'FEHLGESCHLAGEN: QML-Fehler, siehe oben.\n'
    exit 1
fi

printf 'BESTANDEN: keine QML-Fehler. Bitte bestaetigen, dass das Fenster Symbole zeigte.\n'
exit 0
