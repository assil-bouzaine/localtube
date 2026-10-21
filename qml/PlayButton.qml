import QtQuick
import LocalTube

// The round, frosted play/pause/replay button at the left of the control bar.
Item {
    id: root

    required property Item player
    readonly property var mpv: player.mpv
    readonly property string state_: player.ended ? "replay" : mpv.paused ? "play" : "pause"

    width: player.playSize
    height: player.playSize

    Frosted {
        anchors.fill: parent
        radius: width / 2
    }

    PillButton {
        id: button
        anchors.fill: parent
        highlightRadius: width / 2
        insetLeft: 4
        insetRight: 4
        tooltip: root.state_ === "replay" ? qsTr("Replay") : root.state_ === "play" ? qsTr("Play") : qsTr("Pause")
        shortcut: root.state_ === "replay" ? "" : "k"
        onClicked: root.player.togglePause(false)

        // Cross-fade between the icons, with a little scale like YouTube's morph.
        Repeater {
            model: [
                { name: "play", icon: Icons.play },
                { name: "pause", icon: Icons.pause },
                { name: "replay", icon: Icons.replay },
            ]
            delegate: Icon {
                required property var modelData
                readonly property bool shown: root.state_ === modelData.name
                readonly property real size: root.player.xsmall ? 24 : modelData.name === "replay" ? 28 : 36
                anchors.centerIn: parent
                width: size
                height: size
                icon: modelData.icon
                opacity: shown ? 1 : 0
                scale: shown ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
            }
        }
    }
}
