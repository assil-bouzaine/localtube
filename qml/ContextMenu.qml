import QtQuick
import LocalTube

// Right-click menu (ytp-contextmenu), frosted in the current design.
Item {
    id: menu

    required property Item player
    readonly property var mpv: player.mpv
    property bool open: false

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    width: Math.min(player.width - 16, Math.max(272, column.implicitWidth))
    height: Math.max(1, Math.min(column.implicitHeight, player.height - 16))

    function openAt(px, py) {
        x = Math.max(8, Math.min(player.width - width - 8, px))
        y = Math.max(8, Math.min(player.height - height - 8, py))
        open = true
    }
    function close() { open = false }
    function run(action) {
        close()
        action()
    }

    Frosted {
        anchors.fill: parent
        radius: 12
        tint: Theme.tintMedium
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    component Separator: Rectangle {
        width: parent ? parent.width - 16 : 0
        height: 1
        color: Theme.divider
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            width: menu.width
            padding: 8

            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                icon: Icons.loop
                label: qsTr("Loop")
                hasToggle: true
                toggled: menu.mpv.loop
                onClicked: menu.mpv.loop = !menu.mpv.loop
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.youtubeId !== ""
                icon: Icons.link
                label: qsTr("Copy video URL")
                onClicked: menu.run(() => Platform.copyText("https://youtu.be/" + menu.player.youtubeId))
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.youtubeId !== ""
                icon: Icons.link
                label: qsTr("Copy video URL at current time")
                onClicked: menu.run(() => Platform.copyText("https://youtu.be/" + menu.player.youtubeId + "?t=" + Math.floor(menu.mpv.position)))
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.loaded
                icon: Icons.link
                label: qsTr("Copy file path")
                onClicked: menu.run(() => Platform.copyText(menu.mpv.path))
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.loaded
                icon: Icons.folder
                label: qsTr("Show in folder")
                onClicked: menu.run(() => menu.player.showInFolderRequested())
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.loaded
                icon: Icons.camera
                label: qsTr("Take screenshot")
                value: "s"
                onClicked: menu.run(() => menu.player.takeScreenshot())
            }

            Separator {}

            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.loaded
                icon: Icons.folder
                label: qsTr("Back to library")
                onClicked: menu.run(() => menu.player.showHomeRequested())
            }

            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                icon: Icons.movie
                label: qsTr("Open file…")
                value: "Ctrl+O"
                onClicked: menu.run(() => menu.player.openFilesRequested())
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                icon: Icons.folder
                label: qsTr("Open folder…")
                onClicked: menu.run(() => menu.player.openFolderRequested())
            }

            Separator {}

            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                visible: menu.player.loaded
                icon: Icons.info
                label: qsTr("Stats for nerds")
                onClicked: menu.run(() => menu.player.statsPanel.open = !menu.player.statsPanel.open)
            }
            MenuRow {
                width: parent.width - 16
                rowHeight: 40
                icon: Icons.keyboard
                label: qsTr("Keyboard shortcuts")
                value: "?"
                onClicked: menu.run(() => menu.player.shortcutsDialog.open = true)
            }
        }
    }

}
