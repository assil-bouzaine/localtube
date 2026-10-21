import QtQuick
import LocalTube

// Switch used in menu rows (ytp-menuitem-toggle-checkbox).
Item {
    id: root

    property bool checked: false

    implicitWidth: 40
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.checked ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.3)
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
    }
    Rectangle {
        width: 20
        height: 20
        radius: 10
        y: 2
        x: root.checked ? 18 : 2
        color: root.checked ? Theme.white : Theme.textSecondary
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
    }
}
