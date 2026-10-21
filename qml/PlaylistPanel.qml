import QtQuick
import LocalTube

// The list next to the player in default view: every video in the folder,
// like YouTube's playlist panel.
Rectangle {
    id: panel

    required property var playlist
    signal playRequested(int index)

    color: Theme.page

    Rectangle {
        id: box
        anchors.fill: parent
        anchors.margins: 12
        anchors.leftMargin: 0
        radius: 12
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        clip: true

        Rectangle {
            id: header
            width: parent.width
            height: 72
            color: Theme.surface
            radius: 12
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 12
                color: Theme.surface
            }

            Column {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                spacing: 4
                Text {
                    width: parent.width
                    text: panel.playlist.title || qsTr("Up next")
                    color: Theme.textPrimary
                    font.family: Theme.font
                    font.weight: Font.Bold
                    font.pixelSize: 18
                    elide: Text.ElideRight
                }
                Text {
                    text: panel.playlist.count === 1 ? qsTr("1 video")
                          : qsTr("%1 videos · %2 / %3").arg(panel.playlist.count).arg(panel.playlist.currentIndex + 1).arg(panel.playlist.count)
                    color: Theme.textTertiary
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }

        ListView {
            id: list
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            clip: true
            model: panel.playlist
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: panel.playlist.currentIndex
            highlightFollowsCurrentItem: false
            Component.onCompleted: positionViewAtIndex(Math.max(0, currentIndex), ListView.Center)
            onCurrentIndexChanged: positionViewAtIndex(Math.max(0, currentIndex), ListView.Contain)

            delegate: Item {
                id: entry
                required property int index
                required property string path
                required property string title
                required property real duration
                required property string poster
                required property real progress
                required property bool current
                width: list.width
                height: 72

                Rectangle {
                    anchors.fill: parent
                    color: entry.current ? Qt.rgba(1, 1, 1, 0.12) : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                }

                Text {
                    id: marker
                    width: 28
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: entry.current ? "▶" : entry.index + 1
                    color: Theme.textTertiary
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                Item {
                    id: thumb
                    x: 28
                    anchors.verticalCenter: parent.verticalCenter
                    width: 100
                    height: 56

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Theme.surfaceHover
                    }
                    RoundedImage {
                        anchors.fill: parent
                        radius: 8
                        source: entry.poster
                    }
                    Rectangle {
                        visible: entry.progress > 0
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 4
                        color: Qt.rgba(1, 1, 1, 0.35)
                        Rectangle {
                            width: parent.width * Math.min(1, entry.progress)
                            height: parent.height
                            color: Theme.brandRed
                        }
                    }
                    Rectangle {
                        visible: entry.duration > 0
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        anchors.bottomMargin: entry.progress > 0 ? 8 : 4
                        width: durationLabel.implicitWidth + 6
                        height: durationLabel.implicitHeight + 2
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.8)
                        Text {
                            id: durationLabel
                            anchors.centerIn: parent
                            text: Theme.formatTime(entry.duration)
                            color: Theme.text
                            font.family: Theme.font
                            font.weight: Font.Medium
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    anchors.left: thumb.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.title
                    color: Theme.textPrimary
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.playRequested(entry.index)
                }
            }

            // Thin YouTube-like scrollbar.
            Rectangle {
                visible: list.contentHeight > list.height
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, list.moving ? 0.45 : 0.25)
                y: list.visibleArea.yPosition * list.height
                height: Math.max(24, list.visibleArea.heightRatio * list.height)
            }
        }
    }
}
