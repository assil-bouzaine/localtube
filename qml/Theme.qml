pragma Singleton
import QtQuick

// Design tokens taken from YouTube's current ("delhi modern") player CSS.
QtObject {
    readonly property string font: "Roboto"

    // Set by PlayerView: the blurred video behind frosted-glass elements.
    property Item blurSource: null
    property rect blurArea: Qt.rect(0, 0, 1, 1)
    property bool blurEnabled: true
    // Set by PlayerView: the shared button tooltip.
    property Item tooltip: null

    readonly property color brandRed: "#ff0033"
    readonly property color progressPink: "#ff2791"
    readonly property color white: "#ffffff"
    readonly property color text: "#ffffff"
    readonly property color textMenu: "#eeeeee"
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.7)
    readonly property color textTertiary: "#aaaaaa"
    readonly property color hover: Qt.rgba(1, 1, 1, 0.1)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.2)
    readonly property color divider: Qt.rgba(1, 1, 1, 0.2)

    readonly property color progressTrack: Qt.rgba(40 / 255, 40 / 255, 40 / 255, 0.6)
    readonly property color progressLoaded: Qt.rgba(1, 1, 1, 0.4)
    readonly property color progressHover: Qt.rgba(1, 1, 1, 0.5)

    // Page colours of YouTube's dark theme.
    readonly property color page: "#0f0f0f"
    readonly property color surface: "#212121"
    readonly property color surfaceHover: "#272727"
    readonly property color textPrimary: "#f1f1f1"

    // Frosted glass tints (black overlay on the blurred video).
    readonly property real tintLight: 0.3
    readonly property real tintMedium: 0.6

    // cubic-bezier(.05, 0, 0, 1), YouTube's standard motion curve.
    readonly property var curve: [0.05, 0, 0, 1, 1, 1]
    // cubic-bezier(0, 0, .2, 1) and (.4, 0, 1, 1): fade in / fade out.
    readonly property var curveIn: [0, 0, 0.2, 1, 1, 1]
    readonly property var curveOut: [0.4, 0, 1, 1, 1, 1]

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0)
            seconds = 0
        seconds = Math.floor(seconds)
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        const s = seconds % 60
        const ss = s < 10 ? "0" + s : "" + s
        if (h > 0)
            return h + ":" + (m < 10 ? "0" + m : m) + ":" + ss
        return m + ":" + ss
    }
}
