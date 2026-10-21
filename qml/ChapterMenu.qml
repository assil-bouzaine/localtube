import QtQuick
import LocalTube

// Chapter list that opens from the chapter pill, with previews.
Item {
    id: menu

    required property Item player
    readonly property var mpv: player.mpv
    property bool open: false
    property real anchorX: 0

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    width: Math.min(360, player.width - 24)
    height: Math.min(list.contentHeight + 16, player.height - player.barHeight - 30)
    x: Math.max(12, Math.min(player.width - width - 12, anchorX))
    y: player.height - player.barHeight - 6 - height

    function toggleBelow(item) {
        if (open) {
            close()
            return
        }
        anchorX = item.mapToItem(player, 0, 0).x
        open = true
        list.positionViewAtIndex(Math.max(0, mpv.chapter), ListView.Contain)
    }
    function close() { open = false }

    Frosted {
        anchors.fill: parent
        radius: 12
        tint: Theme.tintMedium
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: menu.mpv.chapters

        delegate: Item {
            id: entry
            required property var modelData
            required property int index
            readonly property bool current: index === menu.mpv.chapter
            width: list.width
            height: 64

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: entry.current ? Qt.rgba(1, 1, 1, 0.15) : mouse.containsMouse ? Theme.hover : "transparent"
            }

            RoundedImage {
                id: thumb
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 88
                height: 50
                radius: 6
                source: {
                    menu.player.thumbnailer.revision
                    return menu.open ? menu.player.thumbnailer.thumbnail(entry.modelData.time + 1) : ""
                }
            }

            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    width: parent.width
                    text: entry.modelData.title || qsTr("Chapter %1").arg(entry.index + 1)
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    width: timeLabel.implicitWidth + 8
                    height: timeLabel.implicitHeight + 2
                    radius: 4
                    color: entry.current ? Theme.brandRed : Qt.rgba(1, 1, 1, 0.12)
                    Text {
                        id: timeLabel
                        anchors.centerIn: parent
                        text: Theme.formatTime(entry.modelData.time)
                        color: Theme.text
                        font.family: Theme.font
                        font.weight: Font.Medium
                        font.pixelSize: 12
                    }
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    menu.mpv.seekTo(entry.modelData.time, true)
                    menu.close()
                }
            }
        }
    }
}
