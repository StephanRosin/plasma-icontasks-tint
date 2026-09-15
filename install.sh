#!/usr/bin/env bash
# Baut den Fork des Icons-Only Task Manager und installiert ihn ins Benutzerverzeichnis.
# Extrahiert bei jedem Lauf frisch aus der gerade installierten Plasma-Bibliothek,
# damit ein erneuter Aufruf nach einem Plasma-Update den Stand nachzieht.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/plasma/plasmoids/ch.sterostxc.icontasks-tint"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# Vorpruefung: alle Bausteine, die dieses Skript spaeter kopiert, muessen jetzt
# schon da sein. Lieber hier klar abbrechen als mitten im Bau mit "cp: nicht
# gefunden" und einem halb kopierten Zielverzeichnis.
for datei in \
    "$ROOT/patch/task-qml.patch" \
    "$ROOT/patch/IconEffect.qml" \
    "$ROOT/patch/HoverSpin.qml" \
    "$ROOT/patch/Backend.qml" \
    "$ROOT/patch/SmartLauncherItem.qml" \
    "$ROOT/skel/metadata.json" \
    "$ROOT/skel/tmlocal-qmldir"
do
    if [[ ! -f "$datei" ]]; then
        printf 'Abbruch: %s fehlt.\n' "$datei" >&2
        exit 1
    fi
done

printf 'Extrahiere QML-Quellen ...\n'
python3 "$ROOT/extract.py" "$BUILD/ui"

printf 'Wende Patch an ...\n'
if ! patch --dry-run -s -p1 -d "$BUILD/ui" < "$ROOT/patch/task-qml.patch"; then
    printf 'Abbruch: Der Patch passt nicht mehr auf Task.qml.\n' >&2
    printf 'Plasma hat die Datei geaendert. Patch neu erzeugen, siehe Plan Task 5.\n' >&2
    exit 1
fi
patch -s -p1 -d "$BUILD/ui" < "$ROOT/patch/task-qml.patch"

cp "$ROOT/patch/IconEffect.qml" "$ROOT/patch/HoverSpin.qml" "$BUILD/ui/"

# Die mitgelieferte qmldir stammt aus dem kompilierten Modul und enthaelt eine
# prefer-Zeile, die den lokalen Namensraum aushebelt. In Task 2 aufgefallen.
if [[ ! -f "$BUILD/ui/qmldir" ]]; then
    printf 'Abbruch: erwartete qmldir fehlt im extrahierten Stand.\n' >&2
    printf 'extract.py hat sich geaendert, der Ansatz ist neu zu pruefen.\n' >&2
    exit 1
fi
rm -f "$BUILD/ui/qmldir"

# Plasma erwartet die Konfigurationsbeschreibung unter contents/config/,
# extract.py legt alles flach ab. Ebenfalls in Task 2 aufgefallen.
if [[ ! -f "$BUILD/ui/main.xml" || ! -f "$BUILD/ui/config.qml" ]]; then
    printf 'Abbruch: main.xml oder config.qml fehlt im extrahierten Stand.\n' >&2
    printf 'Plasma hat die Konfigurationsdateien umbenannt oder entfernt.\n' >&2
    exit 1
fi
mkdir -p "$BUILD/config"
mv "$BUILD/ui/main.xml" "$BUILD/ui/config.qml" "$BUILD/config/"

printf 'Lege den lokalen Namensraum an ...\n'
if [[ ! -f "$BUILD/ui/LayoutMetrics.js" || ! -f "$BUILD/ui/TaskTools.js" ]]; then
    printf 'Abbruch: LayoutMetrics.js oder TaskTools.js fehlt im extrahierten Stand.\n' >&2
    printf 'Diese Dateien werden fuer den lokalen Namensraum gebraucht.\n' >&2
    exit 1
fi
mkdir -p "$BUILD/ui/tmlocal"
cp "$ROOT/skel/tmlocal-qmldir" "$BUILD/ui/tmlocal/qmldir"
cp "$ROOT/patch/Backend.qml" "$ROOT/patch/SmartLauncherItem.qml" "$BUILD/ui/tmlocal/"
cp "$BUILD/ui/LayoutMetrics.js" "$BUILD/ui/TaskTools.js" "$BUILD/ui/tmlocal/"

printf 'Biege den Namensraum um ...\n'
# Task.qml bringt seine Import-Zeile schon aus dem Patch mit (siehe task-qml.patch).
# Alle anderen Dateien, die das Bibliotheksmodul noch importieren, werden hier
# generisch umgestellt.
mapfile -t betroffen < <(grep -rl 'plasma\.applet\.org\.kde\.plasma\.taskmanager' \
                         "$BUILD/ui" --include='*.qml')
if [[ "${#betroffen[@]}" -eq 0 ]]; then
    printf 'Abbruch: keine Datei importiert das Bibliotheksmodul mehr.\n' >&2
    printf 'Plasma hat den Aufbau geaendert, der Ansatz ist neu zu pruefen.\n' >&2
    exit 1
fi
sed -i 's|import plasma\.applet\.org\.kde\.plasma\.taskmanager as TaskManagerApplet|import "tmlocal" as TaskManagerApplet|' \
    "${betroffen[@]}"
printf '  %d Datei(en) umgestellt\n' "${#betroffen[@]}"

# Gegenprobe: danach darf keine Datei mehr auf das Bibliotheksmodul verweisen.
# Faende sich noch eine, haette der sed-Ausdruck nicht gegriffen (z. B. weil
# Plasma die Import-Zeile leicht anders schreibt) - dann lieber abbrechen als
# ein Paket auszuliefern, das im Journal mit einem TypeError endet.
if grep -rlq 'plasma\.applet\.org\.kde\.plasma\.taskmanager' "$BUILD/ui" --include='*.qml'; then
    printf 'Abbruch: nach der Umstellung verweist noch mindestens eine Datei auf das Bibliotheksmodul.\n' >&2
    printf 'Der sed-Ausdruck hat nicht gegriffen, Plasma hat die Zeile vermutlich anders formuliert.\n' >&2
    exit 1
fi

printf 'Installiere nach %s ...\n' "$DEST"
rm -rf "$DEST"
mkdir -p "$DEST/contents"
cp "$ROOT/skel/metadata.json" "$DEST/metadata.json"
cp -r "$BUILD/ui" "$DEST/contents/ui"
cp -r "$BUILD/config" "$DEST/contents/config"

printf 'Starte die Plasma-Shell neu ...\n'
systemctl --user restart plasma-plasmashell

printf '\nFertig. Das Widget liegt bereit; in die Leisten bringt es ./migrate.py\n'
printf 'Rueckweg: ./uninstall.sh\n'
