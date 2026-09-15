// Prueft IconEffect ohne Plasma: sind Ruhe- und Hover-Zustand richtig,
// und wird zwischen ihnen ueberblendet statt gesprungen?
import QtQuick
import "../../patch"

Item {
    id: root
    width: 64
    height: 64

    property int failures: 0

    function check(bedingung, was) {
        if (bedingung) {
            console.log("  ok   " + was);
        } else {
            console.log("  FAIL " + was);
            root.failures++;
        }
    }

    // Hinweis: quelle.layer.effect wuerde IconEffect wie in Task 5 ueber
    // layer.effect einhaengen - das ist der Produktivweg. Auf diesem Qt
    // legt Qt das erzeugte Effekt-Objekt aber nicht als Kind von quelle ab
    // (quelle.children.length bleibt 0), daher ist es im Test nicht ueber
    // quelle.children[0] erreichbar. Deshalb hier die im Briefing (Step 4)
    // dokumentierte Alternative: IconEffect als Geschwister mit explizitem
    // source, direkt referenzierbar. Der Produktivcode in Task 5 nutzt
    // weiterhin layer.effect unveraendert.
    Rectangle {
        id: quelle
        width: 40
        height: 40
        color: "red"
    }

    IconEffect {
        id: effekt
        objectName: "effekt"
        source: quelle
        hovered: root.gehovert
    }

    property bool gehovert: false

    function effektHolen() {
        return effekt;
    }

    SequentialAnimation {
        running: true

        PauseAnimation { duration: 100 }
        ScriptAction {
            script: {
                const e = root.effektHolen();
                root.check(e !== null, "Effekt ist eingehaengt");
                root.check(Math.abs(e.saturation) < 0.01, "Ruhe: Saettigung neutral (Toenung darf nicht zerstoert werden)");
                root.check(Math.abs(e.colorization - 1.0) < 0.01, "Ruhe: voll getoent");
                root.check(e.colorizationColor.toString() === "#9b6dff", "Ruhe: Toenung ist das Violett");
                root.gehovert = true;
            }
        }
        PauseAnimation { duration: 60 }
        ScriptAction {
            script: {
                const e = root.effektHolen();
                root.check(e.colorization > 0.01 && e.colorization < 0.99,
                           "blendet ueber statt zu springen");
            }
        }
        PauseAnimation { duration: 250 }
        ScriptAction {
            script: {
                const e = root.effektHolen();
                root.check(Math.abs(e.saturation) < 0.01, "Hover: Saettigung neutral");
                root.check(Math.abs(e.colorization) < 0.01, "Hover: keine Toenung mehr");
                Qt.exit(root.failures);
            }
        }
    }
}
