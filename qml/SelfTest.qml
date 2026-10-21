import QtQuick
import LocalTube

// Scripted UI walkthrough used during development (localtube --self-test DIR).
// Drives the real UI with synthetic input and saves screenshots.
Item {
    id: test

    readonly property var win: Window.window
    readonly property string dir: Platform.selfTestDir
    property int step: 0
    property var steps: []

    function find(item, name) {
        if (!item)
            return null
        if (item.objectName === name)
            return item
        for (let i = 0; i < item.children.length; i++) {
            const found = find(item.children[i], name)
            if (found)
                return found
        }
        return null
    }
    function center(name, fx, fy) {
        const item = find(win.contentItem, name)
        if (!item) {
            Platform.log("SELFTEST: no item " + name)
            return Qt.point(0, 0)
        }
        return item.mapToItem(null, item.width * (fx === undefined ? 0.5 : fx), item.height * (fy === undefined ? 0.5 : fy))
    }
    function move(p) { Platform.mouseMove(win, p.x, p.y) }
    function click(p) { Platform.mouseMove(win, p.x, p.y); Platform.mouseClick(win, p.x, p.y, 1) }
    function rightClick(p) { Platform.mouseMove(win, p.x, p.y); Platform.mouseClick(win, p.x, p.y, 2) }
    function key(k, text) { window.handleKey({ key: k, text: text || "", modifiers: 0, accepted: false }) }
    function shot(name) {
        const ok = Platform.grab(win, dir + "/" + name + ".png")
        Platform.log("SELFTEST: shot " + name + (ok ? "" : " FAILED"))
    }

    property double seekStart: 0
    property string seekLabel: ""
    Connections {
        target: player.mpv
        function onPlaybackRestarted() {
            if (test.seekStart > 0) {
                Platform.log("SEEK " + test.seekLabel + ": " + (Date.now() - test.seekStart) + " ms")
                test.seekStart = 0
            }
        }
    }

    property real phaseStartDrops: 0
    property real phaseStartPos: 0
    function drops() { return Number(player.mpv.getProperty("frame-drop-count")) || 0 }
    function phaseBegin() {
        phaseStartDrops = drops()
        phaseStartPos = player.mpv.position
    }
    function phaseEnd(name) {
        const frames = Math.round((player.mpv.position - phaseStartPos) * player.mpv.fps)
        Platform.log("PERF " + name + ": dropped " + (drops() - phaseStartDrops) + " of " + frames
                     + " frames | level " + player.renderLevel + " | hwdec " + player.mpv.hwdec + " | " + player.qualityLabel)
    }

    Component.onCompleted: {
        if (dir.indexOf("/readme") >= 0) {
            steps = [
                [4200, () => move(Qt.point(win.width / 2, win.height / 2))],
                [400, () => move(center("progressBar", 0.47, 0.5))],
                [2200, () => shot("readme_player")],
                [100, () => click(center("settingsButton"))],
                [800, () => shot("readme_settings")],
                [100, () => key(Qt.Key_Escape)],
                [200, () => { settings.theater = false }],
                [300, () => move(Qt.point(player.width / 2, player.height / 2))],
                [2500, () => shot("readme_panel")],
                [100, () => { settings.theater = true; Platform.quit(0) }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/history") >= 0) {
            steps = [
                [5000, () => window.playIndex(0)],
                [7000, () => { window.saveProgress(); History.save(); Platform.quit(0) }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/home") >= 0) {
            steps = [
                [4000, () => shot("home")],
                [100, () => Platform.quit(0)],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/panel") >= 0) {
            steps = [
                [300, () => { settings.theater = false }],
                [5000, () => { move(Qt.point(player.width / 2, player.height / 2)) }],
                [600, () => shot("panel")],
                [100, () => { move(center("chapterPill")) }],
                [500, () => click(center("chapterPill"))],
                [900, () => shot("chapters")],
                [100, () => { settings.theater = true; Platform.quit(0) }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/mini") >= 0) {
            steps = [
                [3000, () => window.setMiniplayer(true)],
                [2500, () => { move(Qt.point(win.width / 2, win.height / 2)); shot("mini") }],
                [3000, () => window.setMiniplayer(false)],
                [6000, () => Platform.quit(0)],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/seek") >= 0) {
            const seeks = []
            const run = (exact, delta) => () => {
                seekStart = Date.now()
                player.mpv.seekBy(delta, exact)
                seekLabel = (exact ? "exact " : "keyframe ") + delta
            }
            steps = [[3000, () => {}]]
            for (const exact of [true, false]) {
                for (const delta of [5, -5, 10, -10, 5]) {
                    steps.push([1500, run(exact, delta)])
                }
            }
            steps.push([1500, () => Platform.quit(0)])
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/subs") >= 0) {
            steps = [
                [300, () => { settings.theater = false }],
                [2000, () => move(Qt.point(player.width / 2, player.height / 2))],
                [2500, () => {
                    Platform.log("SUBS margin=" + player.mpv.getProperty("sub-margin-y") + " osd=" + JSON.stringify(player.mpv.getProperty("osd-dimensions")))
                    shot("subs_letterbox")
                }],
                [100, () => { settings.theater = true; Platform.quit(0) }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/big") >= 0) {
            steps = [
                [300, () => { player.fullscreen = true }],
                [3500, () => move(Qt.point(win.width / 2, win.height / 2))],
                [500, () => shot("big_controls")],
                [100, () => move(center("progressBar", 0.55, 0.5))],
                [1500, () => shot("big_hover")],
                [100, () => Platform.quit(0)],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/perf") >= 0) {
            const W = () => win.width
            const H = () => win.height
            steps = [
                [2500, () => { Platform.mouseMove(win, W() / 2, H() / 2); phaseBegin() }],
                [100, () => { player.pointerActive = false }],
                [10000, () => phaseEnd("controls-hidden")],
                [100, () => { move(center("progressBar", 0.3, 0.5)); phaseBegin() }],
            ]
            // Keep the pointer moving over the progress bar during the second phase.
            for (let i = 0; i < 40; i++)
                steps.push([250, () => move(center("progressBar", 0.3 + (step % 20) * 0.02, 0.5))])
            steps.push([10, () => phaseEnd("controls-visible+hover")])
            steps.push([10, () => Platform.quit(0)])
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        const W = () => win.width
        const H = () => win.height
        steps = [
            [3500, () => move(Qt.point(W() / 2, H() / 2))],
            [700, () => {
                shot("01_controls")
                Platform.log("SELFTEST: sub-margin-y=" + player.mpv.getProperty("sub-margin-y") + " controlsVisible=" + player.controlsVisible)
            }],
            [100, () => move(center("progressBar", 0.4, 0.5))],
            [1800, () => shot("02_progress_hover")],
            [100, () => move(center("volumeControl", 0.3, 0.5))],
            [700, () => shot("03_volume_hover")],
            [100, () => click(center("settingsButton"))],
            [600, () => shot("04_settings")],
            [100, () => click(center("speedRow"))],
            [700, () => shot("05_speed_page")],
            [100, () => key(Qt.Key_Escape)],
            [400, () => move(Qt.point(W() / 2, H() / 3))],
            [200, () => key(Qt.Key_K, "k")],
            [330, () => shot("06_bezel_pause")],
            [900, () => key(Qt.Key_Right)],
            [300, () => key(Qt.Key_Right)],
            [250, () => shot("07_seek_indicator")],
            [800, () => key(Qt.Key_Up)],
            [280, () => shot("08_volume_bezel")],
            [800, () => rightClick(Qt.point(W() * 0.4, H() * 0.3))],
            [500, () => shot("09_context_menu")],
            [100, () => key(Qt.Key_Escape)],
            [200, () => { player.statsPanel.open = true }],
            [900, () => shot("10_stats")],
            [100, () => { player.statsPanel.open = false; key(Qt.Key_Question, "?") }],
            [500, () => shot("11_shortcuts")],
            [100, () => key(Qt.Key_Escape)],
            [200, () => { player.mpv.seekTo(Math.max(0, player.mpv.duration - 1.5), true); player.mpv.paused = false }],
            [3200, () => shot("12_end")],
            [100, () => Platform.quit(0)],
        ]
        timer.interval = steps[0][0]
        timer.start()
    }

    Timer {
        id: timer
        onTriggered: {
            test.steps[test.step][1]()
            test.step++
            if (test.step < test.steps.length) {
                interval = test.steps[test.step][0]
                start()
            }
        }
    }
}
