import QtQuick
import LocalTube

// The small autoplay switch in the right control pill.
PillButton {
    id: root

    property bool checked: false

    tooltip: checked ? qsTr("Autoplay is on") : qsTr("Autoplay is off")

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: 30
        height: 18
        radius: 9
        color: root.checked ? Theme.white : Qt.rgba(1, 1, 1, 0.3)
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

        Icon {
            width: 14
            height: 14
            y: 2
            x: root.checked ? track.width - width - 2 : 2
            icon: root.checked ? Icons.play : Icons.pause
            color: root.checked ? "#000000" : Theme.white
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
        }
    }
}
