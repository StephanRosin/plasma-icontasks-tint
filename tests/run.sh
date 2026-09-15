#!/usr/bin/env bash
# Testlaeufer des Projekts. Ohne Argument laufen alle Tests.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# Bevorzugt den Qt6-qml-Interpreter. Die Komponenten nutzen unversionierte
# "import QtQuick"-Direktiven (Qt6-Stil, so auch in der finalen Plasma-6-Datei).
# Auf dieser Maschine loest der blanke Befehl "qml" auf den parallel installierten
# Qt5-qml (/usr/bin/qml, qt5-declarative) auf, der unversionierte Imports
# stillschweigend nicht laedt (Abbruch ohne Fehlermeldung). Der Qt6-qml liegt
# hier unter /usr/lib/qt6/bin/qml; falls nicht vorhanden, faellt es auf den
# blanken Befehl zurueck.
QML_BIN="qml"
[[ -x /usr/lib/qt6/bin/qml ]] && QML_BIN="/usr/lib/qt6/bin/qml"

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

test_extract() {
    printf 'extract.py\n'
    local out; out="$(mktemp -d)"
    trap 'rm -rf "$out"' RETURN

    if ! python3 "$ROOT/extract.py" "$out" >/dev/null 2>&1; then
        fail "Aufruf schlaegt fehl"; return
    fi
    ok "laeuft durch"

    local count; count="$(find "$out" -maxdepth 1 -type f | wc -l)"
    [[ "$count" -eq 24 ]] && ok "24 Dateien" || fail "24 Dateien erwartet, $count gefunden"

    [[ -f "$out/Task.qml" ]] && ok "Task.qml vorhanden" || fail "Task.qml fehlt"

    grep -q 'id: icon' "$out/Task.qml" \
        && ok "Task.qml enthaelt das Icon-Element" \
        || fail "Task.qml enthaelt 'id: icon' nicht - Upstream hat sich geaendert"

    grep -q 'source: task.model.decoration' "$out/Task.qml" \
        && ok "Icon-Quelle unveraendert" \
        || fail "Icon-Quelle hat sich geaendert"
}

# Laesst eine QML-Testdatei laufen, zeigt ihre Zusicherungen und wertet den Rueckgabewert aus.
# Die Testdatei beendet sich mit Qt.exit(<Anzahl Fehler>), 0 heisst bestanden.
qml_test() {
    local name="$1" datei="$2" ausgabe
    printf '%s\n' "$name"
    # QT_FORCE_STDERR_LOGGING: ohne Terminal schreibt Qt console.log/qWarning
    # sonst ins Journal statt nach stderr, und die ok/FAIL-Zeilen blieben unsichtbar.
    ausgabe="$(QT_FORCE_STDERR_LOGGING=1 "$QML_BIN" -platform offscreen "$datei" 2>&1)"
    local code=$?
    ausgabe="${ausgabe//qml: /}"  # Logging-Kategorie-Praefix wieder abstreifen
    printf '%s\n' "$ausgabe" | grep -E '^[[:space:]]+(ok|FAIL)' || true
    if [[ "$code" -eq 0 ]]; then
        ok "alle Zusicherungen erfuellt"
    else
        fail "$code Zusicherung(en) verletzt oder QML-Fehler"
        printf '%s\n' "$ausgabe" | tail -5
    fi
}

test_hoverspin() { qml_test 'HoverSpin' "$ROOT/tests/qml/tst_hoverspin.qml"; }
test_iconeffect() { qml_test 'IconEffect' "$ROOT/tests/qml/tst_iconeffect.qml"; }

test_patch() {
    printf 'task-qml.patch\n'
    local out; out="$(mktemp -d)"
    trap 'rm -rf "$out"' RETURN

    python3 "$ROOT/extract.py" "$out" >/dev/null 2>&1 || { fail "Extraktion"; return; }

    if patch --dry-run -s -p1 -d "$out" < "$ROOT/patch/task-qml.patch"; then
        ok "Patch ist anwendbar"
    else
        fail "Patch passt nicht mehr auf Task.qml - Upstream hat sich geaendert"
        return
    fi

    patch -s -p1 -d "$out" < "$ROOT/patch/task-qml.patch"

    grep -q 'layer.effect: IconEffect' "$out/Task.qml" \
        && ok "IconEffect eingehaengt" || fail "IconEffect fehlt"
    grep -q 'HoverSpin' "$out/Task.qml" \
        && ok "HoverSpin eingehaengt" || fail "HoverSpin fehlt"
    # Zeilenanker: 'id: icon' ohne $ traefe auch 'id: iconBox' (den Loader
    # weiter oben in derselben Datei) und waere nie bei genau 1 - unabhaengig
    # vom Patch. Das ist eine Praezisierung des Musters, keine Lockerung.
    grep -c 'id: icon$' "$out/Task.qml" | grep -q '^1$' \
        && ok "das Icon-Element ist unveraendert geblieben" \
        || fail "das Icon-Element wurde doppelt oder gar nicht angefasst"

    patch -s -p1 -d "$out" < "$ROOT/patch/config-appearance.patch" \
        && ok "Einstellungs-Patch ist anwendbar" \
        || fail "Einstellungs-Patch passt nicht mehr auf main.xml/ConfigAppearance.qml"

    grep -q '<entry name="tintColor"' "$out/main.xml" \
        && ok "tintColor ist als Einstellung angelegt" || fail "tintColor fehlt in main.xml"
    grep -q '<entry name="tintStrength"' "$out/main.xml" \
        && ok "tintStrength ist als Einstellung angelegt" || fail "tintStrength fehlt in main.xml"
    grep -q 'cfg_tintColor' "$out/ConfigAppearance.qml" \
        && ok "Farbwaehler im Einstellungsdialog" || fail "Farbwaehler fehlt"
    grep -q 'cfg_tintStrength' "$out/ConfigAppearance.qml" \
        && ok "Staerkeregler im Einstellungsdialog" || fail "Staerkeregler fehlt"
    grep -q 'tintColor: Plasmoid.configuration.tintColor' "$out/Task.qml" \
        && ok "Task.qml reicht die Einstellung an IconEffect durch" \
        || fail "Task.qml reicht die Einstellung nicht durch"

    grep -q 'Qt.createComponent("tmlocal/SmartLauncherItem.qml")' "$out/Task.qml" \
        && ok "SmartLauncherItem wird lokal aufgeloest" \
        || fail "die Erzeugungsstelle von SmartLauncherItem zeigt noch auf das Bibliotheksmodul"

    grep -q 'plasma.applet.org.kde.plasma.taskmanager' "$out/Task.qml" \
        && fail "Task.qml verweist noch auf das Bibliotheksmodul" \
        || ok "kein Verweis auf das Bibliotheksmodul mehr in Task.qml"
}

test_migrate() {
    printf 'migrate.py\n'
    local out; out="$(mktemp -d)"
    trap 'rm -rf "$out"' RETURN
    local datei="$out/appletsrc"

    # Nachbau der echten Struktur: zwei Leisten mit dem alten Widget, eine davon
    # mit angehefteten Startern, dazu ein fremdes Widget das unberuehrt bleiben muss.
    cat > "$datei" <<'ENDE'
[Containments][46][Applets][79]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][46][Applets][79][Configuration][General]
groupingStrategy=0
launchers=applications:systemsettings.desktop,applications:code.desktop

[Containments][46][Applets][65]
plugin=org.kde.plasma.showdesktop

[Containments][69][Applets][117]
plugin=org.kde.plasma.icontasks

[Containments][69][Applets][117][Configuration][General]
launchers=
ENDE

    python3 "$ROOT/migrate.py" --pruefen "$datei" >/dev/null 2>&1 \
        && ok "laeuft durch" || { fail "Aufruf schlaegt fehl"; return; }

    [[ "$(grep -c '^plugin=ch.sterostxc.icontasks-tint$' "$datei")" -eq 2 ]] \
        && ok "beide Leisten umgestellt" \
        || fail "es wurden nicht genau zwei Widgets umgestellt"

    grep -q '^plugin=org.kde.plasma.icontasks$' "$datei" \
        && fail "altes Widget steht noch in der Datei" \
        || ok "kein altes Widget mehr uebrig"

    grep -q '^plugin=org.kde.plasma.showdesktop$' "$datei" \
        && ok "fremdes Widget unberuehrt" \
        || fail "fremdes Widget wurde mitveraendert"

    grep -q '^launchers=applications:systemsettings.desktop,applications:code.desktop$' "$datei" \
        && ok "angeheftete Starter unveraendert" \
        || fail "die angehefteten Starter sind verlorengegangen"

    # Der Abschnittskopf darf sich nicht verschieben - sonst findet Plasma die
    # Einstellungen des Applets nicht mehr.
    grep -q '^\[Containments\]\[46\]\[Applets\]\[79\]\[Configuration\]\[General\]$' "$datei" \
        && ok "Abschnittsnamen unveraendert" \
        || fail "ein Abschnittsname hat sich geaendert"

    # --- Zusaetzliche Grenzfaelle: das Skript muss abbrechen statt zu raten ---

    # Zweiter Lauf auf der bereits migrierten Datei: kein zweiter Schaden, kein
    # stillschweigendes Nochmal-Schreiben.
    local vorher; vorher="$(cat "$datei")"
    if python3 "$ROOT/migrate.py" --pruefen "$datei" >/dev/null 2>&1; then
        fail "zweiter Lauf auf bereits migrierter Datei meldet faelschlich Erfolg"
    else
        ok "zweiter Lauf auf bereits migrierter Datei bricht ab"
    fi
    [[ "$(cat "$datei")" == "$vorher" ]] \
        && ok "zweiter Lauf ist idempotent - Datei unveraendert" \
        || fail "zweiter Lauf hat die bereits migrierte Datei doch noch veraendert"

    # Keine passende Zeile vorhanden.
    local leer="$out/leer"
    cat > "$leer" <<'ENDE'
[Containments][46][Applets][65]
plugin=org.kde.plasma.showdesktop
ENDE
    local leer_vorher; leer_vorher="$(cat "$leer")"
    if python3 "$ROOT/migrate.py" --pruefen "$leer" >/dev/null 2>&1; then
        fail "laeuft trotz fehlendem altem Widget durch"
    else
        ok "kein Widget gefunden - bricht ab statt zu raten"
    fi
    [[ "$(cat "$leer")" == "$leer_vorher" ]] \
        && ok "Datei ohne Treffer bleibt unveraendert" \
        || fail "Datei ohne Treffer wurde trotzdem angefasst"

    # Mehr Treffer als die erwarteten zwei: lieber ganz abbrechen als raten,
    # welche der drei gemeint sind.
    local zuviel="$out/zuviel"
    cat > "$zuviel" <<'ENDE'
[Containments][46][Applets][79]
plugin=org.kde.plasma.icontasks

[Containments][69][Applets][117]
plugin=org.kde.plasma.icontasks

[Containments][80][Applets][200]
plugin=org.kde.plasma.icontasks
ENDE
    local vorher_zuviel; vorher_zuviel="$(cat "$zuviel")"
    if python3 "$ROOT/migrate.py" --pruefen "$zuviel" >/dev/null 2>&1; then
        fail "laeuft trotz unerwarteter Anzahl (3 statt 2) durch"
    else
        ok "unerwartete Anzahl Treffer - bricht ab statt zu raten"
    fi
    [[ "$(cat "$zuviel")" == "$vorher_zuviel" ]] \
        && ok "Datei bei unerwarteter Anzahl komplett unveraendert" \
        || fail "Datei wurde trotz Abbruch teilweise migriert"

    # Zeilen, die den Plugin-Namen nur als Teilstring enthalten (Kommentar,
    # andere Schluessel, Starternamen), duerfen nicht mitgezaehlt oder veraendert werden.
    local mischmasch="$out/mischmasch"
    cat > "$mischmasch" <<'ENDE'
# Hinweis: frueher stand hier plugin=org.kde.plasma.icontasks als Kommentar
iconTasksBackupPlugin=org.kde.plasma.icontasks

[Containments][46][Applets][79]
plugin=org.kde.plasma.icontasks

[Containments][69][Applets][117]
plugin=org.kde.plasma.icontasks

[Containments][46][Applets][79][Configuration][General]
launchers=applications:org.kde.plasma.icontasks-lookalike.desktop
ENDE
    local kommentar_vorher; kommentar_vorher="$(grep '^# Hinweis' "$mischmasch")"
    local fremdschluessel_vorher; fremdschluessel_vorher="$(grep '^iconTasksBackupPlugin=' "$mischmasch")"
    local starter_vorher; starter_vorher="$(grep '^launchers=' "$mischmasch")"

    python3 "$ROOT/migrate.py" --pruefen "$mischmasch" >/dev/null 2>&1 \
        && ok "laeuft trotz aehnlicher Teilstrings durch" \
        || fail "bricht trotz genau zweier echter Treffer faelschlich ab"

    [[ "$(grep -c '^plugin=ch.sterostxc.icontasks-tint$' "$mischmasch")" -eq 2 ]] \
        && ok "genau die zwei echten Zeilen umgestellt" \
        || fail "nicht genau zwei echte Treffer umgestellt"

    [[ "$(grep '^# Hinweis' "$mischmasch")" == "$kommentar_vorher" ]] \
        && ok "Kommentar mit gleichem Teilstring unveraendert" \
        || fail "Kommentarzeile wurde faelschlich mitveraendert"

    [[ "$(grep '^iconTasksBackupPlugin=' "$mischmasch")" == "$fremdschluessel_vorher" ]] \
        && ok "andere Schluesselzeile mit gleichem Teilstring unveraendert" \
        || fail "eine fremde Schluesselzeile wurde faelschlich mitveraendert"

    [[ "$(grep '^launchers=' "$mischmasch")" == "$starter_vorher" ]] \
        && ok "Starterzeile mit gleichem Teilstring unveraendert" \
        || fail "eine Starterzeile wurde faelschlich mitveraendert"

    # --zurueck ohne je angelegte Sicherung: muss abbrechen, darf die Zieldatei
    # nicht anfassen. Ueber --pruefen simuliert, damit weder die echte Konfiguration
    # noch plasmashell/systemctl beruehrt werden.
    local keine_sicherung="$out/keine-sicherung"
    printf 'platzhalter\n' > "$keine_sicherung"
    if python3 "$ROOT/migrate.py" --zurueck --pruefen "$keine_sicherung" >/dev/null 2>&1; then
        fail "--zurueck laeuft ohne Sicherung trotzdem durch"
    else
        ok "--zurueck ohne Sicherung bricht ab"
    fi
    [[ "$(cat "$keine_sicherung")" == "platzhalter" ]] \
        && ok "Zieldatei bei fehlender Sicherung unveraendert" \
        || fail "Zieldatei wurde trotz fehlender Sicherung veraendert"

    # Sicherung vorhanden, aber die Konfiguration wurde seit der Migration erneut
    # veraendert (Pruefsumme passt nicht mehr): Wiederherstellen darf diese
    # zwischenzeitliche Aenderung nicht stillschweigend verwerfen.
    local veraendert="$out/veraendert"
    printf 'stand-nach-migration-und-weiterer-aenderung\n' > "$veraendert"
    printf 'stand-vor-migration\n' > "$veraendert.vor-migration"
    printf 'falsche-pruefsumme-simuliert-veraltete-sicherung\n' > "$veraendert.vor-migration.stand"
    local veraendert_vorher; veraendert_vorher="$(cat "$veraendert")"
    if python3 "$ROOT/migrate.py" --zurueck --pruefen "$veraendert" >/dev/null 2>&1; then
        fail "--zurueck stellt trotz nicht passender Pruefsumme wieder her"
    else
        ok "--zurueck bricht bei nicht passender Pruefsumme ab"
    fi
    [[ "$(cat "$veraendert")" == "$veraendert_vorher" ]] \
        && ok "zwischenzeitliche Aenderung bleibt bei Abbruch erhalten" \
        || fail "zwischenzeitliche Aenderung wurde stillschweigend verworfen"

    # Gutfall: Sicherung und Pruefsumme passen zusammen - Wiederherstellen muss
    # tatsaechlich funktionieren, sonst waere die ganze Absicherung wertlos.
    local ok_datei="$out/wiederherstellen-ok"
    printf 'stand-nach-migration\n' > "$ok_datei"
    printf 'stand-vor-migration\n' > "$ok_datei.vor-migration"
    python3 -c "
import hashlib, sys
text = open(sys.argv[1], encoding='utf-8').read()
open(sys.argv[1] + '.vor-migration.stand', 'w', encoding='utf-8').write(hashlib.sha256(text.encode('utf-8')).hexdigest())
" "$ok_datei"
    python3 "$ROOT/migrate.py" --zurueck --pruefen "$ok_datei" >/dev/null 2>&1 \
        && ok "--zurueck laeuft bei passender Pruefsumme durch" \
        || fail "--zurueck bricht trotz passender Pruefsumme ab"
    [[ "$(cat "$ok_datei")" == "stand-vor-migration" ]] \
        && ok "Wiederherstellung stellt den Stand vor der Migration her" \
        || fail "Wiederherstellung hat nicht den Stand vor der Migration hergestellt"

    # Vollstaendiger Rueckbau: nach erfolgreicher Wiederherstellung duerfen keine
    # verwaisten Dateien liegen bleiben - sonst weiss spaeter niemand mehr, wozu
    # sie gehoeren (Fix-Runde 1).
    [[ ! -e "$ok_datei.vor-migration" && ! -e "$ok_datei.vor-migration.stand" ]] \
        && ok "Sicherung und Pruefsumme werden nach erfolgreicher Wiederherstellung entfernt" \
        || fail "Sicherung oder Pruefsumme bleiben nach der Wiederherstellung als Datenmuell liegen"

    # Ein zweiter --zurueck-Aufruf direkt danach darf nicht behaupten, die Datei
    # sei "seit der Migration erneut veraendert" worden - das waere schlicht falsch,
    # es steht dort der korrekt wiederhergestellte Ausgangszustand (Fix-Runde 1).
    local zweite_ausgabe
    zweite_ausgabe="$(python3 "$ROOT/migrate.py" --zurueck --pruefen "$ok_datei" 2>&1)"
    if [[ $? -eq 0 ]]; then
        fail "zweiter --zurueck-Aufruf nach erfolgreicher Wiederherstellung meldet faelschlich Erfolg"
    else
        ok "zweiter --zurueck-Aufruf nach erfolgreicher Wiederherstellung bricht ab"
    fi
    [[ "$zweite_ausgabe" != *"wurde seit der Migration erneut veraendert"* ]] \
        && ok "Meldung behauptet keine erneute Veraenderung mehr, die nie stattfand" \
        || fail "Meldung behauptet weiterhin faelschlich eine erneute Veraenderung"

    # --erzwingen ohne --zurueck wirkt nirgends - das darf nicht stillschweigend
    # geschluckt werden, sondern muss dem Aufrufer auffallen (Fix-Runde 1).
    local erzwingen_ausgabe erzwingen_code
    erzwingen_ausgabe="$(python3 "$ROOT/migrate.py" --pruefen "$out/nicht-vorhanden" --erzwingen 2>&1)"
    erzwingen_code=$?
    [[ "$erzwingen_code" -ne 0 ]] \
        && ok "--erzwingen ohne --zurueck wird abgelehnt statt stillschweigend geschluckt" \
        || fail "--erzwingen ohne --zurueck laeuft stillschweigend durch"
    [[ "$erzwingen_ausgabe" == *"--erzwingen"* && "$erzwingen_ausgabe" == *"--zurueck"* ]] \
        && ok "Meldung erklaert, dass --erzwingen nur mit --zurueck wirkt" \
        || fail "Meldung erklaert die Ablehnung von --erzwingen nicht verstaendlich"
}

case "${1:-all}" in
    extract)    test_extract ;;
    hoverspin)  test_hoverspin ;;
    iconeffect) test_iconeffect ;;
    patch)      test_patch ;;
    migrate)    test_migrate ;;
    all)        test_extract; test_hoverspin; test_iconeffect; test_patch; test_migrate ;;
    *)          printf 'unbekannter Test: %s\n' "$1"; exit 2 ;;
esac

[[ "$FAILED" -eq 0 ]] && printf '\nalle Tests bestanden\n' || printf '\nes gab Fehler\n'
exit "$FAILED"
