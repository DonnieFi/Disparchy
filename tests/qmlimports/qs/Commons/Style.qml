pragma Singleton
import QtQuick

QtObject {
    function space(px) {
        var n = Number(px)
        if (!isFinite(n))
            return 1
        return Math.max(1, Math.round(n))
    }

    readonly property QtObject font: QtObject {
        property string family: "sans-serif"
        property int body: 15
        property int bodySmall: 13
        property int caption: 11
    }
    readonly property QtObject bar: QtObject {
        property int iconSlot: 24
    }
    readonly property real cornerRadius: 10
    readonly property real selectedFillAlpha: 0.16
    readonly property color hoverFill: "#1c2836"
    readonly property color normalFill: "#12181f"
    readonly property color hoverBorderColor: "#8aa0b8"
    readonly property color normalBorderColor: "#2c3a48"
    readonly property int gapsOut: 8
    readonly property int spacingPopupPadding: 6

    function selectionFillFor(ink, accent) {
        return Qt.alpha(accent, 0.35)
    }

    function controlFill(hover, selected, ink, accent) {
        if (selected)
            return Qt.alpha(accent, 0.35)
        if (hover)
            return hoverFill
        return normalFill
    }
}
