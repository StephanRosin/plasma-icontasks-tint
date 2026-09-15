#!/usr/bin/env bash
# Misst die mittlere Farbsaettigung der Symbolreihe im Hauptpanel.
# Aufruf: messung.sh vorher|nachher
set -euo pipefail

AUSSCHNITT="2820x110+4520+2770"
ABLAGE="${TMPDIR:-/tmp}/icontasks-messung"
mkdir -p "$ABLAGE"

phase="${1:?vorher oder nachher angeben}"
schuss="$ABLAGE/$phase.png"

spectacle -b -n -f -o "$schuss" >/dev/null 2>&1
sleep 1

wert="$(magick "$schuss" -crop "$AUSSCHNITT" +repage \
        -colorspace HSL -channel g -separate +channel \
        -format '%[fx:mean]' info:)"

printf '%s\n' "$wert" > "$ABLAGE/$phase.txt"
printf 'mittlere Saettigung (%s): %s\n' "$phase" "$wert"

if [[ "$phase" == "nachher" && -f "$ABLAGE/vorher.txt" ]]; then
    vorher="$(cat "$ABLAGE/vorher.txt")"
    printf '\nvorher:  %s\nnachher: %s\n' "$vorher" "$wert"
    if awk -v v="$vorher" -v n="$wert" 'BEGIN { exit !(n < v * 0.6) }'; then
        printf 'ok   Saettigung ist deutlich gefallen\n'
    else
        printf 'FAIL Saettigung ist nicht ausreichend gefallen\n'
        exit 1
    fi
fi
