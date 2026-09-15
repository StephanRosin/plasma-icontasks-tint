#!/usr/bin/env bash
# Faehrt den Mauszeiger auf ein Symbol der Taskleiste und prueft messend,
# ob es sich dreht und ob seine Farbe zurueckkehrt.
set -euo pipefail

export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR}/.ydotool_socket"
ABLAGE="${TMPDIR:-/tmp}/icontasks-hover"
mkdir -p "$ABLAGE"

# Mitte des dritten Symbols der Hauptleiste, logische Koordinaten des
# Gesamtdesktops. Die Symbolreihe beginnt bei x=2260, Schrittweite 78,
# Panelmitte bei y=1412. Am 2026-09-15 am laufenden System ermittelt.
X=${1:-2416}
Y=${2:-1412}
AUSSCHNITT="120x120+$(( (X - 60) * 2 ))+$(( (Y - 60) * 2 ))"

schuss() {
    spectacle -b -n -f -o "$ABLAGE/$1.png" >/dev/null 2>&1
    sleep 0.4
}

kennzahl() {  # mittlere Saettigung des Symbolausschnitts
    magick "$ABLAGE/$1.png" -crop "$AUSSCHNITT" +repage \
        -colorspace HSL -channel g -separate +channel -format '%[fx:mean]' info:
}

# Zeiger weit weg parken, Ruhezustand aufnehmen
ydotool mousemove --absolute -x 3900 -y 700
sleep 0.5
schuss ruhe

# Auf das Symbol fahren, zweimal mitten in der Drehung aufnehmen
ydotool mousemove --absolute -x "$X" -y "$Y"
sleep 0.6
schuss hover1
schuss hover2

# Wieder wegfahren
ydotool mousemove --absolute -x 3900 -y 700
sleep 1.2
schuss zurueck

ruhe="$(kennzahl ruhe)"; hover="$(kennzahl hover1)"; zurueck="$(kennzahl zurueck)"
dreh="$(magick compare -metric RMSE \
        \( "$ABLAGE/hover1.png" -crop "$AUSSCHNITT" +repage \) \
        \( "$ABLAGE/hover2.png" -crop "$AUSSCHNITT" +repage \) null: 2>&1 \
        | sed 's/.*(\(.*\))/\1/')"

printf 'Saettigung  Ruhe %s | Hover %s | zurueck %s\n' "$ruhe" "$hover" "$zurueck"
printf 'Unterschied zwischen zwei Hover-Aufnahmen (RMSE): %s\n' "$dreh"

fehler=0
awk -v r="$ruhe" -v h="$hover" 'BEGIN { exit !(h > r * 1.3) }' \
    && printf 'ok   Farbe kehrt beim Hover zurueck\n' \
    || { printf 'FAIL Farbe kehrt beim Hover nicht zurueck - stimmen die Koordinaten?\n'; fehler=1; }

awk -v d="$dreh" 'BEGIN { exit !(d > 0.02) }' \
    && printf 'ok   Symbol dreht sich (zwei Aufnahmen unterscheiden sich)\n' \
    || { printf 'FAIL keine Bewegung messbar\n'; fehler=1; }

awk -v r="$ruhe" -v z="$zurueck" 'BEGIN { exit !(z < r * 1.3) }' \
    && printf 'ok   nach dem Verlassen wieder eingefaerbt\n' \
    || { printf 'FAIL bleibt nach dem Verlassen bunt\n'; fehler=1; }

exit "$fehler"
