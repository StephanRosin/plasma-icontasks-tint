#!/usr/bin/env python3
"""Zieht die QML-Quellen des Task-Manager-Widgets aus der kompilierten Plasma-Bibliothek.

Das Widget org.kde.plasma.icontasks liefert unter /usr/share/plasma/plasmoids/ nur eine
metadata.json; sein QML steckt als Qt-Resource in der Applet-Bibliothek. Laedt man die
Bibliothek per dlopen, registriert ihr statischer Initialisierer die Resource im
Qt-Resource-System, und QFile kann sie danach unter ihrem :/-Pfad lesen.
"""

import argparse
import ctypes
import sys
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QDir, QFile, QIODevice

APPLET_LIB = "/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so"
RESOURCE_ROOT = ":/qt/qml/plasma/applet/org/kde/plasma/taskmanager"


def extract(lib: str, target: Path) -> list[str]:
    """Schreibt alle Dateien der Resource nach target und gibt ihre Namen zurueck."""
    QCoreApplication([])  # das Qt-Resource-System braucht eine Anwendungsinstanz
    ctypes.CDLL(lib, ctypes.RTLD_GLOBAL)

    source = QDir(RESOURCE_ROOT)
    if not source.exists():
        raise RuntimeError(
            f"{RESOURCE_ROOT} nicht gefunden. Entweder ist {lib} nicht das "
            "Task-Manager-Applet, oder Plasma legt sein QML inzwischen woanders ab."
        )

    target.mkdir(parents=True, exist_ok=True)
    written = []
    for name in source.entryList():
        handle = QFile(f"{RESOURCE_ROOT}/{name}")
        if not handle.open(QIODevice.ReadOnly):
            raise RuntimeError(f"{name} liess sich nicht oeffnen")
        (target / name).write_bytes(bytes(handle.readAll().data()))
        written.append(name)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path, help="Zielverzeichnis fuer die QML-Dateien")
    parser.add_argument("--lib", default=APPLET_LIB, help="Pfad zur Applet-Bibliothek")
    args = parser.parse_args()

    try:
        names = extract(args.lib, args.target)
    except (RuntimeError, OSError) as error:
        print(f"Extraktion fehlgeschlagen: {error}", file=sys.stderr)
        return 1

    print(f"{len(names)} Dateien nach {args.target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
