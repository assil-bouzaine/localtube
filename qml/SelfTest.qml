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
    property double waitingSince: Date.now()

    function check(condition, message) {
        if (!condition) throw new Error(message)
    }

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
            throw new Error("No item " + name)
        }
        return item.mapToItem(null, item.width * (fx === undefined ? 0.5 : fx), item.height * (fy === undefined ? 0.5 : fy))
    }
    function move(p) { Platform.mouseMove(win, p.x, p.y) }
    function click(p) { Platform.mouseMove(win, p.x, p.y); Platform.mouseClick(win, p.x, p.y, 1) }
    function rightClick(p) { Platform.mouseMove(win, p.x, p.y); Platform.mouseClick(win, p.x, p.y, 2) }
    function key(k, text) { window.handleKey({ key: k, text: text || "", modifiers: 0, accepted: false }) }
    function shot(name) {
        const ok = Platform.grab(win, dir + "/" + name + ".png")
        check(ok, "Could not save screenshot " + name)
        Platform.log("SELFTEST: shot " + name)
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
        if (dir.indexOf("/home-controls") >= 0) {
            steps = [
                [100, () => {
                    const card = find(win.contentItem, "historyCard0")
                    check(card !== null, "Continue-watching card was not created")
                    check(card.activeFocusOnTab, "History card cannot receive keyboard focus")
                    card.forceActiveFocus()
                    check(card.activeFocus, "History card did not receive focus")
                    Platform.key(win, Qt.Key_Delete)
                }],
                [200, () => {
                    const home = find(win.contentItem, "homeScreen")
                    check(home.recent.length === 0, "Delete did not remove the focused history card")
                    check(History.save(), "History removal was not saved")
                    shot("home_after_remove")
                    Platform.log("SELFTEST: home keyboard checks passed")
                    Platform.quit(0)
                }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
        if (dir.indexOf("/regression") >= 0) {
            steps = [
                [100, () => {
                    check(player.loaded, "Video did not load")
                    player.mpv.paused = true
                    player.mpv.scrub(5)
                    player.mpv.scrub(10)
                    player.mpv.scrub(15)
                    player.mpv.seekTo(20, true)
                }],
                [1200, () => {
                    check(Math.abs(player.mpv.position - 20) < 0.25, "A preview overrode the committed seek")
                    window.saveProgress()
                    check(History.save(), "History save failed")
                    check(Math.abs(History.resumePosition(player.mpv.path) - 20) < 0.25, "Resume position was not saved")
                    window.notification = ""
                    player.mpv.setOption("screenshot-directory", "/dev/null/localtube")
                    player.mpv.screenshot()
                    check(window.notification === "", "Screenshot reported success before completion")
                }],
                [1000, () => {
                    check(window.notification.indexOf("screenshot failed") >= 0, "Screenshot failure was not reported")
                    Platform.log("SELFTEST: playback regression checks passed")
                    Platform.quit(0)
                }],
            ]
            timer.interval = steps[0][0]
            timer.start()
            return
        }
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
            // Wait for actual readiness instead of assuming decoding starts in time.
            if (test.step === 0 && Platform.initialFiles.length && !player.loaded) {
                if (window.errorText !== "" || Date.now() - test.waitingSince > 15000) {
                    Platform.log("SELFTEST FAILED: " + (window.errorText || "Playback readiness timed out"))
                    Platform.quit(1)
                    return
                }
                interval = 100
                start()
                return
            }
            try {
                test.steps[test.step][1]()
            } catch (error) {
                Platform.log("SELFTEST FAILED: " + error)
                Platform.quit(1)
                return
            }
            test.step++
            if (test.step < test.steps.length) {
                interval = test.steps[test.step][0]
                start()
            }
        }
    }
}
