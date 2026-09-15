#!/usr/bin/env bash
# Baut den Fork des Icons-Only Task Manager und installiert ihn ins Benutzerverzeichnis.
# Extrahiert bei jedem Lauf frisch aus der gerade installierten Plasma-Bibliothek,
# damit ein erneuter Aufruf nach einem Plasma-Update den Stand nachzieht.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/plasma/plasmoids/ch.sterostxc.icontasks-tint"
BUILD="$(mktemp -d)"
# STAGE (fertiges Paket, wartet auf den atomaren Platzwechsel) und ALT
# (beiseite geschobene alte Installation) entstehen erst weiter unten -
# hier schon leer deklariert, damit "set -u" beim Aufraeumen nicht stoert,
# falls das Skript vorher abbricht.
STAGE=""
ALT=""
aufraeumen() {
    # Den Exit-Code des eigentlichen Skripts sichern, bevor hier irgendein
    # Test (z. B. "-e $ALT" nach erfolgreichem Aufraeumen) mit falsch
    # zurueckkommt und sonst faelschlich zu einem Exit-Code 1 fuehren wuerde.
    local status=$?
    rm -rf "$BUILD"
    [[ -n "$STAGE" && -e "$STAGE" ]] && rm -rf "$STAGE"
    [[ -n "$ALT" && -e "$ALT" ]] && rm -rf "$ALT"
    exit "$status"
}
trap aufraeumen EXIT

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

# Ein leeres $betroffen hat zwei ganz verschiedene Ursachen, die sich nicht
# verwechseln duerfen: entweder war Task.qml zufaellig die letzte Datei mit
# diesem Import, und der Patch hat sie schon erledigt (voellig in Ordnung -
# dann bleibt fuer den sed-Schritt hier nichts mehr zu tun), oder das
# Bibliotheksmodul wird nirgends mehr importiert, auch nicht in der vom
# Patch erzeugten Form (dann greift der ganze Ansatz nicht mehr). Nur der
# zweite Fall ist ein echter Abbruchgrund.
task_qml_vom_patch_umgestellt=false
if [[ -f "$BUILD/ui/Task.qml" ]] \
    && grep -q 'import "tmlocal" as TaskManagerApplet' "$BUILD/ui/Task.qml"; then
    task_qml_vom_patch_umgestellt=true
fi

if [[ "${#betroffen[@]}" -eq 0 && "$task_qml_vom_patch_umgestellt" == false ]]; then
    printf 'Abbruch: keine Datei importiert das Bibliotheksmodul mehr - auch Task.qml nicht, weder im Original- noch im vom Patch umgestellten Import.\n' >&2
    printf 'Plasma hat den Aufbau geaendert, der Ansatz ist neu zu pruefen.\n' >&2
    exit 1
fi

if [[ "${#betroffen[@]}" -gt 0 ]]; then
    sed -i 's|import plasma\.applet\.org\.kde\.plasma\.taskmanager as TaskManagerApplet|import "tmlocal" as TaskManagerApplet|' \
        "${betroffen[@]}"
    printf '  %d Datei(en) umgestellt\n' "${#betroffen[@]}"
else
    printf '  keine weitere Datei mehr umzustellen - Task.qml hat der Patch bereits erledigt.\n'
fi

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
DEST_PARENT="$(dirname "$DEST")"
mkdir -p "$DEST_PARENT"

# Das fertige Paket vollstaendig in einem Geschwisterverzeichnis von $DEST
# zusammenbauen - selbes Elternverzeichnis, also selbes Dateisystem, das ist
# die Voraussetzung dafuer, dass der Platzwechsel weiter unten ein einzelnes,
# atomares mv (Rename) sein kann statt eines Kopiervorgangs. Bricht dieser
# Aufbau hier ab (volle Platte, abgebrochener Lauf), ist $DEST noch gar
# nicht angefasst - die alte Installation bleibt unversehrt.
STAGE="$(mktemp -d "$DEST_PARENT/.icontasks-tint-build.XXXXXX")"
mkdir -p "$STAGE/contents"
cp "$ROOT/skel/metadata.json" "$STAGE/metadata.json"
cp -r "$BUILD/ui" "$STAGE/contents/ui"
cp -r "$BUILD/config" "$STAGE/contents/config"

# Platzwechsel: zwei einzelne mv (Rename), jedes fuer sich atomar - nie ein
# halb kopiertes $DEST. Eine bestehende Installation wird erst beiseite
# geschoben (ALT), dann das fertige Paket an ihre Stelle bewegt. Schlaegt der
# zweite mv wider Erwarten fehl, wird die alte Installation aus ALT sofort
# zurueckgeholt, statt den Benutzer ganz ohne Widget dastehen zu lassen.
ALT="$DEST_PARENT/.icontasks-tint-alt.$$"
if [[ -e "$DEST" ]] && ! mv "$DEST" "$ALT"; then
    printf 'Abbruch: die bestehende Installation unter %s liess sich nicht beiseite schieben.\n' "$DEST" >&2
    printf 'Sie ist unveraendert - nichts wurde installiert.\n' >&2
    exit 1
fi
if ! mv "$STAGE" "$DEST"; then
    printf 'Abbruch: Platzwechsel nach %s fehlgeschlagen.\n' "$DEST" >&2
    if [[ -e "$ALT" ]]; then
        printf 'Stelle die vorherige Installation wieder her ...\n' >&2
        mv "$ALT" "$DEST"
    fi
    exit 1
fi
rm -rf "$ALT" 2>/dev/null || true

printf 'Starte die Plasma-Shell neu ...\n'
systemctl --user restart plasma-plasmashell

printf '\nFertig. Das Widget liegt bereit; in die Leisten bringt es ./migrate.py\n'
printf 'Rueckweg: ./uninstall.sh\n'
