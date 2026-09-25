import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "dkfiander.disparchy"
    ipcTarget: "dkfiander.disparchy"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    property string promptText: ""
    property string viewingRunId: ""
    property bool historyOpen: false
    property bool setupOpen: false
    property string pluginVersion: ""
    property string menuCli: ""
    // Assigned only when the panel opens, a run is sent, or a past run is opened.
    property int widthCount: 1
    property var selection: Model.emptySelection()
    property var available: []
    property var providerStatus: []
    property var liveModels: ({})
    readonly property int controlSize: Style.space(20)
    readonly property var shown: {
        var out = []
        var list = Model.cliList()
        var have = {}
        for (var i = 0; i < available.length; i++)
            have[available[i].id] = true
        for (var j = 0; j < list.length; j++) {
            var row = list[j]
            if (!Model.isEnabled(selection, row.id)) continue
            if (row.transport === "http" || have[row.id]) out.push(row)
        }
        return out
    }
    property var history: []
    property var liveRun: null
    property bool historyPrimed: false
    property bool clearConfirmOpen: false
    property string confirmAction: "history"
    property string confirmCli: ""
    property string replacingCli: ""
    property string keyErrorCli: ""
    property bool cancelRequested: false

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateRoot: Model.stateDir(home, Quickshell.env("XDG_STATE_HOME"))
    readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("manifest.json"))
    readonly property string runnerPath: pluginDir + "/bin/disparchy-run"
    readonly property string historyPath: stateRoot + "/history.json"
    readonly property string selectionPath: stateRoot + "/selection.json"
    readonly property string statusPath: stateRoot + "/status.json"
    readonly property string promptPath: stateRoot + "/prompt.txt"

    readonly property color ink: Color.popups.text
    readonly property color dim: Qt.darker(ink, 1.55)
    readonly property color rule: Util.alpha(ink, 0.16)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    // Padding plus the popup border, both sides, so the result area fits n columns.
    readonly property real horizontalInsets: panel.padding * 2
        + Border.left(panel.borderSpec) + Border.right(panel.borderSpec)
    readonly property int hangWidth: Math.round(Model.panelWidth(
        widthCount, panel.availableCardWidth,
        Style.space(680), Style.space(280), Style.space(8), horizontalInsets))
    readonly property int lineHeight: Style.space(28)
    readonly property int actionRadius: Style.space(9)

    readonly property int timeoutSec: {
        var n = parseInt(String(setting("timeoutSec", 90)), 10)
        if (!isFinite(n)) n = 90
        return Math.max(15, Math.min(300, n))
    }
    readonly property int historyMaxRuns: {
        var n = parseInt(String(setting("historyMaxRuns", 50)), 10)
        if (!isFinite(n)) n = 50
        return Math.max(10, Math.min(200, n))
    }

    readonly property var displayRun: viewingRunId ? runById(viewingRunId) : liveRun
    readonly property int inFlight: Model.inFlightCount(liveRun)
    readonly property var sendJobs: Model.expandJobs(selection, shown)
    readonly property bool viewingPast: viewingRunId !== ""
    readonly property bool canClear: !viewingPast && inFlight === 0
        && (promptText.length > 0 || (displayRun && displayRun.targets && displayRun.targets.length > 0))
    readonly property int armedCount: Model.answerCount(selection, shown)
    readonly property string headerHint: {
        if (setupOpen) return "Switch a provider onto the bar. Click sign in to open the CLI."
        if (historyOpen) return "Past runs stay on disk."
        if (viewingPast) return "A past run. Back returns to the prompt."
        return "One prompt. The checked providers answer together."
    }
    readonly property string headerStatus: {
        if (inFlight > 0) return inFlight + " running"
        if (setupOpen) return "Setup"
        if (historyOpen) return history.length + " saved"
        if (armedCount === 0) return "Idle"
        return armedCount + " armed"
    }
    readonly property color headerTint: inFlight > 0 || setupOpen ? Color.accent : ink
    readonly property bool canSend: promptText.trim().length > 0
        && sendJobs.length > 0
        && inFlight === 0
        && !viewingPast
        && !historyOpen
        && !setupOpen
        && !Model.promptTooLarge(promptText)

    function tintFor(cli) {
        if (cli === "claude") return Qt.hsla(0.08, 0.72, 0.62, 1)
        if (cli === "codex") return Qt.hsla(0.42, 0.55, 0.62, 1)
        if (cli === "grok") return Qt.hsla(0.58, 0.62, 0.64, 1)
        if (cli === "antigravity") return Qt.hsla(0.74, 0.55, 0.66, 1)
        if (cli === "cursor") return Qt.hsla(0.12, 0.7, 0.6, 1)
        if (cli === "openclaw") return Qt.hsla(0.28, 0.55, 0.58, 1)
        if (cli === "hermes") return Qt.hsla(0.02, 0.62, 0.62, 1)
        if (cli === "ollama") return Qt.hsla(0.48, 0.5, 0.58, 1)
        if (cli === "lmstudio") return Qt.hsla(0.62, 0.48, 0.64, 1)
        return Color.accent
    }

    function shownRunCount() {
        var run = root.displayRun
        if (!run || !run.targets) return 0
        return run.targets.length
    }

    function latchWidth() {
        root.widthCount = Model.widthCount(root.armedCount, root.shownRunCount())
    }

    function open() {
        var opening = !root.opened
        root.viewingRunId = ""
        root.historyOpen = false
        root.setupOpen = false
        root.discover()
        root.refreshStatus()
        root.refreshModels()
        historyFile.reload()
        selectionFile.reload()
        if (opening)
            root.latchWidth()
        root.controller.show()
        root.pullClipboard()
        Qt.callLater(function () { promptEdit.forceActiveFocus() })
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction)
        return false
    }

    function runById(id) {
        for (var i = 0; i < history.length; i++)
            if (history[i].id === id) return history[i]
        return null
    }

    function cliLabel(cli) {
        var list = Model.cliList()
        for (var i = 0; i < list.length; i++)
            if (list[i].id === cli) return list[i].label
        return cli
    }

    function handleEscape() {
        var target = Model.escapeTarget(root.clearConfirmOpen, root.menuCli !== "")
        if (target === "confirm") clearConfirm.canceled()
        else if (target === "menu") root.menuCli = ""
        else root.close()
    }

    function discover() {
        discoverProc.command = ["python3", root.runnerPath, "--discover"]
        if (!discoverProc.running) discoverProc.running = true
    }

    function refreshStatus() {
        if (!statusProc.running) statusProc.running = true
    }

    function refreshModels() {
        if (!modelsProc.running) modelsProc.running = true
    }

    function applyModels(raw) {
        var map = {}
        var lines = String(raw || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var line = String(lines[i] || "").trim()
            if (!line) continue
            var parts = line.split("\t")
            var cli = parts[0] || ""
            var value = parts[1] || ""
            if (!cli || !value) continue
            if (!map[cli]) map[cli] = []
            map[cli].push({ value: value, label: parts[2] || value })
        }
        root.liveModels = map
    }

    function applyDiscover(raw) {
        var found = Model.parseDiscover(raw)
        root.available = found
        var seedable = []
        for (var i = 0; i < found.length; i++) {
            if (Model.isEnabled(root.selection, found[i].id)) seedable.push(found[i])
        }
        var next = Model.seedIfEmpty(root.selection, seedable, root.settings)
        if (JSON.stringify(next.models) !== JSON.stringify(root.selection.models)) {
            root.selection = next
            root.saveSelection()
        }
    }

    function applyStatus(raw) {
        root.providerStatus = Model.parseProviderStatus(raw)
    }

    function beginKeyWrite(cli, field) {
        if (keyProc.running) return
        keyProc.keyField = field || null
        keyProc.keyCli = String(cli || "")
        keyProc.stdinEnabled = true
        keyProc.command = ["python3", root.runnerPath, "--set-key", keyProc.keyCli]
        keyProc.running = true
    }

    function askRemoveKey(cli) {
        root.confirmAction = "remove-key"
        root.confirmCli = String(cli || "")
        clearConfirm.selectedIndex = 1
        root.clearConfirmOpen = true
    }

    function applyHistory(raw) {
        var parsed = Model.parseHistory(raw)
        if (!root.historyPrimed) {
            var settled = Model.settleStale(parsed)
            root.historyPrimed = true
            root.history = settled
            root.liveRun = null
            root.cancelRequested = false
            if (JSON.stringify(settled) !== JSON.stringify(parsed)) root.saveHistory()
            root.saveStatus()
        } else {
            root.history = parsed
            if (liveRun && Model.inFlightCount(liveRun) === 0) {
                var found = runById(liveRun.id)
                if (found) root.liveRun = found
            }
        }
        rebuildHistory()
    }

    function applySelection(raw) {
        root.selection = Model.parseSelection(raw)
    }

    function saveHistory() {
        historyFile.setText(Model.serializeHistory(root.history))
        root.tightenPerms()
    }

    function saveSelection() {
        selectionFile.setText(Model.serializeSelection(root.selection))
        root.tightenPerms()
    }

    function saveStatus() {
        statusFile.setText(Model.serializeStatus(root.inFlight))
        root.tightenPerms()
    }

    function tightenPerms() {
        if (permProc.running) return
        permProc.command = ["python3", "-c",
            "import os,sys\nroot=sys.argv[1]\nos.makedirs(root, exist_ok=True)\nos.chmod(root, 0o700)\n" +
            "for name in ('selection.json','history.json','status.json','prompt.txt'):\n" +
            " p=os.path.join(root, name)\n" +
            " if os.path.isfile(p) and not os.path.islink(p): os.chmod(p, 0o600)\n",
            root.stateRoot]
        permProc.running = true
    }

    function rebuildHistory() {
        historyModel.clear()
        for (var i = 0; i < history.length; i++) {
            var run = history[i]
            var chips = []
            var seen = {}
            for (var j = 0; j < run.targets.length; j++) {
                var cli = run.targets[j].cli
                if (seen[cli]) continue
                seen[cli] = true
                chips.push(cli)
            }
            historyModel.append({
                runId: run.id,
                startedAt: run.startedAt,
                preview: Model.previewPrompt(run.prompt, 72),
                chips: chips.join(" ")
            })
        }
    }

    function toggleProvider(cli) {
        if (root.viewingPast || root.inFlight > 0) return
        root.selection = Model.toggleCli(root.selection, cli, undefined, root.settings)
        root.saveSelection()
    }

    function clearPrompt() {
        if (root.inFlight > 0 || root.viewingPast) return
        root.promptText = ""
        promptEdit.text = ""
        root.menuCli = ""
        root.liveRun = null
    }

    function setAutoPaste(on) {
        root.selection = Model.setAutoPaste(root.selection, on)
        root.saveSelection()
        if (on) root.pullClipboard()
    }

    function pullClipboard() {
        if (!Model.autoPasteOn(root.selection)) return
        if (root.promptText.length > 0 || root.inFlight > 0 || root.viewingPast) return
        if (pasteProc.running) return
        pasteProc.running = true
    }

    function pickModel(cli, value) {
        root.selection = Model.setModel(root.selection, cli, value)
        root.saveSelection()
    }

    function setShown(cli, on) {
        root.selection = Model.toggleEnabled(root.selection, cli, on)
        root.saveSelection()
    }

    function signIn(cli) {
        var cmd = Model.signInCommand(cli)
        if (!cmd || cmd.length === 0) return
        var launch = ["xdg-terminal-exec", "--hold", "--title=Disparchy", "--"]
        for (var i = 0; i < cmd.length; i++) launch.push(cmd[i])
        Quickshell.execDetached(launch)
    }

    function statusLabel(status, http) {
        if (http) return status.installed === "missing" ? "endpoint down" : "reachable"
        if (status.installed === "missing") return "install"
        if (status.auth === "signed-out") return "sign in"
        if (status.auth === "gateway" || status.auth === "local node") return status.auth
        if (status.auth === "signed-in") return "open"
        return "open"
    }

    function portLabel(url) {
        var text = String(url || "")
        var at = text.lastIndexOf(":")
        if (at < 0) return text
        return text.slice(at)
    }

    function setEndpoint(cli, url) {
        root.selection = Model.setEndpoint(root.selection, cli, url)
        root.saveSelection()
    }

    function statusFor(cli) {
        for (var i = 0; i < providerStatus.length; i++)
            if (providerStatus[i].cli === cli) return providerStatus[i]
        return { cli: cli, installed: "missing", auth: "", key: "none" }
    }

    function slotList() {
        return [slot0, slot1, slot2, slot3, slot4, slot5]
    }

    function runningKeys() {
        var keys = {}
        var slots = slotList()
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].running && slots[i].jobKey)
                keys[slots[i].jobKey] = true
        }
        return keys
    }

    function pump(run) {
        if (!run) return
        var slots = slotList()
        var keys = runningKeys()
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].running) continue
            var job = Model.claimNext(run, keys)
            if (!job) break
            keys[job.key] = true
            slots[i].take(job, run.id)
        }
    }

    function anySlotRunning() {
        var slots = slotList()
        for (var i = 0; i < slots.length; i++)
            if (slots[i].running) return true
        return false
    }

    function cancel() {
        root.cancelRequested = true
        var slots = slotList()
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].running)
                slots[i].running = false
            slots[i].jobKey = ""
        }
        if (!liveRun) {
            root.cancelRequested = false
            root.saveStatus()
            return
        }
        var targets = []
        for (var j = 0; j < liveRun.targets.length; j++) {
            var t = liveRun.targets[j]
            if (t.status === "pending") {
                targets.push({
                    cli: t.cli,
                    model: t.model,
                    status: "failed",
                    elapsedMs: t.elapsedMs,
                    answer: t.answer,
                    error: "cancelled",
                    exitCode: t.exitCode,
                    stdoutBytes: t.stdoutBytes,
                    stderrBytes: t.stderrBytes
                })
            } else {
                targets.push(t)
            }
        }
        var updated = {
            id: liveRun.id,
            startedAt: liveRun.startedAt,
            prompt: liveRun.prompt,
            targets: targets
        }
        root.liveRun = updated
        root.history = Model.upsertRun(root.history, updated, root.historyMaxRuns)
        root.saveHistory()
        root.saveStatus()
        rebuildHistory()
        root.cancelRequested = false
    }

    function send() {
        if (!root.canSend) return
        var jobs = Model.expandJobs(root.selection, root.shown)
        if (jobs.length === 0) return
        var run = Model.newRun(root.promptText, jobs)
        root.liveRun = run
        root.latchWidth()
        root.history = Model.upsertRun(root.history, run, root.historyMaxRuns)
        root.saveHistory()
        promptFile.setText(root.promptText)
        root.tightenPerms()
        pump(run)
        root.saveStatus()
        rebuildHistory()
    }

    function onTargetExited(cli, model, code, stdout, stderr, startedMs, runId) {
        if (root.cancelRequested) return
        if (!liveRun || liveRun.id !== runId) return
        var current = null
        for (var i = 0; i < liveRun.targets.length; i++) {
            if (liveRun.targets[i].cli === cli && String(liveRun.targets[i].model || "") === String(model || ""))
                current = liveRun.targets[i]
        }
        if (current && current.status !== "pending") return
        var elapsed = Math.max(0, Date.now() - startedMs)
        var answer = String(stdout || "")
        var error = String(stderr || "").trim()
        var status = Model.statusFromExit(code, error)
        if (status === "done") error = ""
        var updated = Model.updateTarget(liveRun, cli, model, {
            status: status,
            elapsedMs: elapsed,
            answer: answer,
            error: error,
            exitCode: code,
            stdoutBytes: Model.byteLength(answer),
            stderrBytes: Model.byteLength(error)
        })
        root.liveRun = updated
        root.history = Model.upsertRun(root.history, updated, root.historyMaxRuns)
        root.saveHistory()
        root.saveStatus()
        rebuildHistory()
        pump(updated)
        if (Model.inFlightCount(updated) === 0)
            Quickshell.execDetached(["notify-send", "--app-name=Disparchy", "Disparchy", Model.settleSummary(updated)])
    }

    function copyAnswer(text) {
        if (!text) return
        Quickshell.execDetached(["wl-copy", "--", text])
    }

    function formatWhen(iso) {
        var d = new Date(iso)
        if (isNaN(d.getTime())) return String(iso || "")
        return Qt.formatDateTime(d, "MMM d  HH:mm")
    }

    function showAsk() {
        root.setupOpen = false
        root.historyOpen = false
        root.viewingRunId = ""
    }

    function showSetup() {
        root.open()
        root.historyOpen = false
        root.viewingRunId = ""
        root.setupOpen = true
    }

    function showHistory() {
        root.open()
        root.setupOpen = false
        root.viewingRunId = ""
        root.historyOpen = true
    }

    function toggleHistory() {
        root.setupOpen = false
        if (root.viewingPast) {
            root.viewingRunId = ""
            root.historyOpen = false
            return
        }
        root.historyOpen = !root.historyOpen
    }

    function toggleSetup() {
        root.historyOpen = false
        root.viewingRunId = ""
        root.setupOpen = !root.setupOpen
        if (root.setupOpen) root.refreshStatus()
    }

    onInFlightChanged: saveStatus()
    onOpenedChanged: {
        if (opened) {
            root.discover()
            root.refreshModels()
            root.pullClipboard()
            Qt.callLater(function () { promptEdit.forceActiveFocus() })
            return
        }
        root.replacingCli = ""
        root.keyErrorCli = ""
        root.confirmAction = "history"
    }

    Component.onCompleted: {
        mkdirProc.command = ["python3", "-c",
            "import os,sys\np=sys.argv[1]\nos.makedirs(p, exist_ok=True)\nos.chmod(p, 0o700)",
            root.stateRoot]
        mkdirProc.running = true
        root.discover()
        root.refreshStatus()
    }

    ListModel { id: historyModel }

    FileView {
        id: manifestFile
        path: root.pluginDir + "/manifest.json"
        printErrors: false
        onLoaded: {
            try {
                root.pluginVersion = String(JSON.parse(text()).version || "")
            } catch (e) {
                root.pluginVersion = ""
            }
        }
    }

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyHistory(text())
        onLoadFailed: root.applyHistory("[]")
        onFileChanged: reload()
    }

    FileView {
        id: selectionFile
        path: root.selectionPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applySelection(text())
        onLoadFailed: root.applySelection("{}")
        onFileChanged: reload()
    }

    FileView {
        id: statusFile
        path: root.statusPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: promptFile
        path: root.promptPath
        atomicWrites: true
        printErrors: false
    }

    Process { id: mkdirProc }
    Process { id: permProc }

    Process {
        id: discoverProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyDiscover(text)
        }
    }

    Process {
        id: pasteProc
        command: ["wl-paste", "-n", "-t", "text"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "")
                if (raw.trim().length === 0) return
                if (!Model.autoPasteOn(root.selection)) return
                if (root.promptText.length > 0 || root.inFlight > 0 || root.viewingPast) return
                if (Model.byteLength(raw) > 32 * 1024) return
                root.promptText = raw
                promptEdit.text = raw
            }
        }
    }

    Process {
        id: modelsProc
        command: ["python3", root.runnerPath, "--models"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyModels(text)
        }
    }

    Process {
        id: statusProc
        command: ["python3", root.runnerPath, "--status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyStatus(text)
        }
    }

    Process {
        id: keyProc
        property string keyCli: ""
        property var keyField: null
        stdout: StdioCollector {
            id: keyOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: keyErr
            waitForEnd: true
        }
        // Quickshell closes the write channel only when stdinEnabled goes false
        // while the process is running (Process::setStdinEnabled -> closeWriteChannel).
        // The runner reads stdin to EOF, so Save and Remove both have to close it.
        onStarted: {
            var field = keyField
            if (field)
                write(field.text)
            stdinEnabled = false
        }
        onExited: function (code) {
            var cli = keyCli
            var field = keyField
            keyField = null
            if (code !== 0) {
                root.keyErrorCli = cli
                return
            }
            if (field)
                field.text = ""
            if (root.keyErrorCli === cli)
                root.keyErrorCli = ""
            if (root.replacingCli === cli)
                root.replacingCli = ""
            root.refreshStatus()
        }
    }

    component Slot: Process {
        property string cliName: ""
        property string modelName: ""
        property string jobKey: ""
        property string runId: ""
        property double startedMs: 0
        stdout: StdioCollector { id: so; waitForEnd: true }
        stderr: StdioCollector { id: se; waitForEnd: true }

        function take(job, id) {
            if (running || !job) return
            cliName = job.cli
            modelName = job.model || ""
            jobKey = job.key
            runId = id
            startedMs = Date.now()
            var cmd = ["python3", root.runnerPath,
                "--cli", job.cli,
                "--model", job.model || "",
                "--timeout", String(root.timeoutSec),
                "--prompt-file", root.promptPath]
            var endpoint = Model.endpointFor(root.selection, job.cli)
            if (endpoint) cmd.push("--endpoint", endpoint)
            command = cmd
            running = true
        }

        onExited: function (code) {
            var out = so.text
            var err = se.text
            var cli = cliName
            var model = modelName
            var started = startedMs
            var id = runId
            jobKey = ""
            Qt.callLater(function () {
                root.onTargetExited(cli, model, code, out, err, started, id)
            })
        }
    }

    Slot { id: slot0 }
    Slot { id: slot1 }
    Slot { id: slot2 }
    Slot { id: slot3 }
    Slot { id: slot4 }
    Slot { id: slot5 }

    TextMetrics {
        id: portChipMetrics
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        text: ":18789"
    }

    readonly property int portChipWidth: Math.ceil(portChipMetrics.advanceWidth) + Style.space(12)

    component TabAction: Rectangle {
        id: act
        property string label: ""
        property bool selected: false
        signal clicked()
        implicitWidth: actCaption.implicitWidth + Style.space(26)
        implicitHeight: Style.space(34)
        radius: Style.space(9)
        color: act.selected ? Qt.alpha(root.ink, Style.selectedFillAlpha)
            : actHover.containsMouse ? Style.hoverFill : Style.normalFill
        border.color: act.selected ? root.ink
            : actHover.containsMouse ? Style.hoverBorderColor : Style.normalBorderColor
        Text {
            id: actCaption
            anchors.centerIn: parent
            text: act.label
            color: act.selected ? root.ink : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: act.selected
        }
        MouseArea {
            id: actHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.hangWidth)
        contentHeight: panel.fittedContentHeight(body.implicitHeight)
        padding: Style.space(6)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: promptEdit.activeFocus
            onCloseRequested: root.handleEscape()
            onTabRequested: function (direction) {
                if (root.clearConfirmOpen)
                    clearConfirm.selectedIndex = clearConfirm.selectedIndex === 0 ? 1 : 0
                else
                    root.switchPanel(direction)
            }
            onActivateRequested: {
                if (root.clearConfirmOpen) {
                    if (clearConfirm.selectedIndex === 0) clearConfirm.canceled()
                    else clearConfirm.confirmed()
                } else {
                    root.send()
                }
            }

            Column {
                id: body
                width: parent.width
                spacing: Style.space(8)

                Column {
                    id: headerCol
                    width: parent.width
                    spacing: Style.space(8)

                    Row {
                        width: parent.width
                        spacing: Style.space(10)

                        Column {
                            width: Math.max(Style.space(160), parent.width - Style.space(180))
                            spacing: Style.space(3)

                            Row {
                                spacing: Style.space(8)
                                DisparchyIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconSize: Style.space(22)
                                    color: root.headerTint
                                    busy: root.inFlight > 0
                                }
                                Text {
                                    text: "Disparchy"
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: root.pluginVersion !== ""
                                    text: "v" + root.pluginVersion
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.headerHint
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: statusPill
                            height: Style.space(32)
                            width: statusRow.implicitWidth + Style.space(20)
                            radius: Style.space(16)
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.alpha(root.headerTint, 0.16)
                            border.color: Qt.alpha(root.headerTint, 0.72)
                            border.width: 1
                            Row {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: Style.space(7)
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.headerTint
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.headerStatus
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: Style.space(34)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(8)
                            TabAction {
                                label: "Ask"
                                selected: !root.setupOpen && !root.historyOpen
                                onClicked: root.showAsk()
                            }
                            TabAction {
                                label: "Setup"
                                selected: root.setupOpen
                                onClicked: {
                                    if (!root.setupOpen) root.toggleSetup()
                                }
                            }
                            TabAction {
                                label: "History"
                                selected: root.historyOpen
                                onClicked: {
                                    if (!root.historyOpen) root.toggleHistory()
                                }
                            }
                        }

                    }
                }

                Row {
                    id: promptRow
                    visible: !root.setupOpen && !root.historyOpen
                    width: parent.width
                    spacing: Style.space(8)

                    BorderSurface {
                        width: parent.width
                            - (actionStack.visible ? actionStack.width : 0)
                            - (backBtn.visible ? backBtn.width : 0)
                            - parent.spacing * ((actionStack.visible ? 1 : 0) + (backBtn.visible ? 1 : 0))
                        height: Style.space(88)
                        radius: Style.space(12)
                        clip: true
                        color: Qt.alpha(Color.accent, promptEdit.activeFocus ? 0.12 : 0.07)
                        borderSpec: Border.controlSpec(promptEdit.activeFocus ? "focus" : "normal", root.ink, Color.accent)

                        Text {
                            id: promptLabel
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Style.space(10)
                            textFormat: Text.PlainText
                            text: root.viewingPast ? "Saved prompt" : "Your prompt"
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Text {
                            visible: root.promptText.length === 0 && !root.viewingPast
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: promptLabel.bottom
                            anchors.leftMargin: Style.space(10)
                            anchors.rightMargin: Style.space(10)
                            anchors.topMargin: Style.space(6)
                            textFormat: Text.PlainText
                            text: "Ask the selected providers anything…"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: root.viewingPast
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: promptLabel.bottom
                            anchors.leftMargin: Style.space(10)
                            anchors.rightMargin: Style.space(10)
                            anchors.topMargin: Style.space(6)
                            textFormat: Text.PlainText
                            text: root.displayRun ? root.displayRun.prompt : ""
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        TextEdit {
                            id: promptEdit
                            visible: !root.viewingPast
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: promptLabel.bottom
                            anchors.bottom: promptHint.top
                            anchors.leftMargin: Style.space(10)
                            anchors.rightMargin: Style.space(10)
                            anchors.topMargin: Style.space(6)
                            anchors.bottomMargin: Style.space(5)
                            text: root.promptText
                            onTextChanged: root.promptText = text
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: TextEdit.Wrap
                            clip: true
                            selectionColor: Style.selectionFillFor(root.ink, Color.accent)
                            selectedTextColor: root.ink
                            Keys.onPressed: function (event) {
                                if (event.key === Qt.Key_Escape) {
                                    root.handleEscape()
                                    event.accepted = true
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.send()
                                    event.accepted = true
                                }
                            }
                        }

                        Text {
                            id: promptHint
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: Style.space(10)
                            text: root.viewingPast ? "From history" : "Enter to compare  ·  Shift+Enter for a new line"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Column {
                        id: actionStack
                        visible: !root.viewingPast
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(70)
                        spacing: Style.space(6)

                    BorderSurface {
                        id: clearBtn
                        opacity: root.canClear ? 1 : 0.4
                        width: parent.width
                        height: Style.space(34)
                        radius: root.actionRadius
                        color: Style.controlFill(clearHover.containsMouse, false, root.ink, Color.accent)
                        borderSpec: Border.controlSpec("normal", root.ink, Color.accent)

                        Text {
                            id: clearLabel
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "Clear"
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        MouseArea {
                            id: clearHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.canClear
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.clearPrompt()
                        }
                    }

                    BorderSurface {
                        id: sendBtn
                        width: parent.width
                        height: Style.space(34)
                        radius: root.actionRadius
                        visible: root.inFlight === 0
                        color: root.canSend
                            ? Qt.alpha(Color.accent, 0.35)
                            : Style.controlFill(sendHover.containsMouse, false, root.ink, Color.accent)
                        borderSpec: root.canSend
                            ? Border.controlSpec("selected", root.ink, Color.accent)
                            : Border.controlSpec("normal", root.ink, Color.accent)

                        Text {
                            id: sendLabel
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "Send"
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: root.canSend
                        }

                        MouseArea {
                            id: sendHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.canSend
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.send()
                        }
                    }

                    BorderSurface {
                        id: cancelBtn
                        visible: root.inFlight > 0
                        width: parent.width
                        height: Style.space(34)
                        radius: root.actionRadius
                        color: Qt.alpha(Color.urgent, 0.35)
                        borderSpec: Border.controlSpec("selected", root.ink, Color.urgent)

                        Text {
                            id: cancelLabel
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "Cancel"
                            color: Color.urgent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancel()
                        }
                    }

                    }

                    BorderSurface {
                        id: backBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.viewingPast
                        width: visible ? Style.space(56) : 0
                        height: root.lineHeight
                        radius: root.actionRadius
                        color: Style.controlFill(backHover.containsMouse, false, root.ink, Color.accent)
                        borderSpec: Border.controlSpec("normal", root.ink, Color.accent)
                        Text {
                            anchors.centerIn: parent
                            text: "Back"
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }
                        MouseArea {
                            id: backHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewingRunId = ""
                        }
                    }
                }

                Item {
                    id: askBlock
                    width: parent.width
                    height: root.setupOpen ? setupView.height
                        : (root.historyOpen ? histCol.implicitHeight
                            : providerFlow.y + providerFlow.height
                                + (root.menuCli !== "" ? modelMenu.height + Style.space(4) : 0))

                    Text {
                        id: providerLabel
                        visible: !root.setupOpen && !root.historyOpen
                        height: visible ? implicitHeight : 0
                        text: "Send to"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    Flow {
                        id: providerFlow
                        visible: !root.setupOpen && !root.historyOpen
                        width: parent.width
                        y: providerLabel.height + (visible ? Style.space(6) : 0)
                        height: implicitHeight
                        spacing: Style.space(7)

                        Repeater {
                            model: root.shown
                            delegate: Rectangle {
                                id: providerChip
                                required property var modelData
                                width: chipContents.implicitWidth + Style.space(18)
                                height: Style.space(30)
                                radius: Style.space(9)
                                readonly property bool armed: Model.isArmed(root.selection, modelData.id)
                                readonly property color tint: root.tintFor(modelData.id)
                                color: armed ? Qt.alpha(tint, 0.15) : Qt.alpha(root.ink, 0.04)
                                border.color: armed ? Qt.alpha(tint, 0.75) : Qt.alpha(root.ink, 0.22)
                                border.width: 1

                                Row {
                                    id: chipContents
                                    anchors.centerIn: parent
                                    spacing: Style.space(6)

                                    Rectangle {
                                        width: Style.space(15)
                                        height: width
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: Math.max(2, Style.cornerRadius / 2)
                                        color: providerChip.armed ? providerChip.tint : "transparent"
                                        border.color: providerChip.tint
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            visible: providerChip.armed
                                            text: "✓"
                                            color: Color.background
                                            font.pixelSize: Style.space(10)
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: providerChip.modelData.label
                                        color: providerChip.tint
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: providerChip.armed
                                    }

                                    Text {
                                        id: modelArrow
                                        visible: providerChip.armed
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.menuCli === providerChip.modelData.id ? "▴" : "▾"
                                        color: providerChip.tint
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.space(14)
                                    }
                                }

                                MouseArea {
                                    id: armHit
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.right: providerChip.armed ? modelHit.left : parent.right
                                    enabled: !root.viewingPast && root.inFlight === 0
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.toggleProvider(providerChip.modelData.id)
                                }

                                MouseArea {
                                    id: modelHit
                                    z: 1
                                    visible: providerChip.armed
                                    enabled: visible && !root.viewingPast && root.inFlight === 0
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: providerChip.armed
                                        ? Math.max(Style.space(36), modelArrow.implicitWidth + Style.space(22))
                                        : 0
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.menuCli = root.menuCli === providerChip.modelData.id
                                        ? "" : providerChip.modelData.id
                                }
                            }
                        }
                    }

                    Flickable {
                        id: setupView
                        visible: root.setupOpen
                        width: parent.width
                        height: Math.min(setupCol.implicitHeight, room)
                        contentWidth: width
                        contentHeight: setupCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        onVisibleChanged: if (visible) contentY = 0

                        readonly property real room: {
                            var content = setupCol.implicitHeight
                            if (!(panel.availableCardHeight > 0))
                                return content
                            var inner = panel.availableCardHeight - panel.verticalContentInset
                            var chrome = headerCol.implicitHeight + body.spacing
                            return Math.max(0, inner - chrome)
                        }

                        Column {
                        id: setupCol
                        width: parent.width
                        spacing: Style.space(10)

                        Text {
                            text: "Providers"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Grid {
                            id: setupGrid
                            width: parent.width
                            columns: 2
                            columnSpacing: Style.space(10)
                            rowSpacing: Style.space(10)

                            Component {
                                id: setupCardDelegate
                                Rectangle {
                                    id: setupCard
                                    required property var modelData
                                    width: {
                                        var cols = parent && parent.columns > 0 ? parent.columns : 1
                                        var gap = parent ? parent.columnSpacing : 0
                                        var span = parent ? parent.width : 0
                                        return (span - gap * (cols - 1)) / cols
                                    }
                                    height: setupRow.implicitHeight + Style.space(16)
                                    radius: Style.space(9)
                                    color: Qt.alpha(setupRow.tint, 0.07)
                                    border.color: Qt.alpha(setupRow.tint, 0.33)
                                    border.width: 1

                                    Column {
                                        id: setupRow
                                        x: Style.space(8)
                                        y: Style.space(8)
                                        width: parent.width - Style.space(16)
                                        spacing: Style.space(7)

                                        readonly property string cliId: setupCard.modelData.id
                                        readonly property var presets: setupCard.modelData.presets || []
                                        readonly property bool onBar: Model.isEnabled(root.selection, cliId)
                                        readonly property var status: root.statusFor(cliId)
                                        readonly property color tint: root.tintFor(cliId)
                                        readonly property bool http: setupCard.modelData.transport === "http"

                                        Item {
                                            width: parent.width
                                            height: Style.space(30)

                                            Rectangle {
                                                width: Style.space(3)
                                                height: Style.space(22)
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                radius: 1
                                                color: setupRow.tint
                                            }

                                            Text {
                                                x: Style.space(14)
                                                width: Style.space(108)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: setupCard.modelData.label
                                                color: setupRow.tint
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                x: Style.space(130)
                                                width: Math.max(Style.space(48), parent.width - x - Style.space(64))
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.statusLabel(setupRow.status, setupRow.http)
                                                color: setupRow.status.auth === "signed-out" ? Color.urgent : root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                                font.underline: !setupRow.http
                                                elide: Text.ElideRight
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: !setupRow.http
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: root.signIn(setupRow.cliId)
                                                }
                                            }

                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Style.space(44)
                                                height: Style.space(22)
                                                radius: Style.space(11)
                                                color: setupRow.onBar ? Qt.alpha(setupRow.tint, 0.85) : Qt.alpha(root.dim, 0.35)
                                                Rectangle {
                                                    width: Style.space(16)
                                                    height: Style.space(16)
                                                    radius: Style.space(8)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: setupRow.onBar ? parent.width - width - Style.space(3) : Style.space(3)
                                                    color: Color.background
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -Style.space(6)
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setShown(setupRow.cliId, !setupRow.onBar)
                                                }
                                            }
                                        }

                                        Row {
                                            visible: Model.needsEndpoint(setupRow.cliId)
                                            width: parent.width
                                            height: visible ? Style.space(24) : 0
                                            spacing: Style.space(6)

                                            TextInput {
                                                id: endpointEdit
                                                width: parent.width - portRow.width - parent.spacing
                                                leftPadding: Style.space(8)
                                                topPadding: 0
                                                bottomPadding: 0
                                                verticalAlignment: TextInput.AlignVCenter
                                                height: parent.height
                                                text: Model.endpointFor(root.selection, setupRow.cliId)
                                                color: root.ink
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                selectByMouse: true
                                                clip: true
                                                onEditingFinished: root.setEndpoint(setupRow.cliId, text)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    z: -1
                                                    radius: Math.max(2, Style.cornerRadius / 2)
                                                    color: "transparent"
                                                    border.color: Qt.alpha(setupRow.tint, 0.7)
                                                    border.width: 1
                                                }
                                            }

                                            Row {
                                                id: portRow
                                                spacing: Style.space(4)
                                                Repeater {
                                                    model: setupRow.presets
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        width: root.portChipWidth
                                                        height: Style.space(24)
                                                        radius: Style.space(12)
                                                        color: endpointEdit.text === modelData
                                                            ? Qt.alpha(setupRow.tint, 0.35)
                                                            : "transparent"
                                                        border.color: setupRow.tint
                                                        border.width: 1
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.portLabel(modelData)
                                                            color: setupRow.tint
                                                            font.family: root.fontFamily
                                                            font.pixelSize: Style.font.caption
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                root.setEndpoint(setupRow.cliId, modelData)
                                                                endpointEdit.text = modelData
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Column {
                                            id: keyBlock
                                            visible: Model.needsSecret(setupRow.cliId)
                                            width: parent.width
                                            spacing: Style.space(4)

                                            readonly property bool saved: setupRow.status.key === "saved"
                                            readonly property bool refused: setupRow.status.key === "refused"
                                            readonly property bool unusable: setupRow.status.key === "unusable"
                                            readonly property bool editing: !unusable && ((!saved && !refused) || root.replacingCli === setupRow.cliId)

                                            property bool panelWasOpen: root.opened
                                            onPanelWasOpenChanged: if (!panelWasOpen) secretEdit.text = ""

                                            Row {
                                                visible: (keyBlock.saved || keyBlock.refused) && !keyBlock.editing
                                                width: parent.width
                                                spacing: Style.space(12)

                                                Text {
                                                    text: keyBlock.saved ? "Key saved" : "Key not used"
                                                    color: root.ink
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                }
                                                Text {
                                                    text: "Replace"
                                                    color: replaceHit.containsMouse ? root.ink : root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    MouseArea {
                                                        id: replaceHit
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            secretEdit.text = ""
                                                            root.replacingCli = setupRow.cliId
                                                            if (root.keyErrorCli === setupRow.cliId)
                                                                root.keyErrorCli = ""
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: "Remove"
                                                    color: removeHit.containsMouse ? root.ink : root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    MouseArea {
                                                        id: removeHit
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.askRemoveKey(setupRow.cliId)
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: keyBlock.refused && !keyBlock.editing
                                                width: parent.width
                                                text: "Other users can read this key's file. Replace it to fix that."
                                                color: root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                visible: keyBlock.unusable && Model.keyUnusableLine !== ""
                                                width: parent.width
                                                text: Model.keyUnusableLine
                                                color: root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }

                                            Row {
                                                id: keyEditRow
                                                visible: keyBlock.editing
                                                width: parent.width
                                                spacing: Style.space(6)

                                                TextField {
                                                    id: secretEdit
                                                    width: Math.max(Style.space(80), parent.width - keySave.width - (keyCancel.visible ? keyCancel.width + parent.spacing : 0) - parent.spacing)
                                                    height: Style.space(28)
                                                    echoMode: TextInput.Password
                                                    placeholderText: "Paste API key"
                                                    placeholderTextColor: root.dim
                                                    color: root.ink
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    leftPadding: Style.space(8)
                                                    selectByMouse: true
                                                    background: Rectangle {
                                                        radius: Math.max(2, Style.cornerRadius / 2)
                                                        color: "transparent"
                                                        border.color: Qt.alpha(setupRow.tint, 0.7)
                                                        border.width: 1
                                                    }
                                                }
                                                Text {
                                                    id: keySave
                                                    text: "Save"
                                                    color: saveHit.containsMouse ? root.ink : root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    MouseArea {
                                                        id: saveHit
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.beginKeyWrite(setupRow.cliId, secretEdit)
                                                    }
                                                }
                                                Text {
                                                    id: keyCancel
                                                    visible: root.replacingCli === setupRow.cliId
                                                    text: "Cancel"
                                                    color: cancelHit.containsMouse ? root.ink : root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    MouseArea {
                                                        id: cancelHit
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            secretEdit.text = ""
                                                            if (root.replacingCli === setupRow.cliId)
                                                                root.replacingCli = ""
                                                            if (root.keyErrorCli === setupRow.cliId)
                                                                root.keyErrorCli = ""
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: root.keyErrorCli === setupRow.cliId
                                                width: parent.width
                                                text: "Couldn't save key"
                                                color: root.ink
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: Model.setupGroup(false)
                                delegate: setupCardDelegate
                            }
                        }

                        Text {
                            text: "Endpoints"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Grid {
                            id: endpointGrid
                            width: parent.width
                            columns: 1
                            columnSpacing: Style.space(10)
                            rowSpacing: Style.space(10)

                            Repeater {
                                model: Model.setupGroup(true)
                                delegate: setupCardDelegate
                            }
                        }

                        Text {
                            text: "Preferences"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }

                        Rectangle {
                            width: parent.width
                            height: Style.space(52)
                            radius: Style.space(9)
                            color: Qt.alpha(Color.accent, 0.07)
                            border.color: Qt.alpha(Color.accent, 0.35)
                            border.width: 1

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Style.space(12)
                                spacing: Style.space(3)
                                Text {
                                    text: "Auto-paste clipboard"
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }
                                Text {
                                    text: "Fill an empty prompt when Disparchy opens"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: Style.space(12)
                                width: Style.space(44)
                                height: Style.space(22)
                                radius: Style.space(11)
                                readonly property bool on: Model.autoPasteOn(root.selection)
                                color: on ? Qt.alpha(Color.accent, 0.85) : Qt.alpha(root.dim, 0.35)
                                Rectangle {
                                    width: Style.space(16)
                                    height: width
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.on ? parent.width - width - Style.space(3) : Style.space(3)
                                    color: Color.background
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -Style.space(6)
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setAutoPaste(!Model.autoPasteOn(root.selection))
                                }
                            }
                        }
                    }

                        ScrollBar.vertical: ScrollBar {
                            parent: setupView.parent
                            padding: 0
                            interactive: false
                            width: Style.space(4)
                            height: setupView.height
                            x: setupView.x + setupView.width + (panel.padding - width) / 2
                            y: setupView.y
                            policy: root.setupOpen && setupView.contentHeight > setupView.height
                                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: Style.space(4)
                                radius: width / 2
                                color: root.dim
                            }
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                    }

                    Column {
                        id: histCol
                        visible: root.historyOpen
                        width: parent.width
                        spacing: Style.space(8)

                        Item {
                            width: parent.width
                            height: Style.space(22)
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Saved comparisons"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear history"
                                color: clearMa.containsMouse ? Color.urgent : root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                MouseArea {
                                    id: clearMa
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.confirmAction = "history"
                                        clearConfirm.selectedIndex = 1
                                        root.clearConfirmOpen = true
                                    }
                                }
                            }
                        }

                        ListView {
                            width: parent.width
                            height: Math.min(Style.space(250), Math.max(Style.space(52), contentHeight))
                            spacing: Style.space(6)
                            clip: true
                            model: historyModel
                            delegate: Rectangle {
                                required property string runId
                                required property string startedAt
                                required property string preview
                                required property string chips
                                width: ListView.view.width
                                height: Style.space(52)
                                radius: Style.space(8)
                                color: histMa.containsMouse ? Qt.alpha(Color.accent, 0.14)
                                    : Qt.alpha(Color.accent, 0.055)
                                border.color: histMa.containsMouse ? Qt.alpha(Color.accent, 0.65)
                                    : Qt.alpha(Color.accent, 0.23)
                                border.width: 1

                                Text {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: Style.space(8)
                                    text: root.formatWhen(startedAt)
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Style.space(8)
                                    text: chips
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Style.space(8)
                                    text: preview || "(empty prompt)"
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    id: histMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.viewingRunId = runId
                                        root.historyOpen = false
                                        root.latchWidth()
                                    }
                                }
                            }
                        }

                        Text {
                            visible: historyModel.count === 0
                            text: "No comparisons saved yet. Ask a question to start one."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Flickable {
                        id: modelMenu
                        visible: root.menuCli !== "" && !root.setupOpen && !root.historyOpen
                        width: parent.width
                        y: providerFlow.y + providerFlow.height + Style.space(4)
                        height: Math.min(modelCol.implicitHeight, Style.space(220))
                        contentHeight: modelCol.implicitHeight
                        clip: true
                        flickableDirection: Flickable.VerticalFlick

                        Column {
                        id: modelCol
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: root.menuCli !== "" ? Model.modelsFor(root.menuCli, root.liveModels[root.menuCli]) : []
                            delegate: Item {
                                required property var modelData
                                width: modelMenu.width
                                height: Style.space(22)

                                readonly property bool picked: Model.modelForCli(root.menuCli, root.selection, root.settings) === modelData.value

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(18)
                                    verticalAlignment: Text.AlignVCenter
                                    text: (picked ? "• " : "") + modelData.label
                                    color: picked ? root.tintFor(root.menuCli) : root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.pickModel(root.menuCli, modelData.value)
                                        root.menuCli = ""
                                    }
                                }
                            }
                        }
                        }
                    }

                }

                Item {
                    id: resultArea
                    width: parent.width
                    visible: !root.setupOpen && root.displayRun && root.displayRun.targets && root.displayRun.targets.length > 0
                    height: resultView.height

                Flickable {
                    id: resultView
                    width: parent.width
                    height: Math.min(resultGrid.implicitHeight, room)
                    contentWidth: width
                    contentHeight: resultGrid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    // Same cap as Setup: the card stays within availableCardHeight.
                    // Ask also has the prompt, the provider row, and the footer,
                    // so those count as chrome above and below this view.
                    readonly property real room: {
                        var content = resultGrid.implicitHeight
                        if (!(panel.availableCardHeight > 0))
                            return content
                        var inner = panel.availableCardHeight - panel.verticalContentInset
                        var chromeItems = 1
                            + (promptRow.visible ? 1 : 0)
                            + 1
                            + (resultFooter.visible ? 1 : 0)
                        var chrome = headerCol.implicitHeight
                            + (promptRow.visible ? promptRow.implicitHeight : 0)
                            + askBlock.height
                            + (resultFooter.visible ? resultFooter.height : 0)
                            + body.spacing * chromeItems
                        return Math.max(0, inner - chrome)
                    }

                    readonly property int columns: Model.resultColumns(
                        width, paper.count, Style.space(280), Style.space(8))

                    Grid {
                        id: resultGrid
                        width: parent.width
                        columns: resultView.columns
                        columnSpacing: Style.space(8)
                        rowSpacing: Style.space(8)

                    Repeater {
                        id: paper
                        model: root.displayRun ? root.displayRun.targets : []
                        delegate: Item {
                            id: resultCard
                            required property var modelData
                            width: {
                                var cols = parent && parent.columns > 0 ? parent.columns : 1
                                var gap = parent ? parent.columnSpacing : 0
                                var span = parent ? parent.width : 0
                                return (span - gap * (cols - 1)) / cols
                            }
                            height: cardContent.implicitHeight + Style.space(20)

                            readonly property color tint: root.tintFor(modelData.cli)
                            readonly property string keyNote: Model.keyFileNote(modelData.error, root.statusFor(modelData.cli).key)
                            readonly property string bodyText: modelData.answer !== "" ? modelData.answer
                                : (keyNote !== "" ? keyNote
                                    : (modelData.error !== "" ? modelData.error
                                        : (modelData.status === "pending" ? "Running…" : "")))

                            Rectangle {
                                anchors.fill: parent
                                radius: Style.space(9)
                                color: Qt.alpha(resultCard.tint, 0.055)
                                border.color: Qt.alpha(resultCard.tint, 0.28)
                                border.width: 1
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Style.space(9)
                                anchors.rightMargin: Style.space(9)
                                height: Style.space(3)
                                radius: 1
                                color: modelData.status === "failed" || modelData.status === "timeout"
                                    ? Color.urgent : resultCard.tint
                                SequentialAnimation on opacity {
                                    running: resultCard.modelData.status === "pending"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.32; duration: 750; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
                                }
                            }

                            Column {
                                id: cardContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Style.space(10)
                                spacing: Style.space(6)

                                Row {
                                    width: parent.width
                                    spacing: Style.space(5)
                                    Rectangle {
                                        width: Style.space(7)
                                        height: width
                                        radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: resultCard.modelData.status === "failed" || resultCard.modelData.status === "timeout"
                                            ? Color.urgent : resultCard.tint
                                    }
                                    Text {
                                        id: providerName
                                        text: root.cliLabel(resultCard.modelData.cli)
                                        color: resultCard.tint
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                    }
                                    Text {
                                        width: Math.max(0, parent.width - providerName.implicitWidth - Style.space(20))
                                        text: resultCard.modelData.model !== "" ? resultCard.modelData.model : "default"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: Model.nerdLine(resultCard.modelData)
                                    color: resultCard.modelData.status === "failed" || resultCard.modelData.status === "timeout"
                                        ? Color.urgent : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    id: answerText
                                    width: parent.width
                                    text: resultCard.modelData.answer !== ""
                                        ? Model.markdownForDisplay(resultCard.bodyText)
                                        : resultCard.bodyText
                                    textFormat: resultCard.modelData.answer !== ""
                                        ? Text.MarkdownText : Text.PlainText
                                    color: resultCard.modelData.answer !== "" ? root.ink
                                        : (resultCard.keyNote !== "" ? root.dim
                                            : (resultCard.modelData.error !== "" ? Color.urgent : root.dim))
                                    linkColor: resultCard.tint
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.Wrap
                                    onLinkActivated: function(link) {
                                        var safe = Model.externalLinkForDisplay(link)
                                        if (safe) Qt.openUrlExternally(safe)
                                    }
                                }

                                Row {
                                    spacing: Style.space(8)
                                    visible: resultCard.modelData.answer !== ""

                                    BorderSurface {
                                        id: copyBtn
                                        width: Math.max(Style.space(56), copyLabel.implicitWidth + Style.space(20))
                                        height: root.lineHeight
                                        radius: root.actionRadius
                                        color: Style.controlFill(copyHover.containsMouse, false, root.ink, Color.accent)
                                        borderSpec: Border.controlSpec("normal", root.ink, Color.accent)

                                        Text {
                                            id: copyLabel
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "Copy"
                                            color: root.ink
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                        }

                                        MouseArea {
                                            id: copyHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyAnswer(resultCard.modelData.answer)
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    visible: resultCard.modelData.answer !== ""
                                    text: "≈ " + Model.estimateTokens(resultCard.modelData.answer) + " out"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                    }
                    }

                    ScrollBar.vertical: ScrollBar {
                        parent: resultArea
                        padding: 0
                        interactive: false
                        width: Style.space(4)
                        height: resultView.height
                        x: resultView.x + resultView.width + (panel.padding - width) / 2
                        y: resultView.y
                        policy: resultArea.visible && resultView.contentHeight > resultView.height
                            ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: Style.space(4)
                            radius: width / 2
                            color: root.dim
                        }
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                }
                }

                Item {
                    id: resultFooter
                    width: parent.width
                    height: visible ? Style.space(22) : 0
                    visible: !root.setupOpen && root.displayRun && root.displayRun.targets && root.displayRun.targets.length > 0

                    Rectangle {
                        width: parent.width
                        height: 1
                        anchors.top: parent.top
                        color: root.rule
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: parent.width
                        text: Model.tokenFooter(root.displayRun, root.history)
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                }
            }

            ConfirmDialog {
                id: clearConfirm
                anchors.fill: parent
                opened: root.clearConfirmOpen
                z: 30
                message: root.confirmAction === "remove-key"
                    ? ("Remove the saved key for " + root.cliLabel(root.confirmCli) + "?")
                    : "Clear Disparchy history?"
                confirmText: root.confirmAction === "remove-key" ? "Remove" : "Clear"
                background: Color.popups.background
                foreground: root.ink
                selectedText: Color.accent
                fontFamily: root.fontFamily
                cornerRadius: Style.cornerRadius
                onCanceled: {
                    root.clearConfirmOpen = false
                    root.confirmAction = "history"
                }
                onConfirmed: {
                    root.clearConfirmOpen = false
                    if (root.confirmAction === "remove-key") {
                        var cli = root.confirmCli
                        root.confirmAction = "history"
                        root.beginKeyWrite(cli, null)
                        return
                    }
                    root.history = []
                    if (liveRun && Model.inFlightCount(liveRun) === 0) root.liveRun = null
                    root.viewingRunId = ""
                    root.saveHistory()
                    root.rebuildHistory()
                }
            }
        }
    }
}
