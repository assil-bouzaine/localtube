import QtQuick
import LocalTube

// Shown when nothing is playing: open buttons and "Continue watching".
Rectangle {
    id: home

    signal openFilesRequested()
    signal openFolderRequested()
    signal openPathRequested(string path)

    color: Theme.page

    property var recent: []
    function refresh() { recent = History.recent(12) }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    component PillAction: Item {
        id: action
        property string text
        property var icon
        property bool primary: false
        signal clicked()
        width: row.implicitWidth + 32
        height: 36
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: action.primary ? (mouse.containsMouse ? "#d9d9d9" : "#f1f1f1")
                                  : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1))
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                icon: action.icon
                color: action.primary ? "#0f0f0f" : Theme.textPrimary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: action.text
                color: action.primary ? "#0f0f0f" : Theme.textPrimary
                font.family: Theme.font
                font.weight: Font.Medium
                font.pixelSize: 14
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
    }

    // Top bar with the logo.
    Item {
        id: topBar
        width: parent.width
        height: 56

        Row {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                sourceSize: Qt.size(60, 60)
                source: "qrc:/qt/qml/LocalTube/data/localtube.svg"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "LocalTube"
                color: Theme.textPrimary
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: 19
                font.letterSpacing: -0.6
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: home.recent.length > 0
            PillAction {
                text: qsTr("Open folder")
                icon: Icons.folder
                onClicked: home.openFolderRequested()
            }
            PillAction {
                text: qsTr("Open file")
                icon: Icons.movie
                primary: true
                onClicked: home.openFilesRequested()
            }
        }
    }

    // Empty state.
    Column {
        visible: home.recent.length === 0
        anchors.centerIn: parent
        spacing: 16

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            sourceSize: Qt.size(192, 192)
            source: "qrc:/qt/qml/LocalTube/data/localtube.svg"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Open a video to start watching")
            color: Theme.textPrimary
            font.family: Theme.font
            font.pixelSize: 22
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Or drop files and folders here")
            color: Theme.textTertiary
            font.family: Theme.font
            font.pixelSize: 14
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            topPadding: 8
            PillAction {
                text: qsTr("Open file")
                icon: Icons.movie
                primary: true
                onClicked: home.openFilesRequested()
            }
            PillAction {
                text: qsTr("Open folder")
                icon: Icons.folder
                onClicked: home.openFolderRequested()
            }
        }
    }

    // Continue watching.
    Flickable {
        visible: home.recent.length > 0
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: 24
            y: 8
            width: parent.width - 48
            spacing: 16

            Text {
                text: qsTr("Continue watching")
                color: Theme.textPrimary
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: 20
            }

            Grid {
                id: grid
                readonly property int cols: Math.max(1, Math.min(4, Math.floor((content.width + 16) / 280)))
                columns: cols
                columnSpacing: 16
                rowSpacing: 24

                Repeater {
                    model: home.recent
                    delegate: Item {
                        id: card
                        required property var modelData
                        width: (content.width - (grid.cols - 1) * 16) / grid.cols
                        height: thumbBox.height + 64

                        Item {
                            id: thumbBox
                            width: parent.width
                            height: Math.round(width * 9 / 16)

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: Theme.surfaceHover
                            }
                            RoundedImage {
                                anchors.fill: parent
                                radius: 12
                                source: {
                                    MediaInfo.revision
                                    return MediaInfo.poster(card.modelData.path)
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.3)
                                Rectangle {
                                    width: parent.width * Math.min(1, card.modelData.progress)
                                    height: parent.height
                                    radius: 2
                                    color: Theme.brandRed
                                }
                            }
                            Rectangle {
                                visible: card.modelData.duration > 0
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                anchors.bottomMargin: 12
                                width: dur.implicitWidth + 8
                                height: dur.implicitHeight + 2
                                radius: 4
                                color: Qt.rgba(0, 0, 0, 0.8)
                                Text {
                                    id: dur
                                    anchors.centerIn: parent
                                    text: Theme.formatTime(card.modelData.duration)
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.weight: Font.Medium
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Column {
                            anchors.top: thumbBox.bottom
                            anchors.topMargin: 12
                            width: parent.width
                            spacing: 4
                            Text {
                                width: parent.width
                                text: MediaInfo.displayTitle(card.modelData.path)
                                color: Theme.textPrimary
                                font.family: Theme.font
                                font.weight: Font.Medium
                                font.pixelSize: 15
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: Platform.fileName(Platform.dirName(card.modelData.path)) + " • " + home.ago(card.modelData.updated)
                                color: Theme.textTertiary
                                font.family: Theme.font
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: home.openPathRequested(card.modelData.path)
                        }
                    }
                }
            }
        }
    }

    function ago(seconds) {
        const d = Math.max(0, Date.now() / 1000 - seconds)
        if (d < 60) return qsTr("just now")
        if (d < 3600) return qsTr("%1 min ago").arg(Math.floor(d / 60))
        if (d < 86400) return qsTr("%1 hours ago").arg(Math.floor(d / 3600))
        if (d < 86400 * 30) return qsTr("%1 days ago").arg(Math.floor(d / 86400))
        return qsTr("%1 months ago").arg(Math.floor(d / (86400 * 30)))
    }
}
