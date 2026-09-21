import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
    id: root
    moduleName: "dkfiander.disparchy"

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateRoot: Model.stateDir(home, Quickshell.env("XDG_STATE_HOME"))
    property int inFlight: 0

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function toggleOverlay() {
        if (root.bar && typeof root.bar.run === "function")
            root.bar.run("omarchy-shell shell toggle dkfiander.disparchy '{}'")
        else
            Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "dkfiander.disparchy", "{}"])
    }

    FileView {
        path: root.stateRoot + "/status.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.inFlight = Model.parseStatus(text())
        onLoadFailed: root.inFlight = 0
        onFileChanged: reload()
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰘚"
        tooltipText: root.inFlight > 0
            ? ("Disparchy · " + root.inFlight + " in flight")
            : "Disparchy"
        onPressed: root.toggleOverlay()
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
