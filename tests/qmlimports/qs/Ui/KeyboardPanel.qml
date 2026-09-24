import QtQuick
import qs.Commons

// Width contract from upstream KeyboardPanel: contentWidth is the outer card,
// availableCardWidth is the screen budget, and the content holder is inset by
// the popup border plus padding.
Item {
    id: root

    property var anchorItem: null
    property var owner: null
    property var bar: null
    property bool open: false
    property int margin: 8
    property int padding: Style.space(6)
    property int gap: 8
    property int contentWidth: Style.space(280)
    property int contentHeight: Style.space(200)
    property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    property Item focusTarget: null

    readonly property real screenW: 1920
    readonly property real screenH: 1080
    readonly property real availableCardWidth: Math.max(120, screenW - margin * 2)
    readonly property real availableCardHeight: Math.max(120, screenH - 48)
    readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

    function fittedContentWidth(width, cap) {
        var desired = Math.max(1, Number(width) || 1)
        var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
        if (cap !== undefined && Number(cap) > 0)
            maxWidth = Math.min(maxWidth, Number(cap))
        return Math.round(Math.min(desired, maxWidth))
    }

    function fittedContentHeight(implicitHeight, cap) {
        var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
        var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
        if (cap !== undefined && Number(cap) > 0)
            maxHeight = Math.min(maxHeight, Number(cap))
        return Math.round(Math.min(desired, maxHeight))
    }

    width: contentWidth
    height: contentHeight
    visible: open

    default property alias contentItem: contentHolder.children

    BorderSurface {
        id: card
        anchors.fill: parent
        color: Color.popups.background
        borderSpec: root.borderSpec
        padding: root.padding
        radius: Style.cornerRadius

        Item {
            id: contentHolder
            anchors.fill: parent
            anchors.leftMargin: card.contentLeftInset
            anchors.rightMargin: card.contentRightInset
            anchors.topMargin: card.contentTopInset
            anchors.bottomMargin: card.contentBottomInset
        }
    }
}
