#!/usr/bin/env bash
# Entfernt den Fork. Plasma greift danach wieder auf das mitgelieferte Widget zurueck.
set -euo pipefail

DEST="$HOME/.local/share/plasma/plasmoids/ch.sterostxc.icontasks-tint"

if [[ ! -e "$DEST" ]]; then
    printf 'Nichts zu tun, %s existiert nicht.\n' "$DEST"
    exit 0
fi

rm -rf "$DEST"
# ./migrate.py --zurueck raeumt seine eigene Sicherung (*.vor-migration) und
# Pruefsumme (*.vor-migration.stand) nach erfolgreicher Wiederherstellung selbst
# weg - hier ist dafuer nichts weiter noetig.
printf 'Entfernt. Denk an ./migrate.py --zurueck, falls die Leisten noch\n'
printf 'auf dieses Widget zeigen. Starte die Plasma-Shell neu ...\n'
systemctl --user restart plasma-plasmashell
printf 'Fertig.\n'
