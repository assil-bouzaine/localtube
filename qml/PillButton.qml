import QtQuick
import LocalTube

// An icon button as used inside the control bar pills. The hover highlight is
// an inset rounded shape, like the ::before/::after layers in YouTube's CSS.
Item {
    id: root

    property var icon
    property real iconSize: 24
    property color iconColor: Theme.white
    property real iconRotation: 0
    property string tooltip
    property string shortcut
    property bool showHighlight: true
    property real highlightRadius: height
    property real insetLeft: 0
    property real insetRight: 0
    property real insetTop: 4
    property real insetBottom: 4
    readonly property alias hovered: mouse.containsMouse
    readonly property alias pressed: mouse.pressed
    default property alias content: extra.data

    signal clicked()

    implicitWidth: 48
    implicitHeight: 48
    opacity: enabled ? 1 : 0.5

    Rectangle {
        visible: root.showHighlight
        anchors.fill: parent
        anchors.leftMargin: root.insetLeft
        anchors.rightMargin: root.insetRight
        anchors.topMargin: root.insetTop
        anchors.bottomMargin: root.insetBottom
        radius: Math.min(root.highlightRadius, height / 2)
        color: mouse.pressed ? Theme.pressed : mouse.containsMouse ? Theme.hover : "transparent"
        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
    }

    Icon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        icon: root.icon
        color: root.iconColor
        rotation: root.iconRotation
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
    }

    Item {
        id: extra
        anchors.fill: parent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
        onContainsMouseChanged: {
            if (!Theme.tooltip)
                return
            if (containsMouse && root.tooltip)
                Theme.tooltip.show(root, root.tooltip, root.shortcut)
            else
                Theme.tooltip.hide(root)
        }
    }

    onTooltipChanged: if (mouse.containsMouse && Theme.tooltip) Theme.tooltip.show(root, root.tooltip, root.shortcut)
}
