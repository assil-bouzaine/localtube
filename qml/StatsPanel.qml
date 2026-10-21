import QtQuick
import LocalTube

// "Stats for nerds", laid out like YouTube's panel.
Item {
    id: panel

    required property Item player
    readonly property var mpv: player.mpv
    property bool open: false
    property var rows: []

    visible: open && player.loaded
    width: Math.min(player.width - 20, content.implicitWidth + 24)
    height: content.implicitHeight + 20

    Timer {
        interval: 500
        repeat: true
        running: panel.visible
        triggeredOnStart: true
        onTriggered: panel.refresh()
    }

    function kbps(v) {
        return v > 0 ? Math.round(v / 1000) + " Kbps" : "n/a"
    }

    function refresh() {
        const m = mpv
        const p = m.videoParams
        const g = name => m.getProperty(name)
        const win = panel.Window.window
        const dpr = win ? win.devicePixelRatio : 1
        const fps = m.fps ? Math.round(m.fps * 100) / 100 : 0
        const res = p.w ? p.w + "x" + p.h + "@" + fps : "n/a"
        const outRes = g("video-out-params")
        const drops = g("frame-drop-count") || 0
        const decDrops = g("decoder-frame-drop-count") || 0
        const frames = g("estimated-frame-number") || 0
        const audio = g("audio-params") || {}
        const channels = audio["hr-channels"] || audio.channels || ""
        const hdr = p.gamma === "pq" ? "PQ (HDR10)" : p.gamma === "hlg" ? "HLG (HDR)" : (p.gamma || "")
        const cache = g("demuxer-cache-duration")
        rows = [
            [qsTr("File"), Platform.fileName(m.path)],
            [qsTr("Viewport / Frames"), Math.round(m.width) + "x" + Math.round(m.height) + "*" + dpr.toFixed(2)
                + " / " + (drops + decDrops) + " dropped of " + frames],
            [qsTr("Current / Optimal Res"), res + " / " + res],
            [qsTr("Volume / Normalized"), Math.round(m.volume) + "% / " + (player.stableVolume ? qsTr("Stable Volume on") : qsTr("off"))],
            [qsTr("Codecs"), (g("video-format") || "?") + " (" + (m.hwdec ? "hw: " + m.hwdec : "software") + ") / "
                + (g("audio-codec-name") || "?") + (audio.samplerate ? " " + audio.samplerate / 1000 + " kHz" : "") + (channels ? " " + channels : "")],
            [qsTr("Color"), (p.primaries || "?") + " / " + hdr + (p.pixelformat ? " / " + (p["hw-pixelformat"] || p.pixelformat) : "")],
            [qsTr("Bitrate"), kbps(g("video-bitrate")) + " / " + kbps(g("audio-bitrate"))],
            [qsTr("Buffer Health"), cache !== undefined && cache !== null ? Number(cache).toFixed(2) + " s" : "n/a"],
            [qsTr("Renderer"), "libmpv " + (g("mpv-version") || "").replace("mpv ", "") + " · " + ["High", "Balanced", "Performance"][player.renderLevel]
                + (outRes && outRes.w ? " · " + outRes.w + "x" + outRes.h : "")],
            [qsTr("Container"), (g("file-format") || "?") + " · " + Platform.formatSize(Platform.fileSize(m.path))],
            [qsTr("Date"), new Date().toString()],
        ]
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Qt.rgba(28 / 255, 28 / 255, 28 / 255, 0.8)
    }

    Column {
        id: content
        x: 12
        y: 10
        spacing: 1

        Repeater {
            model: panel.rows
            delegate: Row {
                required property var modelData
                spacing: 10
                Text {
                    width: 150
                    horizontalAlignment: Text.AlignRight
                    text: modelData[0]
                    color: Theme.text
                    font.family: Theme.font
                    font.weight: Font.Medium
                    font.pixelSize: 12
                }
                Text {
                    width: Math.min(implicitWidth, panel.player.width - 210)
                    text: modelData[1]
                    color: "#dddddd"
                    font.family: Theme.font
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: "[x]"
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 12
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.open = false
        }
    }
}
