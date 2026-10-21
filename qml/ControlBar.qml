import QtQuick
import LocalTube

// The bottom control bar in YouTube's current layout: separate frosted pills
// for play, previous/next, volume, time and chapter on the left, and one pill
// with the remaining buttons on the right.
Item {
    id: bar

    required property Item player
    readonly property var mpv: player.mpv
    readonly property bool hovered: hover.hovered
    readonly property bool compact: width < 760
    readonly property bool narrow: width < 640

    signal settingsClicked()
    signal chapterClicked(Item item)

    HoverHandler { id: hover }

    // Swallow clicks on empty space so they don't toggle playback.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    Row {
        id: left
        x: bar.player.sidePadding
        height: parent.height

        PlayButton {
            player: bar.player
            y: (bar.height - height) / 2
        }

        Item { width: 8; height: 1; visible: navPill.visible }

        Item {
            id: navPill
            visible: (bar.player.hasNext || bar.player.hasPrevious) && !bar.narrow && !bar.player.xsmall
            y: bar.player.pillTop
            width: navRow.width
            height: bar.player.pillHeight

            Frosted {
                anchors.fill: parent
                radius: 28
            }

            Row {
                id: navRow
                height: parent.height

                PillButton {
                    visible: bar.player.hasPrevious
                    width: bar.player.buttonWidth + 4
                    height: parent.height
                    insetLeft: 4
                    iconSize: bar.player.iconSize
                    icon: Icons.previous
                    tooltip: qsTr("Previous")
                    shortcut: "SHIFT+p"
                    onClicked: bar.player.previousRequested()
                }
                PillButton {
                    width: bar.player.buttonWidth + 4
                    height: parent.height
                    insetLeft: bar.player.hasPrevious ? 0 : 4
                    insetRight: 4
                    enabled: bar.player.hasNext
                    iconSize: bar.player.iconSize
                    icon: Icons.next
                    tooltip: qsTr("Next")
                    shortcut: "SHIFT+n"
                    onClicked: bar.player.nextRequested()
                }
            }
        }

        Item { width: 12; height: 1 }

        VolumeControl {
            objectName: "volumeControl"
            player: bar.player
            y: bar.player.pillTop
        }

        Item { width: 12; height: 1 }

        Item {
            id: timePill
            y: bar.player.pillTop
            width: timeRow.implicitWidth + 32
            height: bar.player.pillHeight

            Frosted {
                anchors.fill: parent
                radius: 28
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: height / 2
                color: timeMouse.pressed ? Theme.pressed : timeMouse.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
            }

            Row {
                id: timeRow
                anchors.centerIn: parent

                Text {
                    text: bar.player.showRemaining
                          ? "-" + Theme.formatTime(Math.max(0, bar.mpv.duration - bar.mpv.position))
                          : Theme.formatTime(bar.mpv.position)
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: bar.player.fontSize
                }
                Text {
                    text: " / " + Theme.formatTime(bar.mpv.duration)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: bar.player.fontSize
                }
            }

            MouseArea {
                id: timeMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: bar.player.showRemaining = !bar.player.showRemaining
            }
        }

        Item { width: 12; height: 1; visible: chapterPill.visible }

        Item {
            id: chapterPill
            objectName: "chapterPill"
            // Measured from the time pill so the chapter pill's own position
            // (which depends on its visibility) is not part of the binding.
            readonly property real available: bar.width - bar.player.sidePadding - rightPill.width - 12
                                              - (left.x + timePill.x + timePill.width + 12)
            visible: bar.player.currentChapter !== null && bar.mpv.chapters.length > 1 && !bar.player.xsmall && available >= 96
            y: bar.player.pillTop
            width: Math.min(chapterText.implicitWidth + chevron.width + 32, available)
            height: bar.player.pillHeight

            Frosted {
                anchors.fill: parent
                radius: 28
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: height / 2
                color: chapterMouse.pressed ? Theme.pressed : chapterMouse.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve } }
            }

            Row {
                id: chapterRow
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                width: Math.max(0, Math.min(implicitWidth, chapterPill.width - 32))

                Text {
                    id: chapterText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, Math.min(implicitWidth, chapterPill.width - 32 - chevron.width))
                    text: bar.player.currentChapter ? (bar.player.currentChapter.title || qsTr("Chapter %1").arg(bar.mpv.chapter + 1)) : ""
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: bar.player.fontSize
                    elide: Text.ElideRight
                }
                Icon {
                    id: chevron
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    icon: Icons.chevronRight
                }
            }

            MouseArea {
                id: chapterMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: bar.chapterClicked(chapterPill)
            }
        }
    }

    Item {
        id: rightPill
        anchors.right: parent.right
        anchors.rightMargin: bar.player.sidePadding
        y: bar.player.pillTop
        width: rightRow.width + 8
        height: bar.player.pillHeight

        Frosted {
            anchors.fill: parent
            radius: 28
        }

        Row {
            id: rightRow
            x: 4
            height: parent.height

            AutoplayToggle {
                visible: !bar.narrow && !bar.player.xsmall
                width: bar.player.buttonWidth
                height: parent.height
                checked: bar.player.autoplay
                onClicked: bar.player.autoplayToggled()
            }

            PillButton {
                width: bar.player.buttonWidth
                height: parent.height
                iconSize: bar.player.iconSize
                icon: bar.player.captionsOn ? Icons.captionsOn : Icons.captions
                opacity: bar.player.subtitleTracks.length > 0 ? 1 : 0.5
                tooltip: bar.player.subtitleTracks.length > 0 ? qsTr("Subtitles/closed captions") : qsTr("Add subtitles")
                shortcut: bar.player.subtitleTracks.length > 0 ? "c" : ""
                onClicked: {
                    if (bar.player.subtitleTracks.length > 0)
                        bar.player.toggleCaptions()
                    else
                        bar.player.addSubtitleRequested()
                }
            }

            PillButton {
                id: settingsButton
                objectName: "settingsButton"
                width: bar.player.buttonWidth
                height: parent.height
                iconSize: bar.player.iconSize
                icon: Icons.settings
                iconRotation: bar.player.settingsMenu.open ? 30 : 0
                tooltip: bar.player.settingsMenu.open ? "" : qsTr("Settings")
                onClicked: bar.settingsClicked()

                // Quality badge (HD / 4K / HDR) on the gear, YouTube style.
                Item {
                    visible: bar.player.qualityBadge !== ""
                    readonly property real s: bar.player.bigMode ? 1.3 : 1
                    width: 13 * s
                    height: 9 * s
                    x: parent.width / 2 + 5 * s
                    y: parent.height / 2 - 14 * s

                    Icon {
                        anchors.fill: parent
                        visible: bar.player.qualityBadge === "HD" || bar.player.qualityBadge === "4K"
                        icon: bar.player.qualityBadge === "HD" ? Icons.hdBadgeShadow : Icons.fourKBadgeShadow
                        color: Qt.rgba(0, 0, 0, 0.65)
                    }
                    Icon {
                        anchors.fill: parent
                        visible: bar.player.qualityBadge === "HD" || bar.player.qualityBadge === "4K"
                        icon: bar.player.qualityBadge === "HD" ? Icons.hdBadge : Icons.fourKBadge
                    }
                    Text {
                        visible: !(bar.player.qualityBadge === "HD" || bar.player.qualityBadge === "4K")
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.player.qualityBadge
                        color: Theme.white
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.6)
                        font.family: Theme.font
                        font.weight: Font.Bold
                        font.pixelSize: 8 * parent.s
                    }
                }
            }

            Item {
                visible: !bar.compact && !bar.player.xsmall
                width: 13
                height: parent.height
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: bar.player.bigMode ? 28 : 24
                    color: Qt.rgba(1, 1, 1, 0.2)
                }
            }

            PillButton {
                visible: !bar.compact && !bar.player.xsmall && !bar.player.fullscreen
                width: bar.player.buttonWidth
                height: parent.height
                iconSize: bar.player.iconSize
                icon: Icons.miniplayer
                tooltip: bar.player.miniplayer ? qsTr("Expand") : qsTr("Miniplayer")
                shortcut: "i"
                onClicked: bar.player.miniplayerToggled()
            }

            PillButton {
                visible: !bar.compact && !bar.player.xsmall && !bar.player.fullscreen && !bar.player.miniplayer
                width: bar.player.buttonWidth
                height: parent.height
                iconSize: bar.player.iconSize
                icon: bar.player.theater ? Icons.defaultView : Icons.theater
                tooltip: bar.player.theater ? qsTr("Default view") : qsTr("Theater mode")
                shortcut: "t"
                onClicked: bar.player.theaterToggled()
            }

            PillButton {
                width: bar.player.buttonWidth
                height: parent.height
                iconSize: bar.player.iconSize
                icon: bar.player.fullscreen ? Icons.fullscreenExit : Icons.fullscreen
                tooltip: bar.player.fullscreen ? qsTr("Exit full screen") : qsTr("Full screen")
                shortcut: "f"
                onClicked: bar.player.fullscreenToggled()
            }
        }
    }
}
