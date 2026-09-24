import QtQuick
import qs.Commons

// Outer card. content*Inset matches the upstream contract: border plus padding.
Item {
    id: surface

    property var borderSpec: null
    property int padding: 0
    property real radius: 0
    property color color: "transparent"

    readonly property real contentLeftInset: Border.left(borderSpec) + padding
    readonly property real contentRightInset: Border.right(borderSpec) + padding
    readonly property real contentTopInset: Border.top(borderSpec) + padding
    readonly property real contentBottomInset: Border.bottom(borderSpec) + padding

    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        color: surface.color
        border.width: Border.left(surface.borderSpec)
        border.color: surface.borderSpec && surface.borderSpec.color
            ? surface.borderSpec.color : "transparent"
    }
}
