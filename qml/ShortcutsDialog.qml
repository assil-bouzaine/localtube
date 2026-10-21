import QtQuick
import LocalTube

// Keyboard shortcuts overlay (Shift + ?), like YouTube's dialog.
Item {
    id: root

    property bool open: false

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    readonly property var sections: [
        { title: qsTr("Playback"), items: [
            ["Space / K", qsTr("Toggle play/pause")],
            ["J / L", qsTr("Rewind / fast forward 10 seconds")],
            ["← / →", qsTr("Seek backward / forward 5 seconds")],
            ["0 – 9", qsTr("Seek to 0% – 90% of the video")],
            ["Home / End", qsTr("Seek to beginning / end")],
            [", / .", qsTr("Previous / next frame (while paused)")],
            ["< / >", qsTr("Decrease / increase playback rate")],
            ["Ctrl + ← / →", qsTr("Previous / next chapter")],
            ["Shift + P / N", qsTr("Previous / next video")],
        ] },
        { title: qsTr("General"), items: [
            ["F", qsTr("Toggle full screen")],
            ["T", qsTr("Toggle theater mode")],
            ["I", qsTr("Toggle miniplayer")],
            ["Esc", qsTr("Close dialog / exit full screen")],
            ["M", qsTr("Toggle mute")],
            ["↑ / ↓", qsTr("Increase / decrease volume 5%")],
            ["S", qsTr("Take a screenshot")],
            ["Ctrl + O", qsTr("Open file")],
            ["Shift + ?", qsTr("Show keyboard shortcuts")],
        ] },
        { title: qsTr("Subtitles and closed captions"), items: [
            ["C", qsTr("Toggle subtitles/closed captions")],
            ["+ / -", qsTr("Increase / decrease font size")],
        ] },
    ]

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.open = false
            onWheel: wheel => wheel.accepted = true
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 760)
        height: Math.min(parent.height - 32, header.height + flick.contentHeight + 24)
        radius: 12
        color: Theme.surface

        MouseArea { anchors.fill: parent }

        Item {
            id: header
            width: parent.width
            height: 64
            Text {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Keyboard shortcuts")
                color: Theme.textPrimary
                font.family: Theme.font
                font.pixelSize: 20
            }
            PillButton {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                insetTop: 0
                insetBottom: 0
                icon: Icons.close
                onClicked: root.open = false
            }
        }

        Flickable {
            id: flick
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            clip: true
            contentHeight: columns.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: columns
                x: 24
                width: parent.width - 48
                spacing: 20

                Repeater {
                    model: root.sections
                    delegate: Column {
                        required property var modelData
                        width: columns.width
                        spacing: 0

                        Text {
                            text: modelData.title
                            color: Theme.textPrimary
                            font.family: Theme.font
                            font.weight: Font.Medium
                            font.pixelSize: 16
                            bottomPadding: 8
                        }
                        Grid {
                            columns: card.width > 560 ? 2 : 1
                            columnSpacing: 32
                            rowSpacing: 0
                            width: parent.width

                            Repeater {
                                model: modelData.items
                                delegate: Item {
                                    required property var modelData
                                    width: (columns.width - (card.width > 560 ? 32 : 0)) / (card.width > 560 ? 2 : 1)
                                    height: 36
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - keyBox.width - 12
                                        text: modelData[1]
                                        color: Theme.textTertiary
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        id: keyBox
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: keyText.implicitWidth + 16
                                        height: 26
                                        radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.1)
                                        Text {
                                            id: keyText
                                            anchors.centerIn: parent
                                            text: modelData[0]
                                            color: Theme.textPrimary
                                            font.family: Theme.font
                                            font.weight: Font.Medium
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
