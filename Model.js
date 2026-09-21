function pluginId() {
    return "dkfiander.disparchy"
}

function cliList() {
    return [
        { id: "claude", label: "Claude", defaultModel: "sonnet" },
        { id: "codex", label: "Codex", defaultModel: "" },
        { id: "grok", label: "Grok", defaultModel: "" },
        { id: "gemini", label: "Gemini", defaultModel: "" },
        { id: "cursor", label: "Cursor", defaultModel: "" }
    ]
}

function settingKeyFor(cli) {
    var map = {
        claude: "modelClaude",
        codex: "modelCodex",
        grok: "modelGrok",
        gemini: "modelGemini",
        cursor: "modelCursor"
    }
    return map[cli] || ""
}

function stateDir(home, xdgState) {
    var base = String(xdgState || "").replace(/\/$/, "")
    if (!base)
        base = String(home || "").replace(/\/$/, "") + "/.local/state"
    return base + "/omarchy/" + pluginId()
}

function pluginDirFromUrl(url) {
    var u = String(url || "")
    if (u.indexOf("file://") === 0)
        u = u.replace(/^file:\/\/(localhost)?/, "")
    try { u = decodeURIComponent(u) } catch (e) {}
    var cut = u.lastIndexOf("/")
    return cut >= 0 ? u.substring(0, cut) : u
}

function defaultSettings() {
    return {
        timeoutSec: 90,
        historyMaxRuns: 50,
        modelClaude: "sonnet",
        modelCodex: "",
        modelGrok: "",
        modelGemini: "",
        modelCursor: ""
    }
}

function mergeSettings(raw, defaults) {
    var out = defaults || defaultSettings()
    var next = {
        timeoutSec: Number(out.timeoutSec),
        historyMaxRuns: Number(out.historyMaxRuns),
        modelClaude: String(out.modelClaude || "sonnet"),
        modelCodex: String(out.modelCodex || ""),
        modelGrok: String(out.modelGrok || ""),
        modelGemini: String(out.modelGemini || ""),
        modelCursor: String(out.modelCursor || "")
    }
    if (!raw || typeof raw !== "object") return clampSettings(next)
    if (raw.timeoutSec !== undefined && raw.timeoutSec !== null && raw.timeoutSec !== "")
        next.timeoutSec = Number(raw.timeoutSec)
    if (raw.historyMaxRuns !== undefined && raw.historyMaxRuns !== null && raw.historyMaxRuns !== "")
        next.historyMaxRuns = Number(raw.historyMaxRuns)
    if (raw.modelClaude !== undefined && raw.modelClaude !== null)
        next.modelClaude = String(raw.modelClaude)
    if (raw.modelCodex !== undefined && raw.modelCodex !== null)
        next.modelCodex = String(raw.modelCodex)
    if (raw.modelGrok !== undefined && raw.modelGrok !== null)
        next.modelGrok = String(raw.modelGrok)
    if (raw.modelGemini !== undefined && raw.modelGemini !== null)
        next.modelGemini = String(raw.modelGemini)
    if (raw.modelCursor !== undefined && raw.modelCursor !== null)
        next.modelCursor = String(raw.modelCursor)
    return clampSettings(next)
}

function clampSettings(s) {
    var timeout = Number(s.timeoutSec)
    if (!isFinite(timeout)) timeout = 90
    timeout = Math.max(15, Math.min(300, Math.round(timeout)))
    var cap = Number(s.historyMaxRuns)
    if (!isFinite(cap)) cap = 50
    cap = Math.max(10, Math.min(200, Math.round(cap)))
    return {
        timeoutSec: timeout,
        historyMaxRuns: cap,
        modelClaude: String(s.modelClaude || "sonnet"),
        modelCodex: String(s.modelCodex || ""),
        modelGrok: String(s.modelGrok || ""),
        modelGemini: String(s.modelGemini || ""),
        modelCursor: String(s.modelCursor || "")
    }
}

function settingsFromShell(raw, id) {
    var defaults = defaultSettings()
    try {
        var cfg = JSON.parse(String(raw || "{}"))
        var layout = cfg && cfg.bar && cfg.bar.layout ? cfg.bar.layout : {}
        var sections = ["left", "center", "right"]
        for (var s = 0; s < sections.length; s++) {
            var arr = layout[sections[s]] || []
            for (var i = 0; i < arr.length; i++) {
                if (arr[i] && arr[i].id === id)
                    return mergeSettings(arr[i], defaults)
            }
        }
        var plugins = cfg && cfg.plugins ? cfg.plugins : []
        for (var j = 0; j < plugins.length; j++) {
            if (plugins[j] && plugins[j].id === id)
                return mergeSettings(plugins[j], defaults)
        }
    } catch (e) {
        return clampSettings(defaults)
    }
    return clampSettings(defaults)
}

function defaultModel(cli, settings) {
    var key = settingKeyFor(cli)
    var fallback = ""
    var list = cliList()
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === cli) fallback = list[i].defaultModel
    }
    if (!settings || !key) return fallback
    var value = settings[key]
    if (value === undefined || value === null) return fallback
    return String(value)
}

function emptySelection() {
    return { clis: [], models: {} }
}

function parseSelection(raw) {
    try {
        var parsed = JSON.parse(String(raw || "{}"))
        var clis = []
        var models = {}
        var allowed = {}
        var list = cliList()
        for (var i = 0; i < list.length; i++) allowed[list[i].id] = true
        var src = parsed && Array.isArray(parsed.clis) ? parsed.clis : []
        for (var j = 0; j < src.length; j++) {
            var id = String(src[j] || "")
            if (allowed[id] && clis.indexOf(id) === -1) clis.push(id)
        }
        var srcModels = parsed && parsed.models && typeof parsed.models === "object" ? parsed.models : {}
        for (var k in srcModels) {
            if (allowed[k]) models[k] = String(srcModels[k] || "")
        }
        return { clis: clis, models: models }
    } catch (e) {
        return emptySelection()
    }
}

function serializeSelection(selection) {
    var sel = selection || emptySelection()
    return JSON.stringify({
        clis: Array.isArray(sel.clis) ? sel.clis : [],
        models: sel.models && typeof sel.models === "object" ? sel.models : {}
    }, null, 2) + "\n"
}

function parseDiscover(raw) {
    var found = {}
    var lines = String(raw || "").split(/\r?\n/)
    var allowed = {}
    var list = cliList()
    for (var i = 0; i < list.length; i++) allowed[list[i].id] = true
    for (var j = 0; j < lines.length; j++) {
        var id = String(lines[j] || "").trim()
        if (allowed[id]) found[id] = true
    }
    var out = []
    for (var k = 0; k < list.length; k++) {
        if (found[list[k].id]) out.push(list[k])
    }
    return out
}

function parseHistory(raw) {
    try {
        var parsed = JSON.parse(String(raw || "[]"))
        if (!Array.isArray(parsed)) return []
        var out = []
        for (var i = 0; i < parsed.length; i++) {
            var run = normalizeRun(parsed[i])
            if (run) out.push(run)
        }
        return out
    } catch (e) {
        return []
    }
}

function normalizeRun(value) {
    if (!value || typeof value !== "object") return null
    var id = String(value.id || "")
    if (!id) return null
    var targets = []
    var src = Array.isArray(value.targets) ? value.targets : []
    for (var i = 0; i < src.length; i++) {
        var t = src[i] || {}
        var cli = String(t.cli || "")
        if (!cli) continue
        var status = String(t.status || "pending")
        if (["pending", "done", "timeout", "failed"].indexOf(status) === -1)
            status = "failed"
        targets.push({
            cli: cli,
            model: String(t.model || ""),
            status: status,
            elapsedMs: Math.max(0, Number(t.elapsedMs) || 0),
            answer: String(t.answer || ""),
            error: String(t.error || "")
        })
    }
    return {
        id: id,
        startedAt: String(value.startedAt || ""),
        prompt: String(value.prompt || ""),
        targets: targets
    }
}

function settleStale(runs) {
    var next = []
    for (var i = 0; i < runs.length; i++) {
        var run = runs[i]
        var targets = []
        for (var j = 0; j < run.targets.length; j++) {
            var t = run.targets[j]
            if (t.status === "pending") {
                targets.push({
                    cli: t.cli,
                    model: t.model,
                    status: "failed",
                    elapsedMs: t.elapsedMs,
                    answer: t.answer,
                    error: t.error || "interrupted"
                })
            } else {
                targets.push(t)
            }
        }
        next.push({
            id: run.id,
            startedAt: run.startedAt,
            prompt: run.prompt,
            targets: targets
        })
    }
    return next
}

function capHistory(runs, maxRuns, maxBytes) {
    var cap = Number(maxRuns)
    if (!isFinite(cap) || cap < 1) cap = 50
    var bytes = Number(maxBytes)
    if (!isFinite(bytes) || bytes < 1024) bytes = 2 * 1024 * 1024
    var next = Array.isArray(runs) ? runs.slice() : []
    while (next.length > cap) next.pop()
    while (next.length > 0 && JSON.stringify(next).length > bytes) next.pop()
    return next
}

function upsertRun(runs, run, maxRuns) {
    var next = Array.isArray(runs) ? runs.slice() : []
    var found = -1
    for (var i = 0; i < next.length; i++) {
        if (next[i].id === run.id) { found = i; break }
    }
    if (found >= 0) next[found] = run
    else next.unshift(run)
    return capHistory(next, maxRuns, 2 * 1024 * 1024)
}

function updateTarget(run, cli, patch) {
    if (!run) return run
    var targets = []
    for (var i = 0; i < run.targets.length; i++) {
        var t = run.targets[i]
        if (t.cli !== cli) {
            targets.push(t)
            continue
        }
        targets.push({
            cli: t.cli,
            model: patch.model !== undefined ? patch.model : t.model,
            status: patch.status !== undefined ? patch.status : t.status,
            elapsedMs: patch.elapsedMs !== undefined ? patch.elapsedMs : t.elapsedMs,
            answer: patch.answer !== undefined ? patch.answer : t.answer,
            error: patch.error !== undefined ? patch.error : t.error
        })
    }
    return {
        id: run.id,
        startedAt: run.startedAt,
        prompt: run.prompt,
        targets: targets
    }
}

function inFlightCount(run) {
    if (!run || !run.targets) return 0
    var n = 0
    for (var i = 0; i < run.targets.length; i++) {
        if (run.targets[i].status === "pending") n++
    }
    return n
}

function settleSummary(run) {
    if (!run || !run.targets || run.targets.length === 0)
        return "0/0 done"
    var ok = 0
    var failed = 0
    var total = run.targets.length
    for (var i = 0; i < total; i++) {
        var s = run.targets[i].status
        if (s === "done") ok++
        else failed++
    }
    if (failed === 0) return ok + "/" + total + " done"
    return ok + " ok, " + failed + " failed"
}

function previewPrompt(text, maxLen) {
    var s = String(text || "").replace(/\s+/g, " ").trim()
    var n = Number(maxLen)
    if (!isFinite(n) || n < 8) n = 72
    if (s.length <= n) return s
    return s.substring(0, n - 1) + "…"
}

function newRunId() {
    return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
}

function isoNow() {
    return new Date().toISOString()
}

function promptTooLarge(text) {
    var bytes = unescape(encodeURIComponent(String(text || ""))).length
    return bytes > 32 * 1024
}

function serializeHistory(runs) {
    return JSON.stringify(Array.isArray(runs) ? runs : [], null, 2) + "\n"
}

function serializeStatus(inFlight) {
    return JSON.stringify({ inFlight: Math.max(0, Number(inFlight) || 0) }) + "\n"
}

function parseStatus(raw) {
    try {
        var parsed = JSON.parse(String(raw || "{}"))
        var n = Number(parsed && parsed.inFlight)
        return isFinite(n) && n > 0 ? Math.floor(n) : 0
    } catch (e) {
        return 0
    }
}

function modelForCli(cli, selection, settings) {
    var models = selection && selection.models ? selection.models : {}
    if (models[cli] !== undefined && String(models[cli]).trim() !== "")
        return String(models[cli]).trim()
    return defaultModel(cli, settings)
}

function isChecked(selection, cli) {
    return !!(selection && Array.isArray(selection.clis) && selection.clis.indexOf(cli) >= 0)
}

function toggleCli(selection, cli, on) {
    var sel = selection || emptySelection()
    var clis = Array.isArray(sel.clis) ? sel.clis.slice() : []
    var idx = clis.indexOf(cli)
    if (on) {
        if (idx < 0) clis.push(cli)
    } else if (idx >= 0) {
        clis.splice(idx, 1)
    }
    return { clis: clis, models: sel.models && typeof sel.models === "object" ? sel.models : {} }
}

function setModel(selection, cli, model) {
    var sel = selection || emptySelection()
    var models = {}
    var src = sel.models && typeof sel.models === "object" ? sel.models : {}
    for (var k in src) models[k] = src[k]
    models[cli] = String(model || "")
    return { clis: Array.isArray(sel.clis) ? sel.clis.slice() : [], models: models }
}

function selectedAvailable(selection, available) {
    var out = []
    var clis = selection && Array.isArray(selection.clis) ? selection.clis : []
    for (var i = 0; i < clis.length; i++) {
        for (var j = 0; j < available.length; j++) {
            if (available[j].id === clis[i]) { out.push(clis[i]); break }
        }
    }
    return out
}

function statusLabel(status) {
    if (status === "pending") return "pending"
    if (status === "done") return "done"
    if (status === "timeout") return "timeout"
    return "failed"
}

function formatElapsed(ms) {
    var n = Number(ms)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1000) return Math.round(n) + "ms"
    return (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "s"
}
