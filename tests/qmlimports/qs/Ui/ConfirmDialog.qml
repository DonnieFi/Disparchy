import QtQuick

Item {
    property bool opened: false
    property string message: ""
    property string confirmText: ""
    property color background: "black"
    property color foreground: "white"
    property color selectedText: "white"
    property string fontFamily: ""
    property real cornerRadius: 0
    property int selectedIndex: 0

    signal canceled()
    signal confirmed()

    visible: opened
}
