// Prueft HoverSpin ohne Plasma: dreht es, verkleinert es, dreht es ueber die erste
// Umdrehung hinaus weiter (loops: Infinite statt loops: 1), beruecksichtigt es einen
// beim Erzeugen schon gesetzten Anfangswert von "hovered", und kommt es sauber zurueck?
import QtQuick
import "../../patch"

Item {
    id: root
    width: 64
    height: 64

    property int failures: 0
    property real winkelVorher: 0
    property real winkelNachErsterUmdrehung: 0

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

    // Eigenes Ziel fuer den Anfangswert-Fall: hovered wird hier deklarativ beim
    // Erzeugen auf true gesetzt, genau wie spaeter in Task.qml ueber
    // "hovered: task.highlighted", falls ein Task schon hervorgehoben ist, waehrend
    // sein Icon entsteht. onHoveredChanged feuert dafuer NICHT, das muss ueber
    // Component.onCompleted in HoverSpin selbst abgefangen werden.
    Rectangle {
        id: dummyAnfangAn
        width: 40
        height: 40
        color: "blue"
    }

    HoverSpin {
        id: spinAnfangAn
        target: dummyAnfangAn
        hovered: true
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
                root.check(dummyAnfangAn.rotation > 0,
                    "startet gedreht, wenn hovered beim Erzeugen schon true ist");
            }
        }
        PauseAnimation { duration: 300 }
        ScriptAction {
            script: {
                root.check(dummy.rotation !== root.winkelVorher,
                    "dreht innerhalb der ersten Umdrehung weiter");
            }
        }
        // Hover-Zeitraum bewusst ueber spinPeriod (900ms) hinausziehen: bis hierher
        // sind seit spin.hovered = true erst 600ms vergangen. Mit "loops: 1" waere die
        // Drehung bei 900ms fertig und bliebe danach unbeweglich stehen - das faellt
        // erst auf, wenn ueber die erste Umdrehung hinaus gemessen wird.
        PauseAnimation { duration: 400 } // insgesamt 1000ms seit Hover-Beginn
        ScriptAction {
            script: {
                root.winkelNachErsterUmdrehung = dummy.rotation;
            }
        }
        // Zweite Messung kurz danach, deutlich unter einer halben Umdrehung (450ms)
        // entfernt: nur eine laufende Animation zeigt hier garantiert einen anderen
        // Winkel. Eine einzelne Messung waere anfaellig dafuer, zufaellig genau an
        // einem Vielfachen von 360 Grad vorbeizukommen und faelschlich gleich
        // auszusehen; zwei eng benachbarte Messungen umgehen das.
        PauseAnimation { duration: 100 } // insgesamt 1100ms seit Hover-Beginn
        ScriptAction {
            script: {
                root.check(dummy.rotation !== root.winkelNachErsterUmdrehung,
                    "dreht auch ueber die erste Umdrehung hinaus weiter (loops: Infinite)");
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
