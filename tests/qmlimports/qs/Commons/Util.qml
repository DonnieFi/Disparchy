pragma Singleton
import QtQuick

QtObject {
    function alpha(color, opacity) {
        return Qt.alpha(color, opacity)
    }
}
