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

# Positive Erfolgsmarkierung, NUR in dieser Wegwerf-Kopie: "nichts Schlimmes im
# Log" beweist nicht, dass das Widget tatsaechlich geladen wurde - ein Lauf, bei
# dem plasmawindowed das Paket gar nicht erst findet, waere sonst faelschlich
# BESTANDEN, sofern er zufaellig keinen der bekannten Fehlertexte trifft. Der
# Marker sitzt in Component.onCompleted des lokalen Backend-Ersatzes: dieses
# Objekt wird in main.qml als readonly property mit Objekt-Initialisierer
# angelegt (TaskManagerApplet.Backend { ... }), also nur dann instanziiert,
# wenn main.qml wirklich bis zum Aufbau seines Objektbaums geladen wurde. Der
# Marker bleibt bewusst NICHT im committeten patch/Backend.qml - das ist
# produktiver Code fuer Task 5, kein Testschmutz.
sed -i '/^QtObject {$/a\    Component.onCompleted: console.log("SPIKE-WIDGET-GELADEN")' \
    "$DEST/contents/ui/tmlocal/Backend.qml"

printf 'Widget liegt unter %s, starte plasmawindowed fuer 8 Sekunden ...\n' "$DEST"
START="$(date '+%Y-%m-%d %H:%M:%S')"
timeout 8 plasmawindowed "$WIDGET_ID" >"$LOG" 2>&1
PW_EXIT=$?

# plasmawindowed schreibt auf diesem System ueber den systemd-Journal-Handler,
# nicht auf stdout/stderr. Ohne diesen Nachtrag waere der Log-Mitschnitt leer
# und die Pruefung unten wuerde faelschlich BESTANDEN melden.
if command -v journalctl >/dev/null 2>&1; then
    journalctl --user --since "$START" _COMM=plasmawindowed --no-pager >>"$LOG" 2>/dev/null
    journalctl --since "$START" _COMM=plasmawindowed --no-pager >>"$LOG" 2>/dev/null
fi

printf '\n--- Ausgabe (stdout/stderr + Journal) ---\n'
cat "$LOG"
printf '\nExit-Code plasmawindowed: %s\n' "$PW_EXIT"
printf '\n--- Bewertung ---\n'

FEHLGESCHLAGEN=0

# 1. Exit-Code auswerten. "timeout 8" liefert bei planmaessigem Ablauf der Zeit
# den Code 124 - das ist hier der ERWARTETE Ausgang, weil das Fenster die
# vollen acht Sekunden stehen soll. 0 heisst, plasmawindowed hat sich vorzeitig
# beendet; jeder andere Code deutet auf einen Absturz hin.
if [[ "$PW_EXIT" -ne 124 ]]; then
    printf 'FEHLGESCHLAGEN: plasmawindowed beendete sich mit Exit-Code %s (erwartet: 124, timeout erreicht).\n' "$PW_EXIT"
    FEHLGESCHLAGEN=1
fi

# 2. Bekannte Fehlertexte UND eine allgemeine QML-Fehlersignatur, die an der
# Form (nicht am Wortlaut) erkennt: die "<datei>.qml:<zeile>:"-Bauart von
# QML-Compile- und Laufzeitfehlermeldungen, plus die ueblichen Qt-Schweregrade.
# Bekannt und in Ordnung bleibt weiterhin der TypeError aus Task.qml:244 (Folge
# der Erzeugungsstelle von SmartLauncherItem in Zeile 240, gehoert zu Task 5) -
# er faellt hier weiterhin unter "QML-Fehler" und macht den Lauf zu Recht
# FEHLGESCHLAGEN, solange Task.qml nicht gepatcht ist; siehe Bericht.
if grep -qiE 'is not a type|module .* is not installed|Cannot assign|ReferenceError|error when loading applet|Backend\.qml|tmlocal|TypeError|SmartLauncherItem|\.qml:[0-9]+:|\b(Fatal|Critical|SyntaxError|RangeError)\b' "$LOG"; then
    printf 'FEHLGESCHLAGEN: QML-Fehler, siehe oben.\n'
    FEHLGESCHLAGEN=1
fi

# 3. Positive Erfolgsmarkierung verlangen (siehe Kommentar oben bei ihrer
# Einpflanzung). Ohne sie waere ein Lauf, in dem schlicht nichts passiert,
# ebenfalls BESTANDEN.
if ! grep -q 'SPIKE-WIDGET-GELADEN' "$LOG"; then
    printf 'FEHLGESCHLAGEN: keine Erfolgsmarkierung im Journal - das Widget wurde nicht nachweislich geladen.\n'
    FEHLGESCHLAGEN=1
fi

if [[ "$FEHLGESCHLAGEN" -ne 0 ]]; then
    exit 1
fi

printf 'BESTANDEN: keine QML-Fehler, Erfolgsmarkierung vorhanden, Exit-Code 124 wie erwartet. Bitte bestaetigen, dass das Fenster Symbole zeigte.\n'
exit 0
