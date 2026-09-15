#!/usr/bin/env python3
"""Tauscht in der Panel-Konfiguration das Taskleisten-Widget aus.

Die Einstellungen eines Applets haengen an seiner Nummer, nicht an seinem Plugin-Namen.
Es genuegt deshalb, die Zeile `plugin=` umzuschreiben - die angehefteten Starter und alle
uebrigen Einstellungen bleiben unberuehrt an Ort und Stelle stehen.

Plasma schreibt seine Konfiguration beim Beenden zurueck. Ohne `--pruefen` haelt dieses
Skript deshalb plasmashell an, bevor es schreibt, und startet es danach wieder.

Sicherheitsnetz: Es wird nur ersetzt, wenn genau die erwartete Anzahl Widgets gefunden
wird - bei null oder einer unerwarteten Anzahl bricht das Skript ab, statt zu raten.
Bei `--zurueck` wird vor dem Wiederherstellen gegen eine beim Migrieren hinterlegte
Pruefsumme abgeglichen, damit eine zwischenzeitliche Aenderung an der Konfiguration
nicht stillschweigend verworfen wird.

Dateien, die zu diesem Werkzeug gehoeren (neben der Konfiguration selbst):
`<config>.vor-migration` (Sicherung vor der Migration) und
`<config>.vor-migration.stand` (Pruefsumme des Standes direkt nach der Migration).
Eine erfolgreiche Wiederherstellung (`--zurueck`) raeumt beide wieder weg - nach
einem vollstaendigen Rueckbau (siehe uninstall.sh) bleibt so keine verwaiste Datei
im Konfigurationsverzeichnis liegen.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

CONFIG = Path.home() / ".config" / "plasma-org.kde.plasma.desktop-appletsrc"
SICHERUNG = CONFIG.with_name(CONFIG.name + ".vor-migration")
STAND = CONFIG.with_name(CONFIG.name + ".vor-migration.stand")
ALT = "org.kde.plasma.icontasks"
NEU = "ch.sterostxc.icontasks-tint"
# Auf diesem System gibt es zwei Leisten mit dem alten Widget (siehe Task 2/6).
# Eine andere Anzahl bedeutet: die Konfiguration sieht anders aus als erwartet.
ERWARTETE_ANZAHL = 2


def umschreiben(text: str, von: str, nach: str) -> tuple[str, int]:
    """Ersetzt jede Zeile `plugin=<von>` durch `plugin=<nach>`. Nur ganze Zeilen."""
    zeilen = text.splitlines(keepends=True)
    treffer = 0
    for i, zeile in enumerate(zeilen):
        if zeile.strip() == f"plugin={von}":
            ende = zeile[len(zeile.rstrip("\r\n")):]
            zeilen[i] = f"plugin={nach}{ende}"
            treffer += 1
    return "".join(zeilen), treffer


def pruefsumme(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def shell(aktion: str) -> None:
    subprocess.run(
        ["systemctl", "--user", aktion, "plasma-plasmashell"],
        check=True,
    )


def migrieren(ziel: Path, sicherung: Path, stand: Path, probelauf: bool) -> int:
    """Ersetzt das alte durch das neue Widget in 'ziel'.

    Bei probelauf=True wird nur 'ziel' beschrieben - keine Sicherung, kein
    Pruefsummen-Stand, kein Kontakt zu plasmashell. So arbeitet '--pruefen'.
    """
    if not ziel.exists():
        print(f"{ziel} existiert nicht", file=sys.stderr)
        return 1

    text = ziel.read_text(encoding="utf-8")
    neu, treffer = umschreiben(text, ALT, NEU)

    if treffer == 0:
        # Entweder war nie ein altes Widget vorhanden, oder die Datei wurde
        # bereits migriert (zweiter Lauf). In beiden Faellen wird nichts
        # geschrieben - das Skript ist damit idempotent, kein zweiter Schaden.
        if f"plugin={NEU}" in text:
            print(f"{ziel.name} ist bereits migriert - nichts zu tun.", file=sys.stderr)
        else:
            print(f"Kein Widget {ALT} in {ziel.name} gefunden - nichts zu tun.", file=sys.stderr)
        return 1

    if treffer != ERWARTETE_ANZAHL:
        print(
            f"Erwartet {ERWARTETE_ANZAHL} Widget(s) mit Plugin {ALT}, "
            f"gefunden {treffer} in {ziel.name} - breche ab statt zu raten. "
            "Bitte die Datei von Hand pruefen.",
            file=sys.stderr,
        )
        return 1

    if probelauf:
        ziel.write_text(neu, encoding="utf-8")
        print(f"{treffer} Widget(e) umgestellt (Probelauf auf {ziel})")
        return 0

    shutil.copy2(ziel, sicherung)
    stand.write_text(pruefsumme(neu), encoding="utf-8")
    print(f"Sicherung nach {sicherung}")
    shell("stop")
    ziel.write_text(neu, encoding="utf-8")
    shell("start")
    print(f"{treffer} Widget(e) umgestellt, plasmashell neu gestartet")
    return 0


def wiederherstellen(ziel: Path, sicherung: Path, stand: Path,
                      probelauf: bool, erzwingen: bool) -> int:
    """Stellt 'ziel' aus 'sicherung' wieder her.

    Bei probelauf=True (also '--zurueck --pruefen DATEI') wird nur die Testdatei
    angefasst und plasmashell nicht kontaktiert - so laesst sich diese Funktion
    gefahrlos pruefen. Ohne probelauf wirkt es auf die echte Konfiguration.

    Nach einer erfolgreichen Wiederherstellung werden 'sicherung' und 'stand'
    entfernt: Ihr Zweck ist erfuellt, und ohne diesen Aufraeumschritt bliebe nach
    einem vollstaendigen Rueckbau eine verwaiste Datei im Konfigurationsverzeichnis
    liegen. Ein zweiter '--zurueck'-Aufruf findet danach folgerichtig keine
    Sicherung mehr vor, statt faelschlich eine erneute Aenderung zu behaupten.
    """
    if not sicherung.exists():
        print(f"Keine Sicherung unter {sicherung}", file=sys.stderr)
        return 1

    if not ziel.exists():
        print(f"{ziel} existiert nicht", file=sys.stderr)
        return 1

    if not erzwingen:
        if not stand.exists():
            print(
                f"Keine Pruefsumme unter {stand} - kann nicht feststellen, ob "
                f"{ziel.name} seit der Migration unveraendert ist. "
                "Von Hand pruefen oder --erzwingen verwenden.",
                file=sys.stderr,
            )
            return 1

        aktuell = pruefsumme(ziel.read_text(encoding="utf-8"))
        erwartet = stand.read_text(encoding="utf-8").strip()
        if aktuell != erwartet:
            print(
                f"{ziel.name} wurde seit der Migration erneut veraendert - "
                "Wiederherstellen wuerde diese Aenderungen verwerfen. "
                "Von Hand pruefen oder --erzwingen verwenden.",
                file=sys.stderr,
            )
            return 1

    if probelauf:
        shutil.copy2(sicherung, ziel)
    else:
        shell("stop")
        shutil.copy2(sicherung, ziel)
        shell("start")

    sicherung.unlink(missing_ok=True)
    stand.unlink(missing_ok=True)

    zusatz = " (Probelauf)" if probelauf else ""
    print(f"{ziel.name} aus der Sicherung wiederhergestellt{zusatz}, "
          "Sicherung und Pruefsumme aufgeraeumt")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pruefen", type=Path, metavar="DATEI",
                        help="auf dieser Datei arbeiten statt auf der echten Konfiguration, "
                             "ohne plasmashell anzufassen. Zusammen mit --zurueck wird "
                             "genauso die Wiederherstellung auf dieser Datei simuliert "
                             "(die zugehoerige .vor-migration-Sicherung muss daneben liegen).")
    parser.add_argument("--zurueck", action="store_true",
                        help="die Sicherung wiederherstellen statt zu migrieren")
    parser.add_argument("--erzwingen", action="store_true",
                        help="nur zusammen mit --zurueck: wiederherstellen, obwohl sich die "
                             "Pruefsumme nicht bestaetigen laesst oder fehlt")
    args = parser.parse_args()

    if args.erzwingen and not args.zurueck:
        parser.error("--erzwingen wirkt nur zusammen mit --zurueck und wird sonst ignoriert")

    if args.zurueck:
        if args.pruefen:
            ziel = args.pruefen
            sicherung = ziel.with_name(ziel.name + ".vor-migration")
            stand = ziel.with_name(ziel.name + ".vor-migration.stand")
        else:
            ziel, sicherung, stand = CONFIG, SICHERUNG, STAND
        return wiederherstellen(ziel, sicherung, stand,
                                 probelauf=bool(args.pruefen), erzwingen=args.erzwingen)

    if args.pruefen:
        return migrieren(args.pruefen, None, None, probelauf=True)

    return migrieren(CONFIG, SICHERUNG, STAND, probelauf=False)


if __name__ == "__main__":
    sys.exit(main())
