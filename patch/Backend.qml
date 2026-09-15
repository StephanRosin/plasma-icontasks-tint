/*
    SPDX-FileCopyrightText: 2026 Stephan <StephanRosin@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
    Ersatz fuer den C++-Typ Backend aus dem mitgelieferten Task-Manager.

    Der echte Backend steckt in der Applet-Bibliothek und laesst sich aus einem
    eigenstaendigen Widget heraus nicht laden - sie ist ein Plasma-Applet-Plugin und
    kein QQmlEngineExtensionPlugin. Alle vierzehn Verwendungsstellen sind peripher:
    Kontextmenue-Extras, die Zielgeometrie der Minimier-Animation und die Zuordnung
    von Audiostroemen. Dieser Ersatz liefert dafuer neutrale Antworten.

    Bewusst hingenommen: Jump Lists, "Zuletzt benutzt" und "Orte" fehlen im
    Rechtsklickmenue, die Lautsprechersymbole werden Fenstern ungenauer zugeordnet,
    und das Anheften per Ziehen einer .desktop-Datei auf die Leiste entfaellt.
*/
import QtQuick

QtObject {
    id: root

    // Reihenfolge wie in main.xml und ConfigBehavior.qml: None=0 ... BringToCurrentDesktop=5
    enum MiddleClickAction {
        None,
        Close,
        NewInstance,
        ToggleMinimized,
        ToggleGrouping,
        BringToCurrentDesktop
    }

    // Der echte Backend sendet dies beim Ziehen einer Anwendung auf die Leiste.
    // Hier bleibt es ohne Sender - main.qml verbindet sich lediglich darauf.
    signal addLauncher(url url)

    // ContextMenu.qml verbindet sich zusaetzlich auf backend.showAllPlaces. Da
    // placesActions() hier immer leer zurueckgibt, wird das Signal nie gebraucht -
    // es muss aber existieren, sonst bricht die Verbindung mit einem Laufzeitfehler.
    signal showAllPlaces()

    // --- Kontextmenue-Extras: bewusst leer ---
    function recentDocumentActions(launcherUrl, parentMenu) { return []; }
    function placesActions(launcherUrl, showAllPlaces, parentMenu) { return []; }
    function jumpListActions(launcherUrl, parentMenu) { return []; }
    function applicationCategories(launcherUrl) { return []; }
    function isApplication(url) { return false; }
    function setActionGroup(action) { /* ohne Wirkung */ }

    // ContextMenu.qml ruft .toString() auf dem Rueckgabewert auf.
    function tryDecodeApplicationsUrl(url) { return url; }

    // PulseAudio.qml ordnet Audiostroeme ueber den Elternprozess zu.
    // -1 heisst "unbekannt" und fuehrt dort zu keiner Zuordnung.
    function parentPid(pid) { return -1; }

    // Bildschirmkoordinaten eines Task-Elements, Ziel der Minimier-Animation.
    function globalRect(item) {
        if (!item || !item.width) {
            return Qt.rect(0, 0, 0, 0);
        }
        const punkt = item.mapToGlobal(0, 0);
        return Qt.rect(punkt.x, punkt.y, item.width, item.height);
    }
}
