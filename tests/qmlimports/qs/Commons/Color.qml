pragma Singleton
import QtQuick

QtObject {
    readonly property color accent: "#7eb6ff"
    readonly property color background: "#101418"
    readonly property color urgent: "#e85d4c"
    readonly property QtObject popups: QtObject {
        readonly property color text: "#e6e5dd"
        readonly property color background: "#243044"
        readonly property color border: "#3a4a60"
    }
}
