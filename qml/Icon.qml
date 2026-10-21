import QtQuick
import QtQuick.Shapes

// Renders one of the vector icons from Icons.qml at any size, anti-aliased by
// the GPU curve renderer.
Item {
    id: root

    property var icon
    property color color: Theme.white

    implicitWidth: 24
    implicitHeight: 24

    readonly property var box: icon ? icon.box : [0, 0, 24, 24]

    Shape {
        width: root.box[2]
        height: root.box[3]
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Translate { x: -root.box[0]; y: -root.box[1] },
            Scale { xScale: root.width / root.box[2]; yScale: root.height / root.box[3] }
        ]

        ShapePath {
            fillColor: root.color
            strokeWidth: -1
            strokeColor: "transparent"
            fillRule: root.icon && root.icon.evenOdd ? ShapePath.OddEvenFill : ShapePath.WindingFill
            PathSvg { path: root.icon ? root.icon.d : "" }
        }
    }
}
