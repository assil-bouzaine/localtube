import QtQuick
import QtQuick.Shapes
import LocalTube

// End of video: the "Up next" autoplay countdown, or a grid of more videos
// from the folder (YouTube's end screen) when autoplay is off or cancelled.
Item {
    id: root

    required property Item player
    property bool countdown: false
    property bool endScreen: false
    property real progress: 0
    readonly property bool active: countdown || endScreen
    readonly property int seconds: 5

    visible: opacity > 0
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    function start() {
        if (!player.nextItem) {
            showEndScreen()
            return
        }
        endScreen = false
        countdown = true
        timer.restart()
    }
    function cancel() {
        timer.stop()
        countdown = false
        endScreen = false
    }
    function showEndScreen() {
        timer.stop()
        countdown = false
        endScreen = player.endScreenItems.length > 0
    }
    function playNow() {
        timer.stop()
        countdown = false
        player.nextRequested()
    }

    NumberAnimation {
        id: timer
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.seconds * 1000
        onFinished: if (root.countdown) root.playNow()
    }

    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: -root.anchors.bottomMargin
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: root.player.fullscreenToggled()
    }

    // ------------------------------------------------- autoplay countdown
    Column {
        id: card
        visible: root.countdown
        anchors.centerIn: parent
        width: Math.min(root.width - 48, root.player.bigMode ? 480 : 360)
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Up next in %1").arg(Math.max(1, Math.ceil(root.seconds * (1 - root.progress))))
            color: Theme.textSecondary
            font.family: Theme.font
            font.pixelSize: root.player.bigMode ? 18 : 15
        }

        Item {
            width: parent.width
            height: Math.min(Math.round(width * 9 / 16), root.height * 0.4)

            RoundedImage {
                id: nextThumb
                anchors.fill: parent
                radius: 12
                source: root.player.nextItem ? root.player.nextItem.poster : ""
            }
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: nextThumb.status === Image.Ready ? Qt.rgba(0, 0, 0, 0.25) : Theme.surface
            }

            // Circular countdown around a play button.
            Item {
                anchors.centerIn: parent
                width: 64
                height: 64
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.rgba(0, 0, 0, 0.6)
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.white
                        strokeWidth: 4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 32
                            centerY: 32
                            radiusX: 30
                            radiusY: 30
                            startAngle: -90
                            sweepAngle: 360 * root.progress
                        }
                    }
                }
                Icon {
                    anchors.centerIn: parent
                    width: 36
                    height: 36
                    icon: Icons.play
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.playNow()
            }
        }

        Text {
            width: parent.width
            text: root.player.nextItem ? root.player.nextItem.title : ""
            color: Theme.text
            font.family: Theme.font
            font.weight: Font.Medium
            font.pixelSize: root.player.bigMode ? 22 : 18
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: root.player.nextItem && root.player.nextItem.duration > 0 ? Theme.formatTime(root.player.nextItem.duration) : ""
            color: Theme.textSecondary
            font.family: Theme.font
            font.pixelSize: 14
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            topPadding: 4

            TextButton {
                text: qsTr("Cancel")
                onClicked: root.showEndScreen()
            }
            TextButton {
                text: qsTr("Play now")
                primary: true
                onClicked: root.playNow()
            }
        }
    }

    component TextButton: Item {
        id: button
        property string text
        property bool primary: false
        signal clicked()
        width: label.implicitWidth + 32
        height: 36
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: button.primary ? (mouse.containsMouse ? "#d9d9d9" : Theme.white)
                                  : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1))
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            color: button.primary ? "#0f0f0f" : Theme.text
            font.family: Theme.font
            font.weight: Font.Medium
            font.pixelSize: 14
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // ------------------------------------------------------- end screen
    Item {
        id: wall
        visible: root.endScreen
        anchors.fill: parent
        anchors.margins: root.player.xsmall ? 12 : 24

        readonly property int columns: width > 900 ? 4 : width > 560 ? 3 : 2
        readonly property real tileWidth: (width - (columns - 1) * 12) / columns
        readonly property real tileHeight: tileWidth * 9 / 16 + 48
        readonly property int rows: Math.max(1, Math.min(2, Math.floor((height - 40) / (tileHeight + 12))))

        Text {
            id: wallTitle
            text: qsTr("More videos")
            color: Theme.text
            font.family: Theme.font
            font.weight: Font.Medium
            font.pixelSize: 18
        }

        Grid {
            anchors.top: wallTitle.bottom
            anchors.topMargin: 12
            columns: wall.columns
            spacing: 12

            Repeater {
                model: root.player.endScreenItems.slice(0, wall.columns * wall.rows)
                delegate: Item {
                    id: tile
                    required property var modelData
                    width: wall.tileWidth
                    height: wall.tileHeight

                    RoundedImage {
                        id: poster
                        width: parent.width
                        height: Math.round(width * 9 / 16)
                        radius: 8
                        source: tile.modelData.poster
                        scale: tileMouse.containsMouse ? 1.02 : 1
                        Behavior on scale { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {
                        width: parent.width
                        height: poster.height
                        radius: 8
                        visible: poster.status !== Image.Ready
                        color: Theme.surface
                    }
                    Rectangle {
                        visible: tile.modelData.progress > 0
                        y: poster.height - 4
                        x: 0
                        width: poster.width * Math.min(1, tile.modelData.progress)
                        height: 4
                        color: Theme.brandRed
                    }
                    Rectangle {
                        visible: tile.modelData.duration > 0
                        anchors.right: poster.right
                        anchors.bottom: poster.bottom
                        anchors.margins: 6
                        width: durationText.implicitWidth + 8
                        height: durationText.implicitHeight + 2
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.8)
                        Text {
                            id: durationText
                            anchors.centerIn: parent
                            text: Theme.formatTime(tile.modelData.duration)
                            color: Theme.text
                            font.family: Theme.font
                            font.weight: Font.Medium
                            font.pixelSize: 12
                        }
                    }
                    Text {
                        anchors.top: poster.bottom
                        anchors.topMargin: 8
                        width: parent.width
                        text: tile.modelData.title
                        color: Theme.text
                        font.family: Theme.font
                        font.weight: Font.Medium
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player.playIndexRequested(tile.modelData.index)
                    }
                }
            }
        }
    }
}
