import QtQuick

// Stand-in for Quickshell's Panel so the real plugin document can compile
// and open under qmltestrunner. show() is what Panel.qml's open() calls.
Item {
    id: panelRoot

    property string moduleName: ""
    property string ipcTarget: ""
    property bool manageIpc: false
    property bool opened: false
    property bool popoutSwitchClosing: false
    property var bar: null
    property var settings: null
    property QtObject controller: QtObject {
        function show() {
            panelRoot.opened = true
        }

        function hide() {
            panelRoot.opened = false
        }
    }

    function close() {
        opened = false
    }

    function toggle() {
        if (opened)
            close()
        else
            controller.show()
    }

    function closeForPopoutSwitch() {
        popoutSwitchClosing = true
        close()
    }
}
