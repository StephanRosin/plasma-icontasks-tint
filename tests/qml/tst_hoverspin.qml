// Prueft HoverSpin ohne Plasma: dreht es, verkleinert es, und kommt es sauber zurueck?
import QtQuick
import "../../patch"

Item {
    id: root
    width: 64
    height: 64

    property int failures: 0
    property real winkelVorher: 0

    function check(bedingung, was) {
        if (bedingung) {
            console.log("  ok   " + was);
        } else {
            console.log("  FAIL " + was);
            root.failures++;
        }
    }

    Rectangle {
        id: dummy
        width: 40
        height: 40
        color: "red"
    }

    HoverSpin {
        id: spin
        target: dummy
    }

    SequentialAnimation {
        running: true

        ScriptAction {
            script: {
                root.check(dummy.rotation === 0, "Startwinkel ist 0");
                root.check(dummy.scale === 1, "Startgroesse ist 1");
                spin.hovered = true;
            }
        }
        PauseAnimation { duration: 300 }
        ScriptAction {
            script: {
                root.winkelVorher = dummy.rotation;
                root.check(dummy.rotation > 0, "dreht sich nach dem Hover");
                root.check(dummy.scale < 0.75, "verkleinert sich beim Hover");
            }
        }
        PauseAnimation { duration: 300 }
        ScriptAction {
            script: {
                root.check(dummy.rotation !== root.winkelVorher, "dreht ununterbrochen weiter");
                spin.hovered = false;
            }
        }
        PauseAnimation { duration: 700 }
        ScriptAction {
            script: {
                root.check(Math.abs(dummy.rotation) < 0.01, "steht wieder auf 0 Grad");
                root.check(Math.abs(dummy.scale - 1) < 0.01, "hat wieder volle Groesse");
                Qt.exit(root.failures);
            }
        }
    }
}
