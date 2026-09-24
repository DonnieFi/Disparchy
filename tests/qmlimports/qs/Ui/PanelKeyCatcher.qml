import QtQuick

FocusScope {
    property bool blocked: false

    signal closeRequested()
    signal tabRequested(int direction)
    signal activateRequested()
}
