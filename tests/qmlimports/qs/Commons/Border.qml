pragma Singleton
import QtQuick

QtObject {
    function _width(spec) {
        var w = spec && spec.width !== undefined ? Number(spec.width) : 0
        return isFinite(w) ? w : 0
    }

    function surfaceSpec(group, role, color, width) {
        var w = Number(width)
        if (!isFinite(w))
            w = 0
        return { width: w, left: w, right: w, top: w, bottom: w, color: color }
    }

    function controlSpec(state, ink, accent) {
        return { width: 1, left: 1, right: 1, top: 1, bottom: 1 }
    }

    function left(spec) { return _width(spec) }
    function right(spec) { return _width(spec) }
    function top(spec) { return _width(spec) }
    function bottom(spec) { return _width(spec) }
}
