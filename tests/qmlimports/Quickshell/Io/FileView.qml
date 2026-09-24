import QtQuick

QtObject {
    property string path: ""
    property bool watchChanges: false
    property bool atomicWrites: false
    property bool printErrors: false

    signal loaded()
    signal loadFailed()
    signal fileChanged()

    function text() {
        return ""
    }

    function setText(value) {
    }

    function reload() {
    }
}
