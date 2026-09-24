function pluginId() {
    return "dkfiander.disparchy"
}

function cliList() {
    return [
        { id: "claude", label: "Claude", defaultModel: "sonnet", transport: "cli" },
        { id: "codex", label: "Codex", defaultModel: "", transport: "cli" },
        { id: "grok", label: "Grok", defaultModel: "", transport: "cli" },
        { id: "antigravity", label: "Antigravity", defaultModel: "", transport: "cli" },
        { id: "cursor", label: "Cursor", defaultModel: "", transport: "cli" },
        { id: "openclaw", label: "OpenClaw", defaultModel: "", transport: "cli", auth: true, defaultEndpoint: "http://127.0.0.1:18789", presets: ["http://127.0.0.1:18789"] },
        { id: "hermes", label: "Hermes", defaultModel: "", transport: "cli", auth: true, defaultEndpoint: "http://127.0.0.1:8642", presets: ["http://127.0.0.1:8642"] },
        { id: "ollama", label: "Ollama", defaultModel: "", transport: "http", defaultEndpoint: "http://127.0.0.1:11434", presets: ["http://127.0.0.1:11434"] },
        { id: "lmstudio", label: "LM Studio", defaultModel: "", transport: "http", defaultEndpoint: "http://127.0.0.1:1234", presets: ["http://127.0.0.1:1234"] }
    ]
}

function builtinShown() {
    return ["claude", "codex", "grok", "antigravity", "cursor"]
}

function settingKeyFor(cli) {
    var map = {
        claude: "modelClaude",
        codex: "modelCodex",
        grok: "modelGrok",
        antigravity: "modelAntigravity",
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

function opt(value, label) {
    return { value: String(value), label: String(label !== undefined ? label : value) }
}

function modelsFor(cli, live) {
    var def = opt("", cli === "hermes" ? "Hermes default" : "CLI default")
    if (live && live.length) {
        var out = [def]
        for (var i = 0; i < live.length; i++) {
            var row = live[i] || {}
            var value = String(row.value || "")
            if (!value) continue
            out.push(opt(value, row.label || value))
        }
        if (out.length > 1) return out
    }
    if (cli === "codex" || cli === "ollama" || cli === "lmstudio" || cli === "openclaw")
        return [def]
    if (cli === "claude")
        return [def, opt("sonnet", "sonnet"), opt("opus", "opus"), opt("haiku", "haiku"), opt("fable", "fable")]
    if (cli === "grok")
        return [def, opt("grok-4.7", "grok-4.7"), opt("grok-4.6", "grok-4.6")]
    if (cli === "antigravity")
        return [
            def,
            opt("gemini-3.8-flash-high", "gemini 3.8 flash"),
            opt("gemini-3.1-pro-high", "gemini 3.1 pro")
        ]
    if (cli === "cursor")
        return [def, opt("auto", "auto"), opt("composer-2.5", "composer-2.5")]
    return [def]
}

function byteLength(text) {
    try {
        return unescape(encodeURIComponent(String(text || ""))).length
    } catch (e) {
        return String(text || "").length
    }
}

function formatBytes(n) {
    var v = Number(n)
    if (!isFinite(v) || v < 0) v = 0
    if (v < 1024) return Math.round(v) + " B"
    if (v < 1024 * 1024) return (v / 1024).toFixed(v >= 10240 ? 0 : 1) + " KiB"
    return (v / (1024 * 1024)).toFixed(1) + " MiB"
}

function estimateTokens(text) {
    var n = String(text || "").length
    if (n <= 0) return 0
    return Math.ceil(n / 4)
}

// Qt's Markdown renderer can fetch images. Keep formatting and links, but
// turn image syntax into ordinary links and neutralize raw HTML image tags.
function markdownForDisplay(text) {
    return String(text || "")
        .replace(/!\[/g, "[")
        .replace(/<\s*img\b/gi, "&lt;img")
}

function externalLinkForDisplay(url) {
    var value = String(url || "").trim()
    return /^https?:\/\//i.test(value) ? value : ""
}

function runTokens(run) {
    var prompt = estimateTokens(run && run.prompt)
    var answers = 0
    var targets = run && run.targets ? run.targets : []
    for (var i = 0; i < targets.length; i++)
        answers += estimateTokens(targets[i] && targets[i].answer)
    return { prompt: prompt, answers: answers, total: prompt + answers }
}

function historyTokens(history) {
    var prompt = 0
    var answers = 0
    var list = Array.isArray(history) ? history : []
    for (var i = 0; i < list.length; i++) {
        var row = runTokens(list[i])
        prompt += row.prompt
        answers += row.answers
    }
    return { prompt: prompt, answers: answers, total: prompt + answers }
}

function tokenFooter(run, history) {
    if (!run) return ""
    var here = runTokens(run)
    var saved = historyTokens(history)
    return "in " + here.prompt
        + "  ·  out " + here.answers
        + "  ·  ≈ " + here.total + " this run"
        + "  ·  ≈ " + saved.total + " saved"
}

function nerdLine(target) {
    if (!target) return ""
    var parts = []
    parts.push(statusLabel(target.status))
    if (target.elapsedMs > 0) parts.push(formatElapsed(target.elapsedMs))
    if (target.stdoutBytes > 0) parts.push(formatBytes(target.stdoutBytes) + " out")
    if (target.stderrBytes > 0) parts.push(formatBytes(target.stderrBytes) + " err")
    if (target.exitCode !== undefined && target.exitCode !== null && target.exitCode !== "")
        parts.push("exit " + target.exitCode)
    return parts.join(" · ")
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

function isKnownCli(cli) {
    var list = cliList()
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === cli) return true
    }
    return false
}

function normalizeModelList(value) {
    var out = []
    var src
    if (Array.isArray(value)) src = value
    else if (value === undefined || value === null) return out
    else src = [value]
    for (var i = 0; i < src.length; i++) {
        if (src[i] === undefined || src[i] === null) continue
        var model = String(src[i])
        if (out.indexOf(model) === -1) out.push(model)
    }
    return out
}

function copyModels(src) {
    var models = {}
    if (!src || typeof src !== "object") return models
    for (var k in src) {
        if (!Object.prototype.hasOwnProperty.call(src, k)) continue
        if (!isKnownCli(k)) continue
        var list = normalizeModelList(src[k])
        if (list.length > 0) models[k] = list
    }
    return models
}

function emptySelection() {
    return { models: {} }
}

function providerOf(cli) {
    var list = cliList()
    for (var i = 0; i < list.length; i++)
        if (list[i].id === cli) return list[i]
    return null
}

function needsEndpoint(cli) {
    var row = providerOf(cli)
    return !!(row && (row.transport === "http" || row.auth))
}

function setupGroup(wantEndpoint) {
    var list = cliList()
    var out = []
    var want = !!wantEndpoint
    for (var i = 0; i < list.length; i++) {
        if (needsEndpoint(list[i].id) === want) out.push(list[i])
    }
    return out
}

function escapeTarget(confirmOpen, menuOpen) {
    if (confirmOpen) return "confirm"
    if (menuOpen) return "menu"
    return "panel"
}

function widthCount(armedCount, runProviderCount) {
    var armed = parseInt(armedCount, 10)
    if (!isFinite(armed) || armed < 0)
        armed = 0
    var run = parseInt(runProviderCount, 10)
    if (!isFinite(run) || run < 0)
        run = 0
    return Math.max(armed, run)
}

function panelWidth(providerCount, screenWidth, minWidth, colWidth, gap, insets) {
    var count = parseInt(providerCount, 10)
    if (!isFinite(count) || count < 1)
        count = 1
    var n = Math.min(count, 3)
    var min = Number(minWidth)
    var col = Number(colWidth)
    var spacing = Number(gap)
    var pad = Number(insets)
    if (!isFinite(min)) min = 0
    if (!isFinite(col)) col = 0
    if (!isFinite(spacing)) spacing = 0
    if (!isFinite(pad)) pad = 0
    var needed = n * col + (n - 1) * spacing + pad
    var width = Math.max(min, needed)
    var screen = Number(screenWidth)
    if (!isFinite(screen) || screen <= 0)
        return width
    return Math.min(screen, width)
}

function resultColumns(panelWidth, providerCount, minWidth, gap) {
    var count = parseInt(providerCount, 10)
    if (!isFinite(count) || count < 1)
        count = 1
    var min = Number(minWidth)
    var spacing = Number(gap)
    if (!isFinite(min) || min <= 0 || !isFinite(spacing) || spacing <= 0)
        return 1
    var width = Number(panelWidth)
    if (!isFinite(width))
        width = 0
    var cols = 1
    for (var n = 2; n <= 3; n++) {
        if (n * min + (n - 1) * spacing <= width)
            cols = n
    }
    if (cols > count)
        cols = count
    return cols
}

function needsSecret(cli) {
    var row = providerOf(cli)
    return !!(row && row.auth)
}

function copySecrets(src) {
    var out = {}
    if (!src || typeof src !== "object" || Array.isArray(src)) return out
    for (var k in src) {
        if (!Object.prototype.hasOwnProperty.call(src, k)) continue
        if (!needsSecret(k)) continue
        var text = String(src[k] || "").replace(/\s+/g, "")
        if (!text || text.length > 4096) continue
        out[k] = text
    }
    return out
}

function parseAuth(raw) {
    try {
        return copySecrets(JSON.parse(String(raw || "{}")))
    } catch (e) {
        return {}
    }
}

function serializeAuth(auth) {
    return JSON.stringify(copySecrets(auth), null, 2) + "\n"
}

function secretFor(auth, cli) {
    if (!needsSecret(cli)) return ""
    return auth && auth[cli] ? String(auth[cli]) : ""
}

function setSecret(auth, cli, key) {
    var out = copySecrets(auth)
    var id = String(cli || "")
    var text = String(key || "").replace(/\s+/g, "")
    if (needsSecret(id) && text && text.length <= 4096) out[id] = text
    else delete out[id]
    return out
}

function cleanEnabled(src) {
    var out = []
    var list = Array.isArray(src) ? src : []
    for (var i = 0; i < list.length; i++) {
        var id = String(list[i] || "")
        if (!isKnownCli(id) || out.indexOf(id) >= 0) continue
        out.push(id)
    }
    return out
}

function copyEndpoints(src) {
    var out = {}
    if (!src || typeof src !== "object") return out
    for (var k in src) {
        if (!Object.prototype.hasOwnProperty.call(src, k)) continue
        if (!needsEndpoint(k)) continue
        var url = String(src[k] || "").trim()
        if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) continue
        out[k] = url
    }
    return out
}

function withExtras(selection, models) {
    var out = { models: models }
    if (selection && Array.isArray(selection.enabled))
        out.enabled = cleanEnabled(selection.enabled)
    if (selection && selection.endpoints)
        out.endpoints = copyEndpoints(selection.endpoints)
    if (selection && selection.autoPaste === true)
        out.autoPaste = true
    return out
}

function autoPasteOn(selection) {
    return !!(selection && selection.autoPaste === true)
}

function setAutoPaste(selection, on) {
    var out = withExtras(selection, copyModels(selection && selection.models))
    if (on) out.autoPaste = true
    else delete out.autoPaste
    return out
}

function isEnabled(selection, id) {
    if (!isKnownCli(id)) return false
    if (!selection || !Array.isArray(selection.enabled))
        return builtinShown().indexOf(id) >= 0
    return selection.enabled.indexOf(id) >= 0
}

function signInCommand(cli) {
    if (cli === "claude") return ["claude", "auth", "login"]
    if (cli === "codex") return ["codex", "login"]
    if (cli === "grok") return ["grok"]
    if (cli === "antigravity") return ["agy"]
    if (cli === "cursor") return ["cursor-agent", "login"]
    if (cli === "openclaw") return ["openclaw"]
    if (cli === "hermes") return ["hermes"]
    return []
}

function endpointFor(selection, cli) {
    if (!needsEndpoint(cli)) return ""
    var custom = selection && selection.endpoints ? selection.endpoints[cli] : ""
    if (custom) return String(custom)
    var row = providerOf(cli)
    return row && row.defaultEndpoint ? row.defaultEndpoint : ""
}

function toggleEnabled(selection, cli, on) {
    var id = String(cli || "")
    var models = copyModels(selection && selection.models)
    var list = selection && Array.isArray(selection.enabled)
        ? cleanEnabled(selection.enabled)
        : builtinShown().slice()
    var idx = list.indexOf(id)
    var want = on === undefined ? idx < 0 : !!on
    if (want && idx < 0 && isKnownCli(id)) list.push(id)
    if (!want && idx >= 0) list.splice(idx, 1)
    var out = withExtras(selection, models)
    out.enabled = list
    return out
}

function setEndpoint(selection, cli, url) {
    var id = String(cli || "")
    var models = copyModels(selection && selection.models)
    var out = withExtras(selection, models)
    var endpoints = copyEndpoints(out.endpoints)
    var text = String(url || "").trim()
    if (needsEndpoint(id) && (text.indexOf("http://") === 0 || text.indexOf("https://") === 0))
        endpoints[id] = text
    else
        delete endpoints[id]
    if (Object.keys(endpoints).length > 0) out.endpoints = endpoints
    else delete out.endpoints
    return out
}

function parseSelection(raw) {
    try {
        var parsed = JSON.parse(String(raw || "{}"))
        var srcModels = parsed && parsed.models && typeof parsed.models === "object" && !Array.isArray(parsed.models)
            ? parsed.models
            : {}
        var models = copyModels(srcModels)
        var srcClis = parsed && Array.isArray(parsed.clis) ? parsed.clis : null
        if (srcClis && srcClis.length > 0) {
            var keep = {}
            for (var j = 0; j < srcClis.length; j++) {
                var id = String(srcClis[j] || "")
                if (!isKnownCli(id)) continue
                keep[id] = true
                if (!models[id]) models[id] = [""]
            }
            var filtered = {}
            for (var m in models) {
                if (keep[m]) filtered[m] = models[m]
            }
            models = filtered
        }
        var out = { models: models }
        if (parsed && Array.isArray(parsed.enabled))
            out.enabled = cleanEnabled(parsed.enabled)
        if (parsed && parsed.endpoints)
            out.endpoints = copyEndpoints(parsed.endpoints)
        if (parsed && parsed.autoPaste === true)
            out.autoPaste = true
        return out
    } catch (e) {
        return emptySelection()
    }
}

function serializeSelection(selection) {
    var body = { models: copyModels(selection && selection.models) }
    if (selection && Array.isArray(selection.enabled))
        body.enabled = cleanEnabled(selection.enabled)
    if (selection && selection.endpoints) {
        var endpoints = copyEndpoints(selection.endpoints)
        if (Object.keys(endpoints).length > 0) body.endpoints = endpoints
    }
    if (selection && selection.autoPaste === true)
        body.autoPaste = true
    return JSON.stringify(body, null, 2) + "\n"
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
        var exitCode = t.exitCode
        if (exitCode === undefined || exitCode === null || exitCode === "") exitCode = ""
        else exitCode = Number(exitCode)
        targets.push({
            cli: cli,
            model: String(t.model || ""),
            status: status,
            elapsedMs: Math.max(0, Number(t.elapsedMs) || 0),
            answer: String(t.answer || ""),
            error: String(t.error || ""),
            exitCode: exitCode,
            stdoutBytes: Math.max(0, Number(t.stdoutBytes) || 0),
            stderrBytes: Math.max(0, Number(t.stderrBytes) || 0)
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
                    error: t.error || "interrupted",
                    exitCode: t.exitCode,
                    stdoutBytes: t.stdoutBytes,
                    stderrBytes: t.stderrBytes
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

function updateTarget(run, cli, model, patch) {
    if (!run || !run.targets) return run
    if (!patch || typeof patch !== "object") return run
    var wantModel = String(model || "")
    var targets = []
    var hit = false
    for (var i = 0; i < run.targets.length; i++) {
        var t = run.targets[i]
        if (t.cli !== cli || String(t.model || "") !== wantModel) {
            targets.push(t)
            continue
        }
        hit = true
        targets.push({
            cli: t.cli,
            model: t.model,
            status: patch.status !== undefined ? patch.status : t.status,
            elapsedMs: patch.elapsedMs !== undefined ? patch.elapsedMs : t.elapsedMs,
            answer: patch.answer !== undefined ? patch.answer : t.answer,
            error: patch.error !== undefined ? patch.error : t.error,
            exitCode: patch.exitCode !== undefined ? patch.exitCode : t.exitCode,
            stdoutBytes: patch.stdoutBytes !== undefined ? patch.stdoutBytes : t.stdoutBytes,
            stderrBytes: patch.stderrBytes !== undefined ? patch.stderrBytes : t.stderrBytes
        })
    }
    if (!hit) return run
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

function modelsOf(selection, cli) {
    var models = selection && selection.models && typeof selection.models === "object" ? selection.models : {}
    return normalizeModelList(models[cli])
}

function isArmed(selection, cli) {
    return modelsOf(selection, cli).length > 0
}

function isCliActive(selection, cli) {
    return isArmed(selection, cli)
}

function isChecked(selection, cli) {
    return isArmed(selection, cli)
}

function modelsChecked(selection, cli, model) {
    return modelsOf(selection, cli).indexOf(String(model || "")) >= 0
}

function isModelChecked(selection, cli, model) {
    return modelsChecked(selection, cli, model)
}

function modelForCli(cli, selection, settings) {
    var list = modelsOf(selection, cli)
    if (list.length > 0) return list[0]
    return defaultModel(cli, settings)
}

function toggleModel(selection, cli, model, on) {
    var id = String(cli || "")
    var item = String(model || "")
    var models = copyModels(selection && selection.models)
    if (!isKnownCli(id)) return withExtras(selection, models)
    var list = models[id] ? models[id].slice() : []
    var idx = list.indexOf(item)
    var want
    if (on === true) want = true
    else if (on === false) want = false
    else want = idx < 0
    if (want) {
        if (idx < 0) list.push(item)
    } else if (idx >= 0) {
        list.splice(idx, 1)
    }
    if (list.length === 0) delete models[id]
    else models[id] = list
    return withExtras(selection, models)
}

function toggleCli(selection, cli, on, settings) {
    var armed = isArmed(selection, cli)
    var want = on === undefined ? !armed : !!on
    if (want === armed) return withExtras(selection, copyModels(selection && selection.models))
    if (want) return toggleModel(selection, cli, defaultModel(cli, settings), true)
    var models = copyModels(selection && selection.models)
    delete models[cli]
    return withExtras(selection, models)
}

function setModel(selection, cli, model) {
    var models = copyModels(selection && selection.models)
    var id = String(cli || "")
    if (!isKnownCli(id)) return withExtras(selection, models)
    models[id] = [String(model || "")]
    return withExtras(selection, models)
}

function selectedAvailable(selection, available) {
    var out = []
    var list = Array.isArray(available) ? available : []
    for (var i = 0; i < list.length; i++) {
        var id = list[i] && list[i].id ? list[i].id : ""
        if (id && isArmed(selection, id)) out.push(id)
    }
    return out
}

function targetKey(cli, model) {
    return String(cli) + "\x1f" + String(model || "")
}

function jobKey(cli, model) {
    return targetKey(cli, model)
}

function expandJobs(selection, available) {
    var out = []
    var list = Array.isArray(available) ? available : []
    for (var i = 0; i < list.length; i++) {
        var cli = list[i] && list[i].id ? list[i].id : ""
        if (!cli) continue
        var ms = modelsOf(selection, cli)
        for (var j = 0; j < ms.length; j++) {
            out.push({ cli: cli, model: ms[j], key: targetKey(cli, ms[j]) })
        }
    }
    return out
}

function newRun(prompt, jobs) {
    var src = Array.isArray(jobs) ? jobs : []
    var targets = []
    for (var i = 0; i < src.length; i++) {
        var job = src[i] || {}
        targets.push({
            cli: String(job.cli || ""),
            model: String(job.model || ""),
            status: "pending",
            elapsedMs: 0,
            answer: "",
            error: "",
            exitCode: "",
            stdoutBytes: 0,
            stderrBytes: 0
        })
    }
    return {
        id: newRunId(),
        startedAt: isoNow(),
        prompt: String(prompt || ""),
        targets: targets
    }
}

function runningHas(runningKeys, key) {
    if (!runningKeys) return false
    if (typeof runningKeys.has === "function") return !!runningKeys.has(key)
    return !!runningKeys[key]
}

function claimNext(run, runningKeys) {
    if (!run || !run.targets) return null
    for (var i = 0; i < run.targets.length; i++) {
        var t = run.targets[i]
        if (t.status !== "pending") continue
        var key = targetKey(t.cli, t.model)
        if (!runningHas(runningKeys, key))
            return { cli: t.cli, model: t.model, key: key }
    }
    return null
}

function seedIfEmpty(selection, available, settings) {
    var list = Array.isArray(available) ? available : []
    for (var i = 0; i < list.length; i++) {
        var id = list[i] && list[i].id ? list[i].id : ""
        if (id && isArmed(selection, id)) return withExtras(selection, copyModels(selection && selection.models))
    }
    var models = copyModels(selection && selection.models)
    for (var j = 0; j < list.length; j++) {
        var cli = list[j] && list[j].id ? list[j].id : ""
        if (!cli || !isKnownCli(cli)) continue
        models[cli] = [defaultModel(cli, settings)]
    }
    return withExtras(selection, models)
}

function targetsForCli(run, cli) {
    var out = []
    if (!run || !run.targets) return out
    for (var i = 0; i < run.targets.length; i++) {
        if (run.targets[i].cli === cli) out.push(run.targets[i])
    }
    return out
}

function statusFromExit(code, stderr) {
    if (code === 0) return "done"
    if (code === 124 || String(stderr || "") === "timeout") return "timeout"
    return "failed"
}

function rowMetric(cli, selection, displayRun) {
    var names = modelsOf(selection, cli).join(" · ")
    if (!names) names = "—"
    var status = "idle"
    if (displayRun) {
        var hits = targetsForCli(displayRun, cli)
        if (hits.length > 0) {
            status = hits[0].status
            for (var i = 0; i < hits.length; i++) {
                if (hits[i].status === "pending") {
                    status = "pending"
                    break
                }
                if (hits[i].status === "failed" || hits[i].status === "timeout")
                    status = hits[i].status
            }
        }
    }
    return { names: names, status: status, tone: status }
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
