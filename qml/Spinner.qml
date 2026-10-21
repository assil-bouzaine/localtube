import QtQuick
import QtQuick.Shapes
import LocalTube

// Material-style indeterminate spinner (YouTube's buffering indicator). Only
// appears if loading takes longer than a moment, to avoid flicker on seeks.
Item {
    id: root

    property bool big: false
    property bool active: false
    property real t: 0
    property int cycle: 0
    readonly property real stroke: big ? 9 : 6

    width: big ? 96 : 64
    height: width
    opacity: 0
    visible: opacity > 0

    Timer {
        id: delay
        interval: 400
        running: root.active
        onTriggered: root.opacity = 1
    }
    onActiveChanged: if (!active) opacity = 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    // cubic-bezier(.4, 0, .2, 1) is close enough to an ease-in-out cubic.
    function ease(x) {
        return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2
    }
    readonly property real head: t < 0.5 ? 270 * ease(t * 2) : 270
    readonly property real tail: t < 0.5 ? 0 : 270 * ease((t - 0.5) * 2)

    SequentialAnimation {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 1333 }
        ScriptAction { script: root.cycle = (root.cycle + 1) % 4 }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 1568
            loops: Animation.Infinite
            running: root.visible
        }

        ShapePath {
            strokeColor: "#dddddd"
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.stroke / 2
                radiusY: radiusX
                startAngle: root.cycle * 270 + root.tail - 90
                sweepAngle: Math.max(12, root.head - root.tail)
            }
        }
    }
}
