// Prueft SmartLauncherItem ohne Plasma: Die Ungelesen-Plakette gehoert nur
// Thunderbird und darf nicht an einem Eintrag haengen bleiben, dessen
// Starter danach ein anderes Programm ist.
import QtQuick
import "../../patch"

Item {
    id: root

    property int failures: 0

    function check(bedingung, was) {
        if (bedingung) {
            console.log("  ok   " + was);
        } else {
            console.log("  FAIL " + was);
            root.failures++;
        }
    }

    SmartLauncherItem {
        id: item
    }

    Component.onCompleted: {
        item.launcherUrl = "applications:org.mozilla.Thunderbird.desktop";
        item.count = item.parseCount("1\n");
        check(item.countVisible, "Thunderbird mit 1 Ungelesener zeigt die Plakette");

        item.launcherUrl = "applications:firefox.desktop";
        check(!item.countVisible, "nach Wechsel auf Firefox keine Plakette mehr");

        Qt.exit(root.failures);
    }
}
