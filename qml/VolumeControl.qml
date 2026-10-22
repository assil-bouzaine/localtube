import QtQuick
import LocalTube

// Mute button with a horizontal slider that slides out on hover.
Item {
    id: root

    required property Item player
    readonly property var mpv: player.mpv
    readonly property bool expanded: (hover.hovered || slider.pressed || sliderBox.activeFocus || muteButton.activeFocus || keepOpen.running) && !player.xsmall
    readonly property real level: mpv.muted ? 0 : mpv.volume / 100

    width: player.buttonWidth + (expanded ? 52 + 16 : 0)
    height: player.pillHeight
    Behavior on width {
        NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
    }

    // Keeps the slider visible briefly after scrolling over it.
    Timer { id: keepOpen; interval: 800 }

    Frosted {
        anchors.fill: parent
        radius: 28
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: height / 2
        color: hover.hovered ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            root.player.changeVolume(wheel.angleDelta.y > 0 ? 5 : wheel.angleDelta.y < 0 ? -5 : 0)
            keepOpen.restart()
        }
    }

    PillButton {
        id: muteButton
        width: root.player.buttonWidth
        height: parent.height
        iconSize: root.player.iconSize
        showHighlight: false
        icon: root.player.volumeIcon(root.mpv.volume, root.mpv.muted)
        tooltip: root.mpv.muted || root.mpv.volume <= 0 ? qsTr("Unmute") : qsTr("Mute")
        shortcut: "m"
        onClicked: root.player.toggleMute()
    }

    Item {
        id: sliderBox
        activeFocusOnTab: !root.player.xsmall
        Accessible.role: Accessible.Slider
        Accessible.name: qsTr("Volume")
        Accessible.description: Math.round(root.mpv.volume) + "%"
        Accessible.onIncreaseAction: root.player.changeVolume(5)
        Accessible.onDecreaseAction: root.player.changeVolume(-5)
        Keys.onLeftPressed: root.player.changeVolume(-5)
        Keys.onRightPressed: root.player.changeVolume(5)
        x: root.player.buttonWidth
        width: 52
        height: parent.height
        opacity: root.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: "transparent"
            border.width: sliderBox.activeFocus ? 2 : 0
            border.color: Theme.white
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 2
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.2)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: handle.x + handle.width / 2
            height: 2
            radius: 1
            color: Theme.white
        }
        Rectangle {
            id: handle
            width: 12
            height: 12
            radius: 6
            color: Theme.white
            anchors.verticalCenter: parent.verticalCenter
            x: root.level * (parent.width - width)
        }

        MouseArea {
            id: slider
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            preventStealing: true
            function setFrom(x) {
                const v = Math.round(Math.max(0, Math.min(1, (x - 6) / (width - 12))) * 100)
                root.mpv.volume = v
                if (root.mpv.muted && v > 0)
                    root.mpv.muted = false
            }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
        }
    }
}
