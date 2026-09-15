/*
    Faerbt ein Symbol ein: im Ruhezustand entsaettigt und Richtung Akzentblau getoent,
    unter dem Mauszeiger wieder in seinen echten Farben.

    Wird als layer.effect eines Kirigami.Icon eingehaengt. Qt bindet dabei `source`
    selbst an die Layer-Textur und blendet die Quelle aus - deshalb steht hier kein
    `source` und keine Sichtbarkeitsakrobatik.
*/
import QtQuick
import QtQuick.Effects

MultiEffect {
    id: root

    // ---- Schnittstelle ----
    property bool hovered: false

    // ---- Stellschrauben ----
    property color tintColor: "#3daee9"
    property real tintStrength: 0.55  // 0 = keine Toenung, 1 = volle Toenung
    property int fadeDuration: 150    // ms fuer den Farbwechsel

    saturation: hovered ? 0.0 : -1.0
    colorization: hovered ? 0.0 : root.tintStrength
    colorizationColor: root.tintColor

    Behavior on saturation {
        NumberAnimation {
            duration: root.fadeDuration
            easing.type: Easing.OutQuad
        }
    }

    Behavior on colorization {
        NumberAnimation {
            duration: root.fadeDuration
            easing.type: Easing.OutQuad
        }
    }
}
