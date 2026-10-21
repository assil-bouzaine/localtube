import QtQuick

// Frosted-glass background (backdrop blur + dark tint, rounded corners).
// Falls back to a translucent fill when no video is available to blur.
Item {
    id: root

    property real radius: height / 2
    property real tint: Theme.tintLight

    readonly property bool glass: Theme.blurSource !== null && Theme.blurEnabled
    readonly property real dpr: Window.window ? Window.window.devicePixelRatio : 1

    ShaderEffect {
        anchors.fill: parent
        visible: root.glass
        blending: true

        property variant source: Theme.blurSource
        property size itemSize: Qt.size(width, height)
        property real radius: root.radius
        property real tint: root.tint
        property rect area: Theme.blurArea
        property size viewport: Qt.size((root.Window.width || 1) * root.dpr, (root.Window.height || 1) * root.dpr)
        property real dpr: root.dpr
        property real lod: 3.2

        fragmentShader: "qrc:/shaders/frosted.frag.qsb"
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.glass
        radius: Math.min(root.radius, width / 2, height / 2)
        color: Qt.rgba(0.08, 0.08, 0.08, Math.min(0.95, root.tint + 0.45))
    }
}
