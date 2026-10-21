import QtQuick
import LocalTube

// The settings popup above the gear button, with sliding sub-pages.
Item {
    id: menu

    required property Item player
    readonly property var mpv: player.mpv
    property bool open: false
    property string page: "main"
    property int direction: 1
    readonly property real maxHeight: player.height - player.barHeight - 24
    readonly property bool big: player.bigMode

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    // Positioners report the rows' set widths, so measure their natural widths.
    function naturalWidth(page) {
        if (!page)
            return 250
        let w = 0
        for (let i = 0; i < page.children.length; i++) {
            const child = page.children[i]
            if (child.visible)
                w = Math.max(w, child.implicitWidth)
        }
        return w + 16
    }
    width: Math.min(player.width - 24, Math.max(250, naturalWidth(loader.item)))
    height: Math.min(maxHeight, loader.item ? loader.item.implicitHeight : 100)
    Behavior on width { enabled: menu.open; NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
    Behavior on height { enabled: menu.open; NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }

    function toggle() {
        if (open) {
            close()
        } else {
            page = "main"
            open = true
        }
    }
    function close() { open = false }
    function go(name) {
        direction = 1
        page = name
    }
    function back() {
        direction = -1
        page = "main"
    }

    readonly property string speedLabel: Math.abs(mpv.speed - 1) < 0.001 ? qsTr("Normal") : String(Math.round(mpv.speed * 100) / 100)
    readonly property string sleepLabel: player.sleepMinutes === -1 ? qsTr("End of video")
                                         : player.sleepMinutes > 0 ? qsTr("%1 min").arg(player.sleepMinutes) : qsTr("Off")
    readonly property var levelNames: [qsTr("High"), qsTr("Balanced"), qsTr("Performance")]
    readonly property string qualityLabel: player.qualityMode === 0
                                           ? qsTr("Auto") + (player.qualityLabel ? " (" + player.qualityLabel + ")" : "")
                                           : levelNames[player.qualityMode - 1]

    Frosted {
        anchors.fill: parent
        radius: 12
        tint: Theme.tintMedium
    }

    // Keep clicks and wheel events inside the menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentHeight: loader.item ? loader.item.implicitHeight : 0
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Loader {
            id: loader
            width: menu.width
            sourceComponent: menu.page === "speed" ? speedPage
                           : menu.page === "subtitles" ? subtitlesPage
                           : menu.page === "audio" ? audioPage
                           : menu.page === "quality" ? qualityPage
                           : menu.page === "sleep" ? sleepPage
                           : mainPage
            onLoaded: slideIn.restart()
        }
    }

    ParallelAnimation {
        id: slideIn
        NumberAnimation { target: loader; property: "x"; from: 24 * menu.direction; to: 0; duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        NumberAnimation { target: loader; property: "opacity"; from: 0; to: 1; duration: 160 }
    }

    component RoundIconButton: Item {
        id: roundButton
        property var icon
        signal clicked()
        width: 32
        height: 32
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: roundMouse.pressed ? Theme.pressed : roundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Theme.hover
        }
        Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            icon: roundButton.icon
        }
        MouseArea {
            id: roundMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: roundButton.clicked()
        }
    }

    component Header: Item {
        id: header
        property string title
        property string actionText
        signal action()
        width: parent ? parent.width - 16 : 0
        height: menu.big ? 56 : 48

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.divider
        }
        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.back()
        }
        Icon {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            icon: Icons.chevronLeft
        }
        Text {
            x: 48
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            color: Theme.textMenu
            font.family: Theme.font
            font.weight: Font.Medium
            font.pixelSize: menu.big ? 17 : 14
        }
        Text {
            visible: header.actionText !== ""
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: header.actionText
            color: Theme.textMenu
            font.family: Theme.font
            font.pixelSize: menu.big ? 15 : 13
            font.underline: actionMouse.containsMouse
            MouseArea {
                id: actionMouse
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                onClicked: header.action()
            }
        }
    }

    Component {
        id: mainPage
        Column {
            padding: 8
            spacing: 0

            MenuRow {
                width: parent.width - 16
                big: menu.big
                icon: Icons.stableVolume
                label: qsTr("Stable Volume")
                hasToggle: true
                toggled: menu.player.stableVolume
                onClicked: menu.player.stableVolumeRequested(!menu.player.stableVolume)
            }
            MenuRow {
                width: parent.width - 16
                big: menu.big
                icon: Icons.subtitles
                label: qsTr("Subtitles/CC") + (menu.player.subtitleTracks.length ? " (" + menu.player.subtitleTracks.length + ")" : "")
                value: menu.player.captionsOn ? menu.player.trackLabel(menu.player.currentSubtitle) : qsTr("Off")
                submenu: true
                onClicked: menu.go("subtitles")
            }
            MenuRow {
                width: parent.width - 16
                big: menu.big
                icon: Icons.timer
                label: qsTr("Sleep timer")
                value: menu.sleepLabel
                submenu: true
                onClicked: menu.go("sleep")
            }
            MenuRow {
                objectName: "speedRow"
                width: parent.width - 16
                big: menu.big
                icon: Icons.speed
                label: qsTr("Playback speed")
                value: menu.speedLabel
                submenu: true
                onClicked: menu.go("speed")
            }
            MenuRow {
                width: parent.width - 16
                big: menu.big
                icon: Icons.quality
                label: qsTr("Quality")
                value: menu.qualityLabel
                submenu: true
                onClicked: menu.go("quality")
            }
            MenuRow {
                width: parent.width - 16
                big: menu.big
                visible: menu.player.audioTracks.length > 1
                icon: Icons.audioTrack
                label: qsTr("Audio track")
                value: menu.player.trackLabel(menu.player.currentAudio)
                submenu: true
                onClicked: menu.go("audio")
            }
        }
    }

    Component {
        id: speedPage
        Column {
            padding: 8
            Header { title: qsTr("Playback speed") }

            // Custom speed: value, slider and -/+ buttons.
            Item {
                width: parent.width - 16
                height: 92

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    text: (Math.round(menu.mpv.speed * 100) / 100).toFixed(2) + "x"
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: 20
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    spacing: 12

                    RoundIconButton {
                        icon: ({ d: "M5 11h14v2H5z", box: [0, 0, 24, 24] })
                        onClicked: menu.player.setSpeed(menu.mpv.speed - 0.05)
                    }
                    Item {
                        id: speedSlider
                        width: 150
                        height: 32
                        readonly property real minSpeed: 0.25
                        readonly property real maxSpeed: 4
                        readonly property real fraction: (Math.min(maxSpeed, Math.max(minSpeed, menu.mpv.speed)) - minSpeed) / (maxSpeed - minSpeed)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.2)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: speedSlider.fraction * (parent.width - 16) + 8
                            height: 4
                            radius: 2
                            color: Theme.white
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: speedSlider.fraction * (parent.width - 16)
                            width: 16
                            height: 16
                            radius: 8
                            color: Theme.white
                        }
                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            function apply(x) {
                                const f = Math.max(0, Math.min(1, (x - 8) / (width - 16)))
                                const v = speedSlider.minSpeed + f * (speedSlider.maxSpeed - speedSlider.minSpeed)
                                menu.mpv.speed = Math.round(v * 20) / 20
                            }
                            onPressed: mouse => apply(mouse.x)
                            onPositionChanged: mouse => { if (pressed) apply(mouse.x) }
                        }
                    }
                    RoundIconButton {
                        icon: Icons.add
                        onClicked: menu.player.setSpeed(menu.mpv.speed + 0.05)
                    }
                }
            }

            Rectangle {
                width: parent.width - 16
                height: 1
                color: Theme.divider
            }

            Repeater {
                model: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width - 16
                    big: menu.big
                    checkable: true
                    checked: Math.abs(menu.mpv.speed - modelData) < 0.001
                    label: modelData === 1 ? qsTr("Normal") : String(modelData)
                    onClicked: {
                        menu.player.setSpeed(modelData)
                        menu.close()
                    }
                }
            }
        }
    }

    Component {
        id: subtitlesPage
        Column {
            padding: 8
            Header { title: qsTr("Subtitles/CC") }

            MenuRow {
                width: parent.width - 16
                big: menu.big
                checkable: true
                checked: !menu.player.captionsOn
                label: qsTr("Off")
                onClicked: {
                    menu.mpv.selectTrack("sub", null)
                    menu.player.captionsPreferenceChanged(false)
                    menu.close()
                }
            }
            Repeater {
                model: menu.player.subtitleTracks
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width - 16
                    big: menu.big
                    checkable: true
                    checked: !!modelData.selected
                    label: menu.player.trackLabel(modelData) + (modelData.external ? qsTr(" (file)") : "")
                    onClicked: {
                        menu.mpv.selectTrack("sub", modelData.id)
                        menu.player.captionsPreferenceChanged(true)
                        menu.close()
                    }
                }
            }
            MenuRow {
                width: parent.width - 16
                big: menu.big
                icon: Icons.add
                label: qsTr("Add subtitle file…")
                onClicked: {
                    menu.close()
                    menu.player.addSubtitleRequested()
                }
            }
        }
    }

    Component {
        id: audioPage
        Column {
            padding: 8
            Header { title: qsTr("Audio track") }

            Repeater {
                model: menu.player.audioTracks
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width - 16
                    big: menu.big
                    checkable: true
                    checked: !!modelData.selected
                    label: menu.player.trackLabel(modelData)
                    value: {
                        const codec = (modelData.codec || "").toUpperCase()
                        const ch = modelData["demux-channel-count"]
                        return codec + (ch ? " " + (ch === 6 ? "5.1" : ch === 8 ? "7.1" : ch === 2 ? "stereo" : ch === 1 ? "mono" : ch + "ch") : "")
                    }
                    onClicked: {
                        menu.mpv.selectTrack("audio", modelData.id)
                        menu.close()
                    }
                }
            }
        }
    }

    Component {
        id: sleepPage
        Column {
            padding: 8
            Header { title: qsTr("Sleep timer") }

            Repeater {
                model: [0, 10, 15, 20, 30, 45, 60, -1]
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width - 16
                    big: menu.big
                    checkable: true
                    checked: menu.player.sleepMinutes === modelData
                    label: modelData === 0 ? qsTr("Off") : modelData === -1 ? qsTr("End of video") : qsTr("%1 minutes").arg(modelData)
                    onClicked: {
                        menu.player.setSleepTimer(modelData)
                        menu.close()
                    }
                }
            }
        }
    }

    Component {
        id: qualityPage
        Column {
            padding: 8
            Header { title: qsTr("Quality") }

            Repeater {
                model: [
                    { mode: 0, label: qsTr("Auto"), detail: menu.player.qualityMode === 0 ? menu.levelNames[menu.player.renderLevel] : "" },
                    { mode: 1, label: qsTr("High"), detail: qsTr("Sharpest scaling") },
                    { mode: 2, label: qsTr("Balanced"), detail: "" },
                    { mode: 3, label: qsTr("Performance"), detail: qsTr("Smoothest on weak GPUs") },
                ]
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width - 16
                    big: menu.big
                    checkable: true
                    checked: menu.player.qualityMode === modelData.mode
                    label: modelData.label
                    value: modelData.detail
                    onClicked: {
                        menu.player.qualityModeRequested(modelData.mode)
                        menu.close()
                    }
                }
            }

            Text {
                width: parent.width - 16
                leftPadding: 16
                rightPadding: 16
                topPadding: 4
                bottomPadding: 10
                wrapMode: Text.Wrap
                color: Theme.textTertiary
                font.family: Theme.font
                font.pixelSize: 12
                text: {
                    const p = menu.mpv.videoParams
                    if (!p.w)
                        return ""
                    const codec = String(menu.mpv.getProperty("video-format") || "").toUpperCase()
                    const hw = menu.mpv.hwdec ? qsTr("hardware decoding (%1)").arg(menu.mpv.hwdec) : qsTr("software decoding")
                    return qsTr("Original %1×%2 %3 · %4").arg(p.dw).arg(p.dh).arg(codec).arg(hw)
                }
            }
        }
    }
}
