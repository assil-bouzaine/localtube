import QtQuick
import QtQuick.Shapes
import LocalTube

// Shown when seeking with the keyboard: a dark circle on the left or right
// with three chasing arrows and "N seconds" (YouTube's doubletap UI). Repeated
// presses add up.
Item {
    id: root

    property bool big: false
    property int direction: 1
    property real amount: 0
    property real phase: 0

    opacity: 0
    visible: opacity > 0

    function show(dir, seconds) {
        if (visible && dir === direction && hideTimer.running)
            amount += seconds
        else {
            direction = dir
            amount = seconds
        }
        fadeOut.stop()
        opacity = 1
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 700
        onTriggered: fadeOut.start()
    }

    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.Bezier
        easing.bezierCurve: Theme.curveOut
    }

    NumberAnimation on phase {
        from: 0
        to: 1
        duration: 1200
        loops: Animation.Infinite
        running: root.visible
    }

    // Keyframes of YouTube's arrow-fade-out-1/2/3 animations.
    readonly property var keyframes: [
        [0, 0.9, 0.6, 0.3, 0.3, 0.3, 0],
        [0, 0.3, 0.9, 0.6, 0.3, 0.3, 0],
        [0, 0.3, 0.3, 0.9, 0.6, 0.3, 0],
    ]
    function arrowOpacity(index, t) {
        const k = keyframes[index]
        const pos = t * 6
        const i = Math.min(5, Math.floor(pos))
        return k[i] + (k[i + 1] - k[i]) * (pos - i)
    }

    Item {
        id: circle
        readonly property real size: Math.max(96, Math.min(170, root.height * 0.24))
        width: size
        height: size
        x: (root.direction > 0 ? root.width * 0.84 : root.width * 0.16) - width / 2
        y: (root.height - height) / 2

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        Column {
            anchors.centerIn: parent
            spacing: 6

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                layoutDirection: root.direction > 0 ? Qt.LeftToRight : Qt.RightToLeft

                Repeater {
                    model: 3
                    delegate: Shape {
                        required property int index
                        width: 11
                        height: 14
                        preferredRendererType: Shape.CurveRenderer
                        opacity: root.arrowOpacity(index, root.phase)
                        ShapePath {
                            fillColor: "#dddddd"
                            strokeWidth: -1
                            strokeColor: "transparent"
                            startX: root.direction > 0 ? 0 : 11
                            startY: 0
                            PathLine { x: root.direction > 0 ? 11 : 0; y: 7 }
                            PathLine { x: root.direction > 0 ? 0 : 11; y: 14 }
                            PathLine { x: root.direction > 0 ? 0 : 11; y: 0 }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.amount === 1 ? qsTr("1 second") : qsTr("%1 seconds").arg(root.amount)
                color: "#dddddd"
                font.family: Theme.font
                font.weight: Font.Medium
                font.pixelSize: root.big ? 15 : 12
            }
        }
    }
}
