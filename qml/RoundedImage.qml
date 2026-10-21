import QtQuick

// An image with anti-aliased rounded corners (cropped to fill).
Item {
    id: root

    property alias source: image.source
    property real radius: 8
    property alias status: image.status

    Image {
        id: image
        anchors.fill: parent
        visible: false
        asynchronous: false
        cache: true
        smooth: true
        mipmap: true
        sourceSize.width: Math.max(64, root.width * 2)
    }

    ShaderEffect {
        anchors.fill: parent
        visible: image.status === Image.Ready
        property variant source: image
        property size itemSize: Qt.size(width, height)
        property real radius: root.radius
        property real dpr: root.Window.window ? root.Window.window.devicePixelRatio : 1
        // Crop the texture like Image.PreserveAspectCrop would.
        property rect uvRect: {
            const iw = image.implicitWidth, ih = image.implicitHeight
            if (iw <= 0 || ih <= 0 || width <= 0 || height <= 0)
                return Qt.rect(0, 0, 1, 1)
            const imageAspect = iw / ih
            const itemAspect = width / height
            if (imageAspect > itemAspect) {
                const w = itemAspect / imageAspect
                return Qt.rect((1 - w) / 2, 0, w, 1)
            }
            const h = imageAspect / itemAspect
            return Qt.rect(0, (1 - h) / 2, 1, h)
        }
        fragmentShader: "qrc:/shaders/rounded.frag.qsb"
    }
}
