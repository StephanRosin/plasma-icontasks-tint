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

    Bewusst hingenommen: Fortschrittsbalken und Ungelesen-Zaehler entfallen fuer
    alle Anwendungen. Die normale Aufmerksamkeitsanzeige ueber
    task.model.IsDemandingAttention bleibt unabhaengig davon erhalten - sie
    kommt direkt aus dem Fenstermanager, nicht von diesem Typ.
*/
import QtQuick

QtObject {
    id: root

    // Wird von Task.qml einmalig gesetzt (Qt.binding an model.LauncherUrlWithoutIcon),
    // hier aber von keiner Stelle im uebernommenen Code gelesen. Nur noetig, damit
    // die Zuweisung nicht mit einem Laufzeitfehler auf ein nicht existierendes
    // Property scheitert.
    property url launcherUrl

    // --- neutrale Antworten fuer TaskBadgeOverlay.qml und TaskProgressOverlay.qml ---
    property bool countVisible: false
    property int count: 0
    property real progress: 0
    property bool progressVisible: false
    property bool urgent: false
}
