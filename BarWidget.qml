import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "dkfiander.disparchy"

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property int inFlight: panelLoader.item ? Number(panelLoader.item.inFlight || 0) : 0
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
    readonly property real openPanelIndicatorWidth: button.implicitWidth
    readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() {
        if (panelLoader.item) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function togglePanel() {
        if (panelLoader.item) panelLoader.item.toggle()
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    IpcHandler {
        target: "dkfiander.disparchy"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰘚"
        tooltipText: root.inFlight > 0
            ? ("Disparchy · " + root.inFlight + " in flight")
            : "Disparchy"
        onPressed: root.togglePanel()
    }

    Rectangle {
        visible: root.inFlight > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Style.space(1)
        anchors.topMargin: Style.space(1)
        width: badge.implicitWidth + Style.space(6)
        height: badge.implicitHeight + Style.space(2)
        radius: Math.max(2, Style.cornerRadius)
        color: Color.accent

        Text {
            id: badge
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(root.inFlight)
            color: Color.background
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
}
