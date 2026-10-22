import QtQuick
import LocalTube

// Rendering policy is kept separate from the player controls and overlays.
Item {
    id: adaptive
    required property Item player
    property int autoLevel: 0
    readonly property int renderLevel: player.qualityMode === 0 ? autoLevel : player.qualityMode - 1
    readonly property string qualityClass: player.lines ? player.lines + "p" + (player.mpv.fps > 35 ? "60" : "30") + (player.isHdr ? "hdr" : "") : ""

    onQualityClassChanged: {
        if (!qualityClass)
            return
        const remembered = player.qualityMemory[qualityClass]
        if (Number.isInteger(remembered) && remembered >= 0 && remembered <= 2)
            autoLevel = remembered
        else
            autoLevel = (player.isHdr || player.videoW * player.videoH * Math.max(player.mpv.fps, 30) > 3840 * 2160 * 31) ? 1 : 0
    }
    onRenderLevelChanged: applyRenderLevel()
    Component.onCompleted: applyRenderLevel()

    function applyRenderLevel() {
        const L = renderLevel
        // 0: mpv's high quality defaults; 1: no HDR peak detection and
        // cheap chroma upscaling; 2: fastest scalers (good for 4K60 on iGPUs).
        player.mpv.setOption("scale", L >= 2 ? "bilinear" : "lanczos")
        player.mpv.setOption("cscale", L >= 1 ? "bilinear" : "lanczos")
        player.mpv.setOption("dscale", "hermite")
        player.mpv.setOption("correct-downscaling", true)
        player.mpv.setOption("sigmoid-upscaling", L === 0)
        player.mpv.setOption("dither-depth", L >= 2 ? "no" : "auto")
        player.mpv.setOption("hdr-compute-peak", L === 0 ? "auto" : "no")
    }

    // Counts presented frames, so drops caused by the window not being shown
    // (another workspace, minimized) are not mistaken for a slow GPU.
    property int presentedFrames: 0
    Connections {
        target: player.Window.window
        function onFrameSwapped() { adaptive.presentedFrames++ }
    }

    Timer {
        id: dropMonitor
        interval: 2000
        repeat: true
        running: player.loaded && !player.mpv.paused && !player.mpv.seeking && player.qualityMode === 0
        property real lastDrops: -1
        property real lastPosition: 0
        property int lastPresented: 0
        property int badStreak: 0
        property int goodTime: 0
        property bool probing: false
        property bool probed: false
        function reset() {
            lastDrops = -1
            badStreak = 0
        }
        onRunningChanged: reset()
        onTriggered: {
            const drops = Number(player.mpv.getProperty("frame-drop-count")) || 0
            const position = player.mpv.position
            const presented = adaptive.presentedFrames - lastPresented
            const frames = (position - lastPosition) * player.mpv.fps
            if (lastDrops >= 0 && player.mpv.fps > 0 && frames > 0 && presented >= frames * 0.5) {
                const rate = (drops - lastDrops) / frames
                if (rate > 0.04) {
                    goodTime = 0
                    if (++badStreak >= 2 && adaptive.autoLevel < 2) {
                        badStreak = 0
                        probing = false
                        adaptive.autoLevel++
                        player.qualityLearned(adaptive.qualityClass, adaptive.autoLevel)
                    }
                } else {
                    badStreak = 0
                    goodTime += interval
                    if (goodTime >= 30000) {
                        goodTime = 0
                        if (probing) {
                            // The better level held up: remember it.
                            probing = false
                            player.qualityLearned(adaptive.qualityClass, adaptive.autoLevel)
                        } else if (!probed && adaptive.autoLevel > 0) {
                            // Like YouTube's adaptive quality, try one step up.
                            probed = true
                            probing = true
                            adaptive.autoLevel--
                        }
                    }
                }
            }
            lastDrops = drops
            lastPosition = position
            lastPresented = adaptive.presentedFrames
        }
    }

    Connections {
        target: player.mpv
        function onPlaybackRestarted() { dropMonitor.reset() }
        function onFileStarted() {
            dropMonitor.reset()
            dropMonitor.probed = false
            dropMonitor.probing = false
            dropMonitor.goodTime = 0
        }
    }
}
