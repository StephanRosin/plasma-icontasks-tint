/*
    Dreht `target`, solange `hovered` gilt, und verkleinert es dabei.

    Das Verkleinern ist keine Zier: Das Symbol fuellt die Panelhoehe fast aus, und ein um
    45 Grad gedrehtes Quadrat braucht das 1,41-fache seiner Kantenlaenge. Ohne das Schrumpfen
    schneidet der Panelrand die Ecken eckiger Symbole ab.

    Bewusst RotationAnimation statt RotationAnimator: Animator-Typen laufen im Render-Thread
    und aktualisieren die QML-Eigenschaft waehrend der Animation nicht. Dann laese
    beiRuhe() einen veralteten Winkel und das Zurueckdrehen sprigne.
*/
import QtQuick

Item {
    id: root

    // ---- Schnittstelle ----
    property Item target: null
    property bool hovered: false

    // ---- Stellschrauben ----
    property int spinPeriod: 900      // ms je Umdrehung, solange gehovert wird
    property int settleDuration: 400  // ms zum Zurueckdrehen auf 0 Grad
    property int scaleDuration: 150   // ms fuer das Verkleinern und Zurueckwachsen
    property real spinScale: 0.68     // 1/Wurzel(2) mit etwas Reserve

    // Das Element ist reine Steuerung und darf nichts zeichnen.
    width: 0
    height: 0
    visible: false

    onHoveredChanged: hovered ? beiHover() : beiRuhe()

    function beiHover() {
        if (!target) {
            return;
        }
        settle.stop();
        target.transformOrigin = Item.Center;
        spinner.from = target.rotation;
        spinner.to = target.rotation + 360;
        spinner.restart();
        groesse.to = root.spinScale;
        groesse.restart();
    }

    function beiRuhe() {
        if (!target) {
            return;
        }
        spinner.stop();
        // Auf [0,360) normieren und den kuerzeren der beiden Wege nach 0 nehmen.
        const winkel = ((target.rotation % 360) + 360) % 360;
        target.rotation = winkel;
        settle.to = winkel > 180 ? 360 : 0;
        settle.restart();
        groesse.to = 1.0;
        groesse.restart();
    }

    RotationAnimation {
        id: spinner
        target: root.target
        property: "rotation"
        direction: RotationAnimation.Numerical
        duration: root.spinPeriod
        loops: Animation.Infinite
        running: false
    }

    NumberAnimation {
        id: settle
        target: root.target
        property: "rotation"
        duration: root.settleDuration
        easing.type: Easing.OutCubic
        // Nach dem Weg ueber 360 wieder auf den gleichwertigen Wert 0 setzen,
        // damit der naechste Hover nicht bei 360 anfaengt.
        onFinished: if (root.target) { root.target.rotation = 0; }
    }

    NumberAnimation {
        id: groesse
        target: root.target
        property: "scale"
        duration: root.scaleDuration
        easing.type: Easing.OutQuad
    }
}
