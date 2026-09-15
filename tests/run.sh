#!/usr/bin/env bash
# Testlaeufer des Projekts. Ohne Argument laufen alle Tests.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

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

case "${1:-all}" in
    extract) test_extract ;;
    all)     test_extract ;;
    *)       printf 'unbekannter Test: %s\n' "$1"; exit 2 ;;
esac

[[ "$FAILED" -eq 0 ]] && printf '\nalle Tests bestanden\n' || printf '\nes gab Fehler\n'
exit "$FAILED"
