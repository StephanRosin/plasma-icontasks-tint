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

case "${1:-all}" in
    extract)    test_extract ;;
    hoverspin)  test_hoverspin ;;
    iconeffect) test_iconeffect ;;
    all)        test_extract; test_hoverspin; test_iconeffect ;;
    *)          printf 'unbekannter Test: %s\n' "$1"; exit 2 ;;
esac

[[ "$FAILED" -eq 0 ]] && printf '\nalle Tests bestanden\n' || printf '\nes gab Fehler\n'
exit "$FAILED"
