import QtQuick
import LocalTube

// Frosted tooltip shown above control-bar buttons, with a key-hint chip.
Item {
    id: root

    property Item target: null
    property string text
    property string shortcut
    property real bottomY: 0
    property real targetX: 0

    function show(item, text, shortcut) {
        root.text = text
        root.shortcut = shortcut || ""
        targetX = item.mapToItem(parent, item.width / 2, 0).x
        target = item
    }

    function hide(item) {
        if (target === item)
            target = null
    }

    width: content.implicitWidth + 18
    height: content.implicitHeight + 12
    x: Math.max(8, Math.min(parent.width - width - 8, targetX - width / 2))
    y: bottomY - height
    opacity: target && target.visible ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    Frosted {
        anchors.fill: parent
        radius: 8
        tint: Theme.tintLight
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: Theme.text
            font.family: Theme.font
            font.weight: Font.Medium
            font.pixelSize: 13
        }
        Rectangle {
            visible: root.shortcut !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(17, key.implicitWidth + 8)
            height: key.implicitHeight + 2
            radius: 4
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.3)
            Text {
                id: key
                anchors.centerIn: parent
                text: root.shortcut
                color: Theme.text
                font.family: Theme.font
                font.weight: Font.Medium
                font.pixelSize: 12
            }
        }
    }
}
