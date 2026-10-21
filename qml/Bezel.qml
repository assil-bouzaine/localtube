import QtQuick
import LocalTube

// The icon that flashes in the centre on play/pause/volume changes, and the
// text box near the top (volume %, speed...). Timing follows YouTube's
// ytp-delhi-modern-bezel-fadeout keyframes: fade in and grow to 1.33x over the
// first quarter of a second, hold, then fade back out.
Item {
    id: root

    property bool big: false
    property var icon: null
    property string text: ""
    readonly property bool active: circle.opacity > 0 || textBox.opacity > 0

    function flash(icon, text) {
        root.icon = icon
        root.text = text || ""
        if (icon)
            restart(circleIn, circleHold, circle)
        else
            hideNow(circle, circleIn, circleHold)
        if (root.text)
            restart(textIn, textHold, textBox)
        else
            hideNow(textBox, textIn, textHold)
    }

    function flashText(text) {
        flash(null, text)
    }

    function cancel() {
        hideNow(circle, circleIn, circleHold)
        hideNow(textBox, textIn, textHold)
    }

    // A bezel that is already showing just extends its hold instead of
    // fading out and in again (e.g. holding a volume key).
    function restart(fullAnimation, holdAnimation, item) {
        if (item.opacity > 0.3 && (fullAnimation.running || holdAnimation.running)) {
            fullAnimation.stop()
            holdAnimation.restart()
        } else {
            holdAnimation.stop()
            fullAnimation.restart()
        }
    }

    function hideNow(item, a, b) {
        a.stop()
        b.stop()
        item.opacity = 0
    }

    Item {
        id: circle
        anchors.centerIn: parent
        width: 78
        height: 78
        opacity: 0

        Frosted {
            anchors.fill: parent
            radius: width / 2
            tint: Theme.tintMedium
        }
        Icon {
            anchors.centerIn: parent
            readonly property real size: root.icon && root.icon.box[2] === 36 ? 54 : 36
            width: size
            height: size
            icon: root.icon
        }
    }

    SequentialAnimation {
        id: circleIn
        ParallelAnimation {
            NumberAnimation { target: circle; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
            NumberAnimation { target: circle; property: "scale"; from: 1; to: 1.33; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
        PauseAnimation { duration: 500 }
        ParallelAnimation {
            NumberAnimation { target: circle; property: "opacity"; to: 0; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
            NumberAnimation { target: circle; property: "scale"; to: 1; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
    }

    SequentialAnimation {
        id: circleHold
        PropertyAction { target: circle; property: "opacity"; value: 1 }
        PropertyAction { target: circle; property: "scale"; value: 1.33 }
        PauseAnimation { duration: 500 }
        ParallelAnimation {
            NumberAnimation { target: circle; property: "opacity"; to: 0; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
            NumberAnimation { target: circle; property: "scale"; to: 1; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
    }

    Item {
        id: textBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.1
        width: label.implicitWidth + 40
        height: label.implicitHeight + 20
        opacity: 0

        Frosted {
            anchors.fill: parent
            radius: 8
            tint: Theme.tintMedium
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: root.big ? 27 : 19
        }
    }

    SequentialAnimation {
        id: textIn
        NumberAnimation { target: textBox; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: textBox; property: "opacity"; to: 0; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
    }

    SequentialAnimation {
        id: textHold
        PropertyAction { target: textBox; property: "opacity"; value: 1 }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: textBox; property: "opacity"; to: 0; duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
    }
}
