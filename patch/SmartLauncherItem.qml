/*
    SPDX-FileCopyrightText: 2026 Stephan <StephanRosin@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
    Ersatz fuer den C++-Typ SmartLauncherItem aus dem mitgelieferten Task-Manager.

    Wie Backend steckt auch dieser Typ nur in der Applet-Bibliothek und laesst
    sich aus einem eigenstaendigen Widget heraus nicht laden. Er liefert im
    Original Fortschrittsbalken und Ungelesen-Zaehler fuer Anwendungen, die die
    Unity-Launcher-DBus-Schnittstelle bedienen (z. B. Downloadfortschritt im
    Dateimanager, Ungelesen-Zahl im Mail-Client).

    Bewusst hingenommen: Fortschrittsbalken und Unity-Zaehler entfallen. Einzige
    Ausnahme ist Thunderbird, das unter Linux ohnehin keinen Unity-Zaehler sendet:
    Sein Add-on tb-unread (Repo ~/thunderbird-unread) schreibt die Ungelesen-Zahl
    des kombinierten Posteingangs nach ~/.cache/thunderbird-unread, und dieser Typ
    liest sie fuer TaskBadgeOverlay.qml. Die normale Aufmerksamkeitsanzeige ueber
    task.model.IsDemandingAttention bleibt unabhaengig davon erhalten - sie
    kommt direkt aus dem Fenstermanager, nicht von diesem Typ.
*/
import QtQuick
import org.kde.plasma.plasma5support as P5Support

QtObject {
    id: root

    // Wird von Task.qml gesetzt (Qt.binding an model.LauncherUrlWithoutIcon).
    property url launcherUrl

    readonly property string mailLauncher: "org.mozilla.Thunderbird.desktop"
    readonly property string unreadCountCommand: "cat \"$HOME\"/.cache/thunderbird-unread 2>/dev/null"
    // Das Add-on meldet Aenderungen sofort; die Taskleiste fragt die Datei so oft ab.
    readonly property int unreadPollMs: 3000
    readonly property bool isMailClient: String(launcherUrl).endsWith(mailLauncher)

    // --- Antworten fuer TaskBadgeOverlay.qml und TaskProgressOverlay.qml ---
    property int count: 0
    readonly property bool countVisible: count > 0
    property real progress: 0
    property bool progressVisible: false
    property bool urgent: false

    property var unreadCountReader: P5Support.DataSource {
        engine: "executable"
        interval: root.unreadPollMs
        connectedSources: root.isMailClient ? [root.unreadCountCommand] : []
        onNewData: (source, data) => root.count = root.parseCount(data["stdout"])
    }

    // Fehlende oder kaputte Datei heisst: nichts anzeigen.
    function parseCount(text) {
        const parsed = parseInt(text, 10);
        return Number.isInteger(parsed) && parsed > 0 ? parsed : 0;
    }
}
