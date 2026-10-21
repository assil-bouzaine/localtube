import QtQuick
import QtQuick.Effects
import LocalTube

// The player: video surface plus every YouTube-style overlay.
Item {
    id: player
    clip: true

    // ---------------------------------------------------------- inputs
    property bool fullscreen: false
    property bool theater: true
    property bool miniplayer: false
    property bool autoplay: true
    property bool hasNext: false
    property bool hasPrevious: false
    property var nextItem: null          // { title, poster, duration }
    property var endScreenItems: []       // [{ index, title, poster, duration, progress }]
    property string displayTitle: ""
    property string channel: ""
    property string youtubeId: ""
    property int qualityMode: 0           // 0 auto, 1 high, 2 balanced, 3 performance
    property var qualityMemory: ({})      // adaptive level per resolution class
    property bool stableVolume: false

    signal nextRequested()
    signal previousRequested()
    signal playIndexRequested(int index)
    signal fullscreenToggled()
    signal theaterToggled()
    signal miniplayerToggled()
    signal autoplayToggled()
    signal captionsPreferenceChanged(bool enabled)
    signal qualityModeRequested(int mode)
    signal qualityLearned(string key, int level)
    signal stableVolumeRequested(bool enabled)
    signal openFilesRequested()
    signal openFolderRequested()
    signal addSubtitleRequested()
    signal showInFolderRequested()

    readonly property alias mpv: mpv
    readonly property alias thumbnailer: thumbnailer
    readonly property alias settingsMenu: settingsMenu
    readonly property alias statsPanel: statsPanel
    readonly property alias shortcutsDialog: shortcutsDialog
    readonly property alias upNext: upNext
    readonly property alias bezel: bezel

    // ----------------------------------------------------------- state
    readonly property bool loaded: mpv.fileLoaded
    readonly property bool ended: mpv.eofReached && mpv.fileLoaded
    property bool showRemaining: false
    property int sleepMinutes: 0          // -1: end of video
    property double sleepDeadline: 0

    readonly property var subtitleTracks: mpv.tracks.filter(t => t.type === "sub")
    readonly property var audioTracks: mpv.tracks.filter(t => t.type === "audio")
    readonly property var currentSubtitle: subtitleTracks.find(t => t.selected) || null
    readonly property var currentAudio: audioTracks.find(t => t.selected) || null
    readonly property bool captionsOn: currentSubtitle !== null
    readonly property var currentChapter: mpv.chapter >= 0 && mpv.chapter < mpv.chapters.length ? mpv.chapters[mpv.chapter] : null

    readonly property int videoW: mpv.videoParams.dw || 0
    readonly property int videoH: mpv.videoParams.dh || 0
    readonly property bool isHdr: mpv.videoParams.gamma === "pq" || mpv.videoParams.gamma === "hlg"
    // YouTube names resolutions after the short side ("1080p"), also for portrait video.
    readonly property int lines: Math.min(videoW, videoH)
    readonly property string qualityLabel: {
        if (!lines)
            return ""
        const fps = mpv.fps > 35 ? Math.round(mpv.fps) : 0
        return lines + "p" + (fps ? fps : "") + (isHdr ? " HDR" : "")
    }
    readonly property string qualityBadge: {
        if (!lines) return ""
        if (isHdr) return "HDR"
        if (lines >= 4320) return "8K"
        if (lines >= 2880) return "5K"
        if (lines >= 2160) return "4K"
        if (lines >= 720) return "HD"
        return ""
    }

    // -------------------------------------------- metrics (delhi modern)
    readonly property bool bigMode: fullscreen && width >= 1000
    readonly property bool xsmall: width < 528
    readonly property real barHeight: xsmall ? 64 : bigMode ? 96 : 72
    readonly property real pillHeight: xsmall ? 40 : bigMode ? 56 : 48
    readonly property real pillTop: (barHeight - pillHeight) / 2
    readonly property real playSize: xsmall ? 52 : bigMode ? 72 : 56
    readonly property real buttonWidth: xsmall ? 40 : bigMode ? 56 : 48
    readonly property real iconSize: xsmall ? 18 : 24
    readonly property real sidePadding: bigMode ? 24 : 12
    readonly property real fontSize: bigMode ? 16 : 14

    // ---------------------------------------------- controls visibility
    property bool pointerActive: false
    property bool keyboardActive: false
    readonly property bool popupOpen: settingsMenu.open || contextMenu.open || chapterMenu.open
    readonly property bool controlsVisible: loaded && (mpv.paused || ended || popupOpen || pointerActive || keyboardActive
                                                       || controlBar.hovered || progressBar.active || miniplayer && videoMouse.containsMouse)

    function poke() {
        pointerActive = true
        hideTimer.restart()
    }

    function flashControls() {
        keyboardActive = true
        keyboardTimer.restart()
    }

    function closePopups() {
        settingsMenu.close()
        contextMenu.close()
        chapterMenu.close()
    }

    Timer { id: hideTimer; interval: 3000; onTriggered: player.pointerActive = false }
    Timer { id: keyboardTimer; interval: 1500; onTriggered: player.keyboardActive = false }

    // ------------------------------------------------------- actions
    function togglePause(withBezel) {
        if (!loaded)
            return
        if (ended) {
            replay()
            if (withBezel) bezel.flash(Icons.play, "")
            return
        }
        const pause = !mpv.paused
        mpv.paused = pause
        if (withBezel)
            bezel.flash(pause ? Icons.pause : Icons.play, "")
    }

    function replay() {
        upNext.cancel()
        mpv.seekTo(0, true)
        mpv.paused = false
    }

    function seekRelative(seconds) {
        if (!loaded)
            return
        if (ended && seconds > 0)
            return
        mpv.seekBy(seconds, true)
        seekIndicator.show(seconds > 0 ? 1 : -1, Math.abs(seconds))
        flashControls()
    }

    function seekToFraction(fraction) {
        if (!loaded || mpv.duration <= 0)
            return
        upNext.cancel()
        mpv.seekTo(mpv.duration * fraction, true)
        flashControls()
    }

    function volumeIcon(volume, muted) {
        if (muted || volume <= 0) return Icons.volumeOff
        return volume < 50 ? Icons.volumeDown : Icons.volumeUp
    }

    function changeVolume(delta) {
        const v = Math.max(0, Math.min(100, Math.round(mpv.volume + delta)))
        mpv.volume = v
        if (mpv.muted && delta > 0)
            mpv.muted = false
        bezel.flash(volumeIcon(v, mpv.muted && delta <= 0), v + "%")
    }

    function toggleMute() {
        const mute = !mpv.muted
        mpv.muted = mute
        bezel.flash(mute ? Icons.volumeOff : volumeIcon(mpv.volume, false), mute ? "" : Math.round(mpv.volume) + "%")
    }

    function setSpeed(speed) {
        speed = Math.round(Math.max(0.25, Math.min(4, speed)) * 100) / 100
        mpv.speed = speed
        bezel.flashText(speed + "x")
    }

    function trackLabel(t) {
        if (!t) return ""
        let name = t.title || ""
        const lang = t.lang ? languageName(t.lang) : ""
        if (!name) name = lang
        else if (lang && name.toLowerCase().indexOf(lang.toLowerCase()) < 0 && name.length < 24) name = lang + " · " + name
        if (!name) name = qsTr("Track %1").arg(t.id)
        if (t.forced) name += qsTr(" (forced)")
        return name
    }

    function languageName(code) {
        const names = { en: "English", eng: "English", es: "Spanish", spa: "Spanish", fr: "French", fre: "French", fra: "French",
                        de: "German", ger: "German", deu: "German", it: "Italian", ita: "Italian", pt: "Portuguese", por: "Portuguese",
                        ru: "Russian", rus: "Russian", ja: "Japanese", jpn: "Japanese", ko: "Korean", kor: "Korean",
                        zh: "Chinese", chi: "Chinese", zho: "Chinese", ar: "Arabic", ara: "Arabic", hi: "Hindi", hin: "Hindi",
                        tr: "Turkish", tur: "Turkish", nl: "Dutch", dut: "Dutch", nld: "Dutch", pl: "Polish", pol: "Polish",
                        sv: "Swedish", swe: "Swedish", id: "Indonesian", ind: "Indonesian", vi: "Vietnamese", vie: "Vietnamese",
                        th: "Thai", tha: "Thai", fa: "Persian", per: "Persian", fas: "Persian", he: "Hebrew", heb: "Hebrew",
                        uk: "Ukrainian", ukr: "Ukrainian", el: "Greek", gre: "Greek", ell: "Greek", cs: "Czech", cze: "Czech",
                        ro: "Romanian", rum: "Romanian", hu: "Hungarian", hun: "Hungarian", da: "Danish", dan: "Danish",
                        fi: "Finnish", fin: "Finnish", no: "Norwegian", nor: "Norwegian" }
        const base = code.split(/[-_]/)[0].toLowerCase()
        return names[base] || code
    }

    function toggleCaptions() {
        if (!loaded)
            return
        if (subtitleTracks.length === 0) {
            bezel.flashText(qsTr("No subtitles available"))
            return
        }
        if (captionsOn) {
            mpv.selectTrack("sub", null)
            bezel.flash(Icons.captions, qsTr("Subtitles/closed captions off"))
            captionsPreferenceChanged(false)
        } else {
            const track = preferredSubtitle()
            mpv.selectTrack("sub", track.id)
            bezel.flash(Icons.captionsOn, trackLabel(track))
            captionsPreferenceChanged(true)
        }
    }

    function preferredSubtitle() {
        return subtitleTracks.find(t => t["default"]) || subtitleTracks.find(t => t.external) || subtitleTracks[0]
    }

    function cycleChapter(direction) {
        const chapters = mpv.chapters
        if (!chapters.length)
            return
        let index = mpv.chapter + direction
        if (direction < 0 && mpv.chapter >= 0 && mpv.position - chapters[mpv.chapter].time > 3)
            index = mpv.chapter
        index = Math.max(0, Math.min(chapters.length - 1, index))
        mpv.seekTo(chapters[index].time, true)
        bezel.flashText(chapters[index].title || qsTr("Chapter %1").arg(index + 1))
        flashControls()
    }

    function frameStep(backwards) {
        if (!loaded)
            return
        if (!mpv.paused)
            mpv.paused = true
        mpv.frameStep(backwards)
        flashControls()
    }

    function takeScreenshot() {
        if (!loaded)
            return
        mpv.screenshot()
        bezel.flashText(qsTr("Screenshot saved to Pictures"))
    }

    function setSleepTimer(minutes) {
        sleepMinutes = minutes
        sleepDeadline = minutes > 0 ? Date.now() + minutes * 60000 : 0
    }

    function onFileEnded() {
        if (sleepMinutes === -1) {
            setSleepTimer(0)
            return
        }
        if (autoplay && hasNext)
            upNext.start()
        else
            upNext.showEndScreen()
    }

    // ---------------------------------------------- adaptive quality
    property int autoLevel: 0
    readonly property int renderLevel: qualityMode === 0 ? autoLevel : qualityMode - 1
    readonly property string qualityClass: lines ? lines + "p" + (mpv.fps > 35 ? "60" : "30") + (isHdr ? "hdr" : "") : ""

    onQualityClassChanged: {
        if (!qualityClass)
            return
        const remembered = qualityMemory[qualityClass]
        if (remembered !== undefined)
            autoLevel = remembered
        else
            autoLevel = (isHdr || videoW * videoH * Math.max(mpv.fps, 30) > 3840 * 2160 * 31) ? 1 : 0
    }
    onRenderLevelChanged: applyRenderLevel()
    Component.onCompleted: applyRenderLevel()

    function applyRenderLevel() {
        const L = renderLevel
        // 0: mpv's high quality defaults; 1: no HDR peak detection and
        // cheap chroma upscaling; 2: fastest scalers (good for 4K60 on iGPUs).
        mpv.setOption("scale", L >= 2 ? "bilinear" : "lanczos")
        mpv.setOption("cscale", L >= 1 ? "bilinear" : "lanczos")
        mpv.setOption("dscale", "hermite")
        mpv.setOption("correct-downscaling", true)
        mpv.setOption("sigmoid-upscaling", L === 0)
        mpv.setOption("dither-depth", L >= 2 ? "no" : "auto")
        mpv.setOption("hdr-compute-peak", L === 0 ? "auto" : "no")
    }

    // Counts presented frames, so drops caused by the window not being shown
    // (another workspace, minimized) are not mistaken for a slow GPU.
    property int presentedFrames: 0
    Connections {
        target: player.Window.window
        function onFrameSwapped() { player.presentedFrames++ }
    }

    Timer {
        id: dropMonitor
        interval: 2000
        repeat: true
        running: player.loaded && !mpv.paused && !mpv.seeking && player.qualityMode === 0
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
            const drops = Number(mpv.getProperty("frame-drop-count")) || 0
            const position = mpv.position
            const presented = player.presentedFrames - lastPresented
            const frames = (position - lastPosition) * mpv.fps
            if (lastDrops >= 0 && mpv.fps > 0 && frames > 0 && presented >= frames * 0.5) {
                const rate = (drops - lastDrops) / frames
                if (rate > 0.04) {
                    goodTime = 0
                    if (++badStreak >= 2 && player.autoLevel < 2) {
                        badStreak = 0
                        probing = false
                        player.autoLevel++
                        player.qualityLearned(player.qualityClass, player.autoLevel)
                    }
                } else {
                    badStreak = 0
                    goodTime += interval
                    if (goodTime >= 30000) {
                        goodTime = 0
                        if (probing) {
                            // The better level held up: remember it.
                            probing = false
                            player.qualityLearned(player.qualityClass, player.autoLevel)
                        } else if (!probed && player.autoLevel > 0) {
                            // Like YouTube's adaptive quality, try one step up.
                            probed = true
                            probing = true
                            player.autoLevel--
                        }
                    }
                }
            }
            lastDrops = drops
            lastPosition = position
            lastPresented = player.presentedFrames
        }
    }

    Connections {
        target: mpv
        function onPlaybackRestarted() { dropMonitor.reset() }
        function onFileStarted() {
            dropMonitor.probed = false
            dropMonitor.probing = false
            dropMonitor.goodTime = 0
            upNext.cancel()
            player.showRemaining = false
        }
        function onEofReachedChanged() {
            if (mpv.eofReached)
                player.onFileEnded()
            else
                upNext.cancel()
        }
    }

    onStableVolumeChanged: mpv.audioFilter = stableVolume ? "@stablevolume:lavfi=[dynaudnorm=f=200:g=15:p=0.9:m=10]" : ""

    // Captions move up while the control bar is showing, like on YouTube.
    function updateSubtitleMargin() {
        if (height <= 0)
            return
        const px = controlsVisible ? barHeight + 14 : 24
        mpv.setOption("sub-margin-y", Math.round(px * 720 / height))
    }
    onControlsVisibleChanged: updateSubtitleMargin()
    onHeightChanged: {
        updateSubtitleMargin()
        updateBlurArea()
    }
    onBarHeightChanged: updateSubtitleMargin()

    // ---------------------------------------------------------- video
    MpvObject {
        id: mpv
        anchors.fill: parent
    }

    Thumbnailer {
        id: thumbnailer
        source: mpv.fileLoaded ? mpv.path : ""
        duration: mpv.duration
    }

    ShaderEffectSource {
        id: blurSource
        sourceItem: mpv
        hideSource: false
        visible: false
        live: player.controlsVisible || bezel.active || upNext.active || seekIndicator.opacity > 0
        mipmap: true
        smooth: true
        textureSize: Qt.size(Math.max(16, Math.round(mpv.width / 2)), Math.max(16, Math.round(mpv.height / 2)))
    }

    function updateBlurArea() {
        const p = mpv.mapToItem(null, 0, 0)
        Theme.blurArea = Qt.rect(p.x, p.y, Math.max(1, mpv.width), Math.max(1, mpv.height))
    }
    onWidthChanged: updateBlurArea()
    onXChanged: updateBlurArea()
    Component.onDestruction: Theme.blurSource = null
    Item {
        Component.onCompleted: {
            Theme.blurSource = blurSource
            Theme.tooltip = tooltip
            player.updateBlurArea()
        }
    }

    // ------------------------------------------- pointer on the video
    MouseArea {
        id: videoMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: player.controlsVisible || !player.loaded ? Qt.ArrowCursor : Qt.BlankCursor

        onPositionChanged: player.poke()
        onEntered: player.poke()
        onExited: {
            hideTimer.stop()
            player.pointerActive = false
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                chapterMenu.close()
                settingsMenu.close()
                contextMenu.openAt(mouse.x, mouse.y)
                return
            }
            if (player.popupOpen) {
                player.closePopups()
                return
            }
            if (!player.loaded)
                return
            player.togglePause(true)
        }
        onDoubleClicked: mouse => {
            if (mouse.button !== Qt.LeftButton || !player.loaded)
                return
            // The first click already toggled playback; undo it.
            mpv.paused = !mpv.paused
            bezel.cancel()
            player.fullscreenToggled()
        }
        onWheel: wheel => {
            if (!player.loaded)
                return
            player.changeVolume(wheel.angleDelta.y > 0 ? 5 : wheel.angleDelta.y < 0 ? -5 : 0)
            player.poke()
        }
    }

    // ------------------------------------------------------ overlays
    Spinner {
        anchors.centerIn: parent
        big: player.bigMode
        active: player.loaded && !mpv.paused && (mpv.buffering || mpv.seeking)
    }

    Bezel {
        id: bezel
        anchors.fill: parent
        big: player.bigMode
    }

    SeekIndicator {
        id: seekIndicator
        anchors.fill: parent
        big: player.bigMode
    }

    UpNext {
        id: upNext
        anchors.fill: parent
        anchors.bottomMargin: player.barHeight + 6
        player: player
    }

    // Top: title (and channel) of the video.
    Item {
        id: titleBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: titleColumn.implicitHeight + titleColumn.y + 8
        opacity: player.controlsVisible && !player.xsmall ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: player.controlsVisible ? 250 : 100; easing.type: Easing.Bezier; easing.bezierCurve: player.controlsVisible ? Theme.curveIn : Theme.curveOut }
        }

        Column {
            id: titleColumn
            x: player.sidePadding + 4
            y: player.bigMode ? 18 : 12
            width: parent.width - 2 * x
            spacing: 2
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.6
                shadowBlur: 0.35
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            Text {
                width: parent.width
                text: player.displayTitle
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: player.bigMode ? 27 : 18
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: player.channel
                color: Theme.textSecondary
                font.family: Theme.font
                font.pixelSize: player.bigMode ? 17 : 13
                elide: Text.ElideRight
            }
        }
    }

    // Bottom: progress bar and control bar.
    Item {
        id: chrome
        anchors.fill: parent
        opacity: player.controlsVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: player.controlsVisible ? 250 : 100; easing.type: Easing.Bezier; easing.bezierCurve: player.controlsVisible ? Theme.curveIn : Theme.curveOut }
        }

        ProgressBar {
            id: progressBar
            objectName: "progressBar"
            player: player
            x: player.sidePadding
            width: parent.width - 2 * player.sidePadding
            y: parent.height - player.barHeight - height
        }

        ControlBar {
            id: controlBar
            player: player
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: player.barHeight
            onSettingsClicked: {
                contextMenu.close()
                chapterMenu.close()
                settingsMenu.toggle()
            }
            onChapterClicked: item => {
                settingsMenu.close()
                contextMenu.close()
                chapterMenu.toggleBelow(item)
            }
        }
    }

    StatsPanel {
        id: statsPanel
        player: player
        x: 10
        y: 10
    }

    SettingsMenu {
        id: settingsMenu
        player: player
        anchors.right: parent.right
        anchors.rightMargin: player.sidePadding
        y: parent.height - player.barHeight - 6 - height
    }

    ChapterMenu {
        id: chapterMenu
        player: player
    }

    ContextMenu {
        id: contextMenu
        player: player
    }

    Tooltip {
        id: tooltip
        bottomY: player.height - player.barHeight - 22
    }

    ShortcutsDialog {
        id: shortcutsDialog
        anchors.fill: parent
    }

    // Sleep timer.
    Timer {
        interval: 1000
        repeat: true
        running: player.sleepDeadline > 0
        onTriggered: {
            if (Date.now() >= player.sleepDeadline) {
                player.setSleepTimer(0)
                mpv.paused = true
                bezel.flashText(qsTr("Sleep timer: paused"))
            }
        }
    }
}
