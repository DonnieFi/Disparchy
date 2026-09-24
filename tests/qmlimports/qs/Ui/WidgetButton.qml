import QtQuick

Item {
    id: button

    property var bar: null
    property bool labelVisible: false
    property bool hasVisualContent: false
    property real fixedWidth: 0
    property string tooltipText: ""

    signal pressed()

    implicitWidth: fixedWidth > 0 ? fixedWidth : 32
    implicitHeight: 32
}
