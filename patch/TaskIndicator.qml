/*
    SPDX-FileCopyrightText: 2026 Stephan <StephanRosin@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
    Ersetzt den eckigen Block aus widgets/tasks des Plasma-Themas: eine abgerundete Flaeche
    beim Ueberfahren und fuer das aktive Fenster, darunter ein Punkt fuer jedes offene
    Fenster (wie im Dock). Farben nur aus dem Kirigami-Thema, damit das Farbthema mitfaerbt.
    Kirigami.Units.shortDuration ist 0, wenn Animationen im System abgeschaltet sind.
*/
import QtQuick

import org.kde.kirigami as Kirigami

Item {
    id: root

    // ---- Schnittstelle ----
    property bool hovered: false
    property bool isWindow: false
    property bool active: false
    property bool minimized: false
    property bool attention: false

    // ---- Stellschrauben ----
    property real inset: 4           // Abstand der Flaeche zum Rand der Kachel
    property real dotSize: 4
    property real activeDotWidth: 14  // der Punkt des aktiven Fensters wird zum Strich

    readonly property color ink: Kirigami.Theme.textColor

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.inset
        radius: Kirigami.Units.cornerRadius * 2
        color: root.ink
        opacity: root.active ? 0.10 : root.hovered ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Rectangle {
        visible: root.isWindow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        width: root.active ? root.activeDotWidth : root.dotSize
        height: root.dotSize
        radius: height / 2
        color: root.attention ? Kirigami.Theme.neutralTextColor : root.ink
        opacity: root.attention || root.active ? 1 : root.minimized ? 0.35 : 0.55
        Behavior on width { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }
}
