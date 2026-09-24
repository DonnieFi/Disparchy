import QtQuick
import QtQuick.Shapes

// One prompt in a speech frame, three replies cut out of its face.
Item {
    id: root
    property real iconSize: width > 0 ? width : 16
    property color color: "#e6e5dd"
    property bool busy: false

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    Shape {
        id: mark
        width: 64
        height: 64
        anchors.centerIn: parent
        antialiasing: true
        // Qt 6.6+ Shape.CurveRenderer. Qt 6.4 rejects a static binding because
        // the property does not exist yet, so set it when the type has it.
        Component.onCompleted: {
            if (mark["preferredRendererType"] !== undefined && Shape["CurveRenderer"] !== undefined)
                mark["preferredRendererType"] = Shape["CurveRenderer"]
        }
        transform: Scale {
            origin.x: 32
            origin.y: 32
            xScale: root.iconSize / 64
            yScale: root.iconSize / 64
        }

        ShapePath {
            fillColor: root.color
            strokeWidth: 0
            fillRule: ShapePath.OddEvenFill
            PathSvg {
                path: "M7 9H57V43H42L32 55L22 43H7V9ZM16 24H23V35H16V24ZM28 17H35V35H28V17ZM40 21H47V35H40V21Z"
            }
        }
    }

    SequentialAnimation on opacity {
        running: root.busy
        loops: Animation.Infinite
        NumberAnimation { to: 0.62; duration: 850; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 850; easing.type: Easing.InOutSine }
    }
}
