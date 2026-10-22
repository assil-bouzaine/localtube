import QtQuick
import LocalTube

// YouTube's seek bar: chapter segments, buffered/hover/played layers, the red
// scrubber and the storyboard preview above the cursor.
Item {
    id: bar

    required property Item player
    readonly property var mpv: player.mpv
    readonly property real duration: mpv.duration
    readonly property bool active: (hoverArea.containsMouse || dragging) && enabled
    property bool dragging: false
    property real dragTime: 0
    property bool resumeAfterDrag: false

    height: 6
    enabled: player.loaded && duration > 0
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Slider
    Accessible.name: qsTr("Playback position")
    Accessible.description: Theme.formatTime(playTime) + " / " + Theme.formatTime(duration)
    Accessible.onIncreaseAction: mpv.seekBy(5, true)
    Accessible.onDecreaseAction: mpv.seekBy(-5, true)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) mpv.seekBy(-5, true)
        else if (event.key === Qt.Key_Right) mpv.seekBy(5, true)
        else if (event.key === Qt.Key_Home) mpv.seekTo(0, true)
        else if (event.key === Qt.Key_End) mpv.seekTo(duration, true)
        else return
        event.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        border.width: bar.activeFocus ? 2 : 0
        border.color: Theme.white
    }

    function timeAt(x) {
        return duration > 0 ? Math.max(0, Math.min(1, x / width)) * duration : 0
    }

    readonly property real hoverX: Math.max(0, Math.min(width, hoverArea.mouseX))
    readonly property real playTime: dragging ? dragTime : mpv.position
    readonly property real playX: duration > 0 ? Math.max(0, Math.min(1, playTime / duration)) * width : 0
    readonly property real loadX: duration > 0 ? Math.max(0, Math.min(1, mpv.cacheTime / duration)) * width : 0
    readonly property real previewX: dragging ? playX : hoverX
    readonly property real previewTime: dragging ? dragTime : timeAt(hoverX)

    readonly property var segments: {
        const chapters = mpv.chapters
        const d = duration
        if (!chapters || chapters.length < 2 || d <= 0)
            return [{ start: 0, end: Math.max(d, 1), title: "" }]
        const out = []
        for (let i = 0; i < chapters.length; i++) {
            const s = Math.max(0, chapters[i].time)
            const e = i + 1 < chapters.length ? Math.min(d, chapters[i + 1].time) : d
            if (e > s)
                out.push({ start: s, end: e, title: chapters[i].title || "" })
        }
        return out.length ? out : [{ start: 0, end: d, title: "" }]
    }

    function chapterTitleAt(t) {
        if (segments.length < 2)
            return ""
        for (let i = segments.length - 1; i >= 0; --i) {
            if (t >= segments[i].start)
                return segments[i].title
        }
        return ""
    }

    Repeater {
        model: bar.segments
        delegate: Item {
            id: segment
            required property var modelData
            required property int index
            readonly property int count: bar.segments.length
            readonly property real gap: count > 1 ? 2 : 0
            readonly property real startX: bar.duration > 0 ? modelData.start / bar.duration * bar.width : 0
            readonly property real endX: bar.duration > 0 ? modelData.end / bar.duration * bar.width : bar.width
            readonly property bool hot: bar.active && count > 1 && bar.previewX >= startX && bar.previewX <= endX

            x: startX + (index > 0 ? gap / 2 : 0)
            width: Math.max(1, endX - startX - (index > 0 ? gap / 2 : 0) - (index < count - 1 ? gap / 2 : 0))
            height: bar.height
            clip: true

            transform: Scale {
                origin.y: segment.height / 2
                yScale: segment.hot ? 1.667 : bar.active ? 1 : 0.667
                Behavior on yScale {
                    NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.progressTrack
            }
            Rectangle {
                x: -segment.x
                width: bar.loadX
                height: parent.height
                color: Theme.progressLoaded
            }
            Rectangle {
                x: -segment.x
                width: bar.hoverX
                height: parent.height
                color: Theme.progressHover
                opacity: bar.active && !bar.dragging ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curveIn }
                }
            }
            Rectangle {
                x: -segment.x
                width: bar.playX
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.brandRed }
                    GradientStop { position: 0.8; color: Theme.brandRed }
                    GradientStop { position: 1.0; color: Theme.progressPink }
                }
            }
        }
    }

    Rectangle {
        id: scrubber
        width: 12
        height: 12
        radius: 6
        color: Theme.brandRed
        x: bar.playX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        visible: bar.enabled
        scale: bar.active ? 1.67 : 1
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.curve }
        }
    }

    MouseArea {
        id: hoverArea
        width: bar.width
        y: -10
        height: bar.height + 16
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            bar.dragging = true
            bar.resumeAfterDrag = !bar.mpv.paused && !bar.player.ended
            if (bar.resumeAfterDrag)
                bar.mpv.paused = true
            bar.dragTime = bar.timeAt(mouse.x)
            bar.mpv.scrub(bar.dragTime)
            bar.player.upNext.cancel()
        }
        onPositionChanged: mouse => {
            if (pressed) {
                bar.dragTime = bar.timeAt(mouse.x)
                bar.mpv.scrub(bar.dragTime)
            }
            bar.player.poke()
        }
        onReleased: {
            bar.mpv.seekTo(bar.dragTime, true)
            bar.dragging = false
            if (bar.resumeAfterDrag)
                bar.mpv.paused = false
        }
        onCanceled: {
            bar.dragging = false
            if (bar.resumeAfterDrag)
                bar.mpv.paused = false
        }
    }

    // Storyboard preview: thumbnail plus a frosted pill with time and chapter.
    Item {
        id: preview
        visible: bar.active
        readonly property real baseWidth: bar.player.xsmall ? 128 : bar.player.bigMode ? 256 : 176
        readonly property real aspect: bar.player.videoW > 0 && bar.player.videoH > 0
                                       ? Math.max(0.4, Math.min(2.6, bar.player.videoW / bar.player.videoH)) : 16 / 9
        readonly property real thumbWidth: aspect >= 1 ? baseWidth : Math.round(baseWidth * 9 / 16 * aspect)
        readonly property real thumbHeight: aspect >= 1 ? Math.round(baseWidth / aspect) : Math.round(baseWidth * 9 / 16)
        readonly property string thumbSource: {
            bar.player.thumbnailer.revision
            return bar.active ? bar.player.thumbnailer.thumbnail(bar.previewTime) : ""
        }
        readonly property bool hasThumb: thumbSource !== ""
        readonly property string chapter: bar.chapterTitleAt(bar.previewTime)

        width: Math.max(hasThumb ? thumbWidth : 0, pill.width)
        height: (hasThumb ? thumbHeight + 8 : 0) + pill.height
        x: Math.max(-bar.player.sidePadding + 8,
                    Math.min(bar.width + bar.player.sidePadding - 8 - width, bar.previewX - width / 2))
        y: -height - 14

        RoundedImage {
            visible: preview.hasThumb
            anchors.horizontalCenter: parent.horizontalCenter
            width: preview.thumbWidth
            height: preview.thumbHeight
            radius: 8
            source: preview.thumbSource
        }

        Item {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            readonly property real maxWidth: Math.max(160, Math.min(bar.width, 360))
            width: Math.min(maxWidth, pillRow.implicitWidth + 32)
            height: pillRow.implicitHeight + 16

            Frosted {
                anchors.fill: parent
                radius: 18
                tint: Theme.tintLight
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 8
                width: Math.min(implicitWidth, pill.width - 32)

                Text {
                    id: timeText
                    text: Theme.formatTime(bar.previewTime)
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: bar.player.bigMode ? 17 : 13
                }
                Text {
                    visible: text !== ""
                    width: Math.min(implicitWidth, pill.maxWidth - 32 - timeText.implicitWidth - 8)
                    text: preview.chapter
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: timeText.font.pixelSize
                    elide: Text.ElideRight
                }
            }
        }
    }
}
