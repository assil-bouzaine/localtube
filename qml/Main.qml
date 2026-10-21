import QtCore
import QtQuick
import QtQuick.Window
import LocalTube

Window {
    id: window

    width: Math.round(Math.min(Screen.desktopAvailableWidth * 0.75, 1280))
    height: Math.round(width * 9 / 16)
    minimumWidth: 320
    minimumHeight: 180
    visible: true
    color: "black"
    title: player.loaded && player.displayTitle ? player.displayTitle + " - LocalTube" : "LocalTube"

    Settings {
        id: settings
        location: Platform.settingsFile
        property real volume: 100
        property bool muted: false
        property bool autoplay: true
        property bool theater: true
        property int captions: -1        // -1: file default, 0: off, 1: on
        property bool stableVolume: false
        property int qualityMode: 0
        property string qualityMemory: "{}"
        property real subScale: 1.0
        property string lastFolder: ""
    }

    PlaylistModel { id: playlist }

    property bool loading: false
    property bool captionsPending: false
    property string errorText: ""
    property bool miniplayer: false
    property rect savedGeometry
    property bool wasMaximized: false
    readonly property bool fullscreen: visibility === Window.FullScreen
    readonly property real panelWidth: Math.min(402, Math.round(width * 0.36))
    readonly property bool panelVisible: !settings.theater && !fullscreen && !miniplayer && player.loaded
                                         && playlist.count > 0 && width >= 860

    // ------------------------------------------------------- opening
    function openPaths(paths) {
        const index = playlist.open(paths)
        if (index >= 0)
            playIndex(index)
        if (paths.length)
            settings.lastFolder = Platform.dirName(playlist.pathAt(Math.max(0, index)) || paths[0])
    }

    function openFiles() {
        const files = Platform.openFiles(settings.lastFolder)
        if (files.length)
            openPaths(files)
    }

    function openFolder() {
        const dir = Platform.openFolder(settings.lastFolder)
        if (dir)
            openPaths([dir])
    }

    function addSubtitle() {
        const file = Platform.openSubtitle(player.loaded ? Platform.dirName(player.mpv.path) : settings.lastFolder)
        if (file) {
            player.mpv.addSubtitle(file)
            settings.captions = 1
        }
    }

    function saveProgress() {
        const m = player.mpv
        if (m.fileLoaded && m.duration > 0 && !m.eofReached)
            History.update(m.path, m.position, m.duration)
    }

    property int pendingIndex: -1
    function playIndex(index) {
        const path = playlist.pathAt(index)
        if (!path)
            return
        saveProgress()
        playlist.currentIndex = index
        errorText = ""
        loading = true
        if (!player.mpv.ready) {
            pendingIndex = index
            return
        }
        player.mpv.loadFile(path, History.resumePosition(path), false)
    }

    function next() {
        if (playlist.currentIndex + 1 < playlist.count)
            playIndex(playlist.currentIndex + 1)
    }

    function previous() {
        // Like YouTube: restart the current video first if it is well under way.
        if (player.mpv.position > 5 || playlist.currentIndex <= 0)
            player.mpv.seekTo(0, true)
        else
            playIndex(playlist.currentIndex - 1)
    }

    // ------------------------------------------------- window modes
    function toggleFullscreen() {
        if (miniplayer)
            setMiniplayer(false)
        if (fullscreen) {
            visibility = wasMaximized ? Window.Maximized : Window.Windowed
        } else {
            wasMaximized = visibility === Window.Maximized
            visibility = Window.FullScreen
        }
    }

    function setMiniplayer(on) {
        if (on === miniplayer)
            return
        if (on && fullscreen)
            visibility = Window.Windowed
        miniplayer = on
        if (Platform.setMiniplayer(window, on))
            return
        if (on) {
            savedGeometry = Qt.rect(x, y, width, height)
            flags = flags | Qt.WindowStaysOnTopHint
            width = 480
            height = 270
            x = Screen.desktopAvailableWidth - width - 24
            y = Screen.desktopAvailableHeight - height - 24
        } else {
            flags = flags & ~Qt.WindowStaysOnTopHint
            x = savedGeometry.x
            y = savedGeometry.y
            width = savedGeometry.width
            height = savedGeometry.height
        }
    }

    // ---------------------------------------------- captions preference
    function applyCaptionPreference() {
        if (!captionsPending || !player.mpv.fileLoaded)
            return
        captionsPending = false
        const tracks = (player.mpv.getProperty("track-list") || []).filter(t => t.type === "sub")
        const selected = tracks.some(t => t.selected)
        if (settings.captions === 0 && selected)
            player.mpv.selectTrack("sub", null)
        else if (settings.captions === 1 && !selected && tracks.length) {
            const pick = tracks.find(t => t["default"]) || tracks.find(t => t.external) || tracks[0]
            player.mpv.selectTrack("sub", pick.id)
        }
    }

    // ------------------------------------------------- metadata helpers
    function metadataValue(names) {
        const m = player.mpv.metadata
        for (const name of names) {
            for (const key in m) {
                if (key.toLowerCase() === name && m[key])
                    return String(m[key])
            }
        }
        return ""
    }

    readonly property string youtubeId: {
        const path = player.mpv.path
        let match = /\[([A-Za-z0-9_-]{11})\]\.[A-Za-z0-9]+$/.exec(path)
        if (match)
            return match[1]
        const text = metadataValue(["purl", "comment", "description", "synopsis", "url"])
        match = /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/shorts\/)([A-Za-z0-9_-]{11})/.exec(text)
        return match ? match[1] : ""
    }

    readonly property var nextItem: {
        MediaInfo.revision
        const i = playlist.currentIndex + 1
        if (i <= 0 || i >= playlist.count)
            return null
        const path = playlist.pathAt(i)
        return { title: playlist.titleAt(i), poster: MediaInfo.poster(path), duration: MediaInfo.duration(path) }
    }

    readonly property var endScreenItems: {
        MediaInfo.revision
        const items = []
        const n = playlist.count
        const current = playlist.currentIndex
        for (let k = 1; k < n && items.length < 8; k++) {
            const i = (current + k) % n
            const path = playlist.pathAt(i)
            items.push({ index: i, title: playlist.titleAt(i), poster: MediaInfo.poster(path),
                         duration: MediaInfo.duration(path), progress: History.progress(path) })
        }
        return items
    }

    // ----------------------------------------------------------- UI
    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => window.handleKey(event)

        PlayerView {
            id: player
            width: window.panelVisible ? parent.width - window.panelWidth : parent.width
            height: parent.height

            fullscreen: window.fullscreen
            theater: settings.theater
            miniplayer: window.miniplayer
            autoplay: settings.autoplay
            hasNext: playlist.currentIndex >= 0 && playlist.currentIndex + 1 < playlist.count
            hasPrevious: playlist.currentIndex > 0
            nextItem: window.nextItem
            endScreenItems: window.endScreenItems
            displayTitle: {
                const t = mpv.mediaTitle
                const path = mpv.path
                return t && t !== Platform.fileName(path) ? t : MediaInfo.displayTitle(path)
            }
            channel: window.metadataValue(["artist", "album_artist", "uploader", "channel", "author"])
            youtubeId: window.youtubeId
            qualityMode: settings.qualityMode
            qualityMemory: JSON.parse(settings.qualityMemory || "{}")
            stableVolume: settings.stableVolume

            onNextRequested: window.next()
            onPreviousRequested: window.previous()
            onPlayIndexRequested: index => window.playIndex(index)
            onFullscreenToggled: window.toggleFullscreen()
            onTheaterToggled: settings.theater = !settings.theater
            onMiniplayerToggled: window.setMiniplayer(!window.miniplayer)
            onAutoplayToggled: settings.autoplay = !settings.autoplay
            onCaptionsPreferenceChanged: enabled => settings.captions = enabled ? 1 : 0
            onQualityModeRequested: mode => settings.qualityMode = mode
            onQualityLearned: (key, level) => {
                const memory = JSON.parse(settings.qualityMemory || "{}")
                memory[key] = level
                settings.qualityMemory = JSON.stringify(memory)
            }
            onStableVolumeRequested: enabled => settings.stableVolume = enabled
            onOpenFilesRequested: window.openFiles()
            onOpenFolderRequested: window.openFolder()
            onAddSubtitleRequested: window.addSubtitle()
            onShowInFolderRequested: Platform.showInFolder(mpv.path)
        }

        PlaylistPanel {
            visible: window.panelVisible
            x: player.width
            width: window.panelWidth
            height: parent.height
            playlist: playlist
            onPlayRequested: index => window.playIndex(index)
        }

        HomeScreen {
            anchors.fill: parent
            visible: !player.loaded && !window.loading && window.errorText === ""
            onOpenFilesRequested: window.openFiles()
            onOpenFolderRequested: window.openFolder()
            onOpenPathRequested: path => window.openPaths([path])
        }

        // Playback error, like YouTube's error screen.
        Rectangle {
            anchors.fill: player
            visible: window.errorText !== ""
            color: "#000000"
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 520)
                spacing: 12
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    icon: Icons.info
                    color: Theme.textSecondary
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("This video can't be played")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 20
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: window.errorText
                    color: Theme.textTertiary
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    visible: playlist.count > 1
                    Text {
                        text: qsTr("Next video ›")
                        color: Theme.text
                        font.family: Theme.font
                        font.weight: Font.Medium
                        font.pixelSize: 14
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.next()
                        }
                    }
                }
            }
        }

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                const paths = Array.from(drop.urls).map(u => Platform.localPath(u))
                const subtitles = paths.filter(p => /\.(srt|vtt|ass|ssa|sub|sup)$/i.test(p))
                if (player.loaded && subtitles.length && subtitles.length === paths.length) {
                    subtitles.forEach(s => player.mpv.addSubtitle(s))
                    settings.captions = 1
                    return
                }
                window.openPaths(paths)
            }
        }
    }

    // ------------------------------------------------------ keyboard
    function handleKey(event) {
        const key = event.key
        const text = event.text
        const ctrl = event.modifiers & Qt.ControlModifier
        const shift = event.modifiers & Qt.ShiftModifier
        const m = player.mpv
        let handled = true

        if (player.shortcutsDialog.open && key !== Qt.Key_Question) {
            if (key === Qt.Key_Escape)
                player.shortcutsDialog.open = false
            event.accepted = true
            return
        }

        if (ctrl && key === Qt.Key_O) openFiles()
        else if (ctrl && key === Qt.Key_Q) window.close()
        else if (ctrl && key === Qt.Key_Left) player.cycleChapter(-1)
        else if (ctrl && key === Qt.Key_Right) player.cycleChapter(1)
        else if (ctrl) handled = false
        else if (key === Qt.Key_Escape) {
            if (player.popupOpen) player.closePopups()
            else if (player.statsPanel.open) player.statsPanel.open = false
            else if (player.upNext.active) player.upNext.cancel()
            else if (fullscreen) toggleFullscreen()
            else if (miniplayer) setMiniplayer(false)
            else handled = false
        }
        else if (key === Qt.Key_Space || key === Qt.Key_K || key === Qt.Key_MediaTogglePlayPause || key === Qt.Key_MediaPlay || key === Qt.Key_MediaPause)
            player.togglePause(true)
        else if (key === Qt.Key_J) player.seekRelative(-10)
        else if (key === Qt.Key_L) player.seekRelative(10)
        else if (key === Qt.Key_Left) player.seekRelative(-5)
        else if (key === Qt.Key_Right) player.seekRelative(5)
        else if (key === Qt.Key_Up) player.changeVolume(5)
        else if (key === Qt.Key_Down) player.changeVolume(-5)
        else if (key === Qt.Key_M) player.toggleMute()
        else if (key === Qt.Key_F) toggleFullscreen()
        else if (key === Qt.Key_T && !shift) settings.theater = !settings.theater
        else if (key === Qt.Key_I) setMiniplayer(!miniplayer)
        else if (key === Qt.Key_C) player.toggleCaptions()
        else if (key === Qt.Key_S && !shift) player.takeScreenshot()
        else if (key === Qt.Key_N && shift) next()
        else if (key === Qt.Key_P && shift) previous()
        else if (key === Qt.Key_MediaNext) next()
        else if (key === Qt.Key_MediaPrevious) previous()
        else if (key >= Qt.Key_0 && key <= Qt.Key_9) player.seekToFraction((key - Qt.Key_0) / 10)
        else if (key === Qt.Key_Home) player.seekToFraction(0)
        else if (key === Qt.Key_End) { if (m.duration > 0) m.seekTo(m.duration, true) }
        else if (text === ",") player.frameStep(true)
        else if (text === ".") player.frameStep(false)
        else if (text === "<") player.setSpeed(m.speed - 0.25)
        else if (text === ">") player.setSpeed(m.speed + 0.25)
        else if (text === "?") player.shortcutsDialog.open = !player.shortcutsDialog.open
        else if (text === "+" || text === "=") setSubScale(settings.subScale + 0.1)
        else if (text === "-" || text === "_") setSubScale(settings.subScale - 0.1)
        else handled = false

        event.accepted = handled
    }

    function setSubScale(scale) {
        settings.subScale = Math.round(Math.max(0.5, Math.min(3, scale)) * 10) / 10
        player.mpv.setOption("sub-scale", settings.subScale)
        player.bezel.flashText(qsTr("Font size %1%").arg(Math.round(settings.subScale * 100)))
    }

    // ------------------------------------------------- mpv lifecycle
    Connections {
        target: player.mpv

        function onReadyChanged() {
            const m = player.mpv
            m.volume = settings.volume
            m.muted = settings.muted
            m.setOption("sub-scale", settings.subScale)
            if (window.pendingIndex >= 0) {
                const index = window.pendingIndex
                window.pendingIndex = -1
                window.playIndex(index)
            } else if (Platform.initialFiles.length) {
                window.openPaths(Platform.initialFiles)
            }
        }
        function onFileStarted() {
            window.captionsPending = true
        }
        function onFileReady() {
            window.loading = false
            window.errorText = ""
            window.applyCaptionPreference()
        }
        function onFileEnded(reason, error) {
            if (reason === "error") {
                window.loading = false
                window.errorText = error + "\n" + Platform.fileName(playlist.pathAt(playlist.currentIndex))
            }
        }
        function onEofReachedChanged() {
            if (player.mpv.eofReached)
                History.markFinished(player.mpv.path, player.mpv.duration)
        }
        function onVolumeChanged() { settings.volume = player.mpv.volume }
        function onMutedChanged() { settings.muted = player.mpv.muted }
        function onPositionChanged() { mpris.updatePosition(player.mpv.position, false) }
        function onPlaybackRestarted() { mpris.updatePosition(player.mpv.position, true) }
        function onPausedChanged() { window.saveProgress() }
    }

    Timer {
        interval: 5000
        repeat: true
        running: player.loaded && !player.mpv.paused
        onTriggered: window.saveProgress()
    }

    // Keep the screen awake while a video plays.
    readonly property bool playing: player.loaded && !player.mpv.paused
    onPlayingChanged: Platform.inhibitIdle(playing)

    onClosing: {
        saveProgress()
        History.save()
        Platform.inhibitIdle(false)
    }

    Mpris {
        id: mpris
        active: player.loaded
        playing: window.playing
        title: player.displayTitle
        artist: player.channel
        path: player.mpv.path
        duration: player.mpv.duration
        artUrl: {
            MediaInfo.revision
            return player.loaded ? MediaInfo.poster(player.mpv.path) : ""
        }
        volume: player.mpv.volume / 100
        canGoNext: player.hasNext
        canGoPrevious: player.hasPrevious || player.loaded

        onPlayPauseRequested: player.togglePause(false)
        onPlayRequested: if (player.mpv.paused || player.ended) player.togglePause(false)
        onPauseRequested: if (!player.mpv.paused) player.togglePause(false)
        onStopRequested: player.mpv.paused = true
        onNextRequested: window.next()
        onPreviousRequested: window.previous()
        onSeekRequested: offset => player.mpv.seekBy(offset, true)
        onSetPositionRequested: position => player.mpv.seekTo(position, true)
        onVolumeRequested: volume => player.mpv.volume = volume * 100
        onRaiseRequested: {
            window.show()
            window.raise()
            window.requestActivate()
        }
        onQuitRequested: window.close()
    }

    Component.onCompleted: {
        if (Platform.startFullscreen)
            toggleFullscreen()
    }

    Loader {
        active: Platform.selfTestDir !== ""
        source: "SelfTest.qml"
    }
}
