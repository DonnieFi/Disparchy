import QtQuick
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
    property int openPickers: 0
    property var selection: Model.emptySelection()
    property var auth: ({})
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
    property bool cancelRequested: false
    property var resultExpand: ({})

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateRoot: Model.stateDir(home, Quickshell.env("XDG_STATE_HOME"))
    readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("manifest.json"))
    readonly property string runnerPath: pluginDir + "/bin/disparchy-run"
    readonly property string historyPath: stateRoot + "/history.json"
    readonly property string selectionPath: stateRoot + "/selection.json"
    readonly property string authPath: stateRoot + "/auth.json"
    readonly property string statusPath: stateRoot + "/status.json"
    readonly property string promptPath: stateRoot + "/prompt.txt"

    readonly property color ink: Color.popups.text
    readonly property color dim: Qt.darker(ink, 1.55)
    readonly property color rule: Util.alpha(ink, 0.16)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property int hangWidth: {
        var n = displayRun && displayRun.targets ? Math.max(1, displayRun.targets.length) : 1
        if (setupOpen) return Style.space(680)
        if (!displayRun) return Style.space(580)
        return Math.max(Style.space(520), Math.min(Style.space(960), Style.space(210) * n))
    }
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
    readonly property int armedCount: {
        var n = 0
        for (var i = 0; i < shown.length; i++)
            if (Model.isArmed(selection, shown[i].id)) n++
        return n
    }
    readonly property string headerHint: {
        if (setupOpen) return "Switch a provider onto the bar. Click sign in to open the CLI."
        if (historyOpen) return "Past runs stay on disk."
        if (viewingPast) return "A past run. Back returns to the prompt."
        return "One prompt. The checked providers answer together."
    }
    readonly property string headerStatus: {
        if (inFlight > 0) return inFlight + " RUNNING"
        if (setupOpen) return "SETUP"
        if (historyOpen) return history.length + " SAVED"
        if (armedCount === 0) return "IDLE"
        return armedCount + " ARMED"
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

    function open() {
        root.viewingRunId = ""
        root.historyOpen = false
        root.setupOpen = false
        root.discover()
        root.refreshStatus()
        root.refreshModels()
        historyFile.reload()
        selectionFile.reload()
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

    function notePicker(open) {
        root.openPickers = Math.max(0, root.openPickers + (open ? 1 : -1))
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
        var rows = []
        var lines = String(raw || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var line = String(lines[i] || "").trim()
            if (!line) continue
            var parts = line.split("\t")
            rows.push({
                cli: parts[0] || "",
                installed: parts[1] || "missing",
                auth: parts[2] || ""
            })
        }
        root.providerStatus = rows
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

    function applyAuth(raw) {
        root.auth = Model.parseAuth(raw)
    }

    function saveHistory() {
        historyFile.setText(Model.serializeHistory(root.history))
        root.tightenPerms()
    }

    function saveSelection() {
        selectionFile.setText(Model.serializeSelection(root.selection))
        root.tightenPerms()
    }

    function saveAuth() {
        authFile.setText(Model.serializeAuth(root.auth))
        root.tightenPerms()
    }

    function setSecret(cli, key) {
        root.auth = Model.setSecret(root.auth, cli, key)
        root.saveAuth()
    }

    function saveStatus() {
        statusFile.setText(Model.serializeStatus(root.inFlight))
        root.tightenPerms()
    }

    function tightenPerms() {
        if (permProc.running) return
        permProc.command = ["python3", "-c",
            "import os,sys\nroot=sys.argv[1]\nos.makedirs(root, exist_ok=True)\nos.chmod(root, 0o700)\n" +
            "for name in os.listdir(root):\n p=os.path.join(root, name)\n" +
            " if os.path.isfile(p): os.chmod(p, 0o600)\n",
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
        return { cli: cli, installed: "missing", auth: "" }
    }

    function toggleResultExpand(key) {
        var next = {}
        for (var k in root.resultExpand)
            if (Object.prototype.hasOwnProperty.call(root.resultExpand, k))
                next[k] = root.resultExpand[k]
        next[key] = !next[key]
        root.resultExpand = next
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
    onOpenedChanged: if (opened) {
        root.discover()
        root.refreshModels()
        root.pullClipboard()
        Qt.callLater(function () { promptEdit.forceActiveFocus() })
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
        id: authFile
        path: root.authPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyAuth(text())
        onLoadFailed: root.applyAuth("{}")
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
            if (Model.secretFor(root.auth, job.cli))
                cmd.push("--auth-file", root.authPath)
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
            blocked: promptEdit.activeFocus || root.openPickers > 0
            onCloseRequested: {
                if (root.clearConfirmOpen) clearConfirm.canceled()
                else root.close()
            }
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
                                Item {
                                    width: Style.space(22)
                                    height: Style.space(22)
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        width: Style.space(4)
                                        height: Style.space(10)
                                        radius: 1
                                        color: root.ink
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                    }
                                    Rectangle {
                                        width: Style.space(4)
                                        height: Style.space(16)
                                        radius: 1
                                        color: root.ink
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                    }
                                    Rectangle {
                                        width: Style.space(4)
                                        height: Style.space(12)
                                        radius: 1
                                        color: root.ink
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                    }
                                }
                                Text {
                                    text: "DISPARCHY"
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    font.letterSpacing: 2.5
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
                                font.pixelSize: 11
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
                                    font.pixelSize: 9
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

                        TabAction {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Paste"
                            selected: Model.autoPasteOn(root.selection)
                            onClicked: root.setAutoPaste(!Model.autoPasteOn(root.selection))
                        }
                    }
                }

                Row {
                    visible: !root.setupOpen
                    width: parent.width
                    spacing: Style.space(4)

                    BorderSurface {
                        width: parent.width
                            - (sendBtn.visible ? sendBtn.width : 0)
                            - (clearBtn.visible ? clearBtn.width : 0)
                            - (cancelBtn.visible ? cancelBtn.width : 0)
                            - (backBtn.visible ? backBtn.width : 0)
                            - parent.spacing * ((sendBtn.visible ? 1 : 0) + (clearBtn.visible ? 1 : 0) + (cancelBtn.visible ? 1 : 0) + (backBtn.visible ? 1 : 0))
                        height: root.lineHeight
                        radius: root.actionRadius
                        clip: true
                        color: Style.controlFill(promptEdit.activeFocus, false, root.ink, Color.accent)
                        borderSpec: Border.controlSpec(promptEdit.activeFocus ? "focus" : "normal", root.ink, Color.accent)

                        Text {
                            visible: root.promptText.length === 0 && !root.viewingPast
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.controlPaddingX
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                            text: "Ask checked providers…"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: root.viewingPast
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.controlPaddingX
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                            text: root.displayRun ? root.displayRun.prompt : ""
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: promptEdit
                            visible: !root.viewingPast
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.controlPaddingX
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.promptText
                            onTextChanged: root.promptText = text
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            clip: true
                            selectionColor: Style.selectionFillFor(root.ink, Color.accent)
                            selectedTextColor: root.ink
                            Keys.onPressed: function (event) {
                                if (event.key === Qt.Key_Escape) {
                                    root.close()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.send()
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    BorderSurface {
                        id: clearBtn
                        visible: !root.viewingPast
                        opacity: root.canClear ? 1 : 0.4
                        width: visible ? Math.max(Style.space(56), clearLabel.implicitWidth + Style.space(16)) : 0
                        height: root.lineHeight
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
                        width: Math.max(Style.space(56), sendLabel.implicitWidth + Style.space(16))
                        height: root.lineHeight
                        radius: root.actionRadius
                        visible: !root.viewingPast
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
                        visible: root.inFlight > 0 && !root.viewingPast
                        width: visible ? Math.max(Style.space(64), cancelLabel.implicitWidth + Style.space(16)) : 0
                        height: root.lineHeight
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

                    BorderSurface {
                        id: backBtn
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
                    width: parent.width
                    height: root.setupOpen ? setupCol.implicitHeight
                        : (root.historyOpen ? histCol.implicitHeight
                            : providerFlow.height + (root.menuCli !== "" ? modelMenu.height : 0))

                    Row {
                        id: providerFlow
                        visible: !root.setupOpen && !root.historyOpen
                        width: parent.width
                        height: root.lineHeight
                        spacing: Style.space(10)
                        clip: true

                        Repeater {
                            model: root.shown
                            delegate: Row {
                                required property var modelData
                                spacing: Style.space(4)
                                height: root.lineHeight

                                readonly property bool armed: Model.isArmed(root.selection, modelData.id)
                                readonly property color tint: root.tintFor(modelData.id)

                                Rectangle {
                                    width: root.controlSize
                                    height: root.controlSize
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: Math.max(2, Style.cornerRadius / 2)
                                    color: armed ? Qt.alpha(tint, 0.85) : "transparent"
                                    border.color: tint
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        visible: armed
                                        text: "✓"
                                        color: Color.background
                                        font.pixelSize: Style.space(10)
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Style.space(4)
                                        enabled: !root.viewingPast && root.inFlight === 0
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.toggleProvider(modelData.id)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: tint
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: armed
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Style.space(4)
                                        enabled: !root.viewingPast && root.inFlight === 0
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.toggleProvider(modelData.id)
                                    }
                                }

                                Rectangle {
                                    width: root.controlSize
                                    height: root.controlSize
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: armed
                                    radius: Math.max(2, Style.cornerRadius / 2)
                                    color: root.menuCli === modelData.id ? Qt.alpha(tint, 0.22) : "transparent"
                                    border.color: tint
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.menuCli === modelData.id ? "▴" : "▾"
                                        color: tint
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.space(14)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !root.viewingPast && root.inFlight === 0
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.menuCli = root.menuCli === modelData.id ? "" : modelData.id
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        id: setupCol
                        visible: root.setupOpen
                        width: parent.width
                        spacing: Style.space(2)

                        Repeater {
                            model: Model.cliList()
                            delegate: Column {
                                id: setupRow
                                required property var modelData
                                width: setupCol.width
                                spacing: Style.space(2)

                                readonly property string cliId: modelData.id
                                readonly property var presets: modelData.presets || []
                                readonly property bool onBar: Model.isEnabled(root.selection, modelData.id)
                                readonly property var status: root.statusFor(modelData.id)
                                readonly property color tint: root.tintFor(modelData.id)
                                readonly property bool http: modelData.transport === "http"

                                Item {
                                    width: parent.width
                                    height: Style.space(30)

                                    Rectangle {
                                        width: Style.space(3)
                                        height: Style.space(22)
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: 1
                                        color: tint
                                    }

                                    Text {
                                        x: Style.space(14)
                                        width: Style.space(108)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: tint
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        x: Style.space(130)
                                        width: Math.max(Style.space(48), parent.width - x - Style.space(64))
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.statusLabel(status, http)
                                        color: status.auth === "signed-out" ? Color.urgent : root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.underline: !http
                                        elide: Text.ElideRight
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !http
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
                                        color: onBar ? Qt.alpha(tint, 0.85) : Qt.alpha(root.dim, 0.35)
                                        Rectangle {
                                            width: Style.space(16)
                                            height: Style.space(16)
                                            radius: Style.space(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: onBar ? parent.width - width - Style.space(3) : Style.space(3)
                                            color: Color.background
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Style.space(6)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setShown(setupRow.cliId, !onBar)
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
                                            border.color: Qt.alpha(tint, 0.7)
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
                                                width: portText.implicitWidth + Style.space(12)
                                                height: Style.space(24)
                                                radius: Style.space(12)
                                                color: endpointEdit.text === modelData
                                                    ? Qt.alpha(setupRow.tint, 0.35)
                                                    : "transparent"
                                                border.color: setupRow.tint
                                                border.width: 1
                                                Text {
                                                    id: portText
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

                                Item {
                                    visible: Model.needsSecret(setupRow.cliId)
                                    width: parent.width
                                    height: visible ? Style.space(24) : 0

                                    TextInput {
                                        id: secretEdit
                                        z: 1
                                        anchors.fill: parent
                                        leftPadding: Style.space(8)
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        text: Model.secretFor(root.auth, setupRow.cliId)
                                        color: root.ink
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        selectByMouse: true
                                        clip: true
                                        onEditingFinished: root.setSecret(setupRow.cliId, text)
                                    }

                                    Text {
                                        x: Style.space(8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: secretEdit.text.length === 0
                                        text: "API key"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        z: -1
                                        radius: Math.max(2, Style.cornerRadius / 2)
                                        color: "transparent"
                                        border.color: Qt.alpha(setupRow.tint, 0.7)
                                        border.width: 1
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        id: histCol
                        visible: root.historyOpen
                        width: parent.width
                        spacing: Style.space(2)

                        ListView {
                            width: parent.width
                            height: Math.min(Style.space(110), Math.max(Style.space(22), contentHeight))
                            clip: true
                            model: historyModel
                            delegate: Item {
                                required property string runId
                                required property string startedAt
                                required property string preview
                                width: ListView.view.width
                                height: Style.space(22)
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.formatWhen(startedAt) + "  " + (preview || "(empty)")
                                    color: histMa.containsMouse ? root.ink : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
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
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Clear"
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
                                    clearConfirm.selectedIndex = 1
                                    root.clearConfirmOpen = true
                                }
                            }
                        }
                    }

                    Flickable {
                        id: modelMenu
                        visible: root.menuCli !== "" && !root.setupOpen && !root.historyOpen
                        width: parent.width
                        y: providerFlow.height
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

                Row {
                    width: parent.width
                    visible: !root.setupOpen && root.displayRun && root.displayRun.targets && root.displayRun.targets.length > 0
                    spacing: Style.space(8)

                    Repeater {
                        id: paper
                        model: root.displayRun ? root.displayRun.targets : []
                        delegate: Column {
                            required property var modelData
                            width: Math.max(Style.space(160), (parent.width - Style.space(8) * (paper.count - 1)) / Math.max(1, paper.count))
                            spacing: Style.space(4)

                            readonly property color tint: root.tintFor(modelData.cli)
                            readonly property string tKey: Model.targetKey(modelData.cli, modelData.model)
                            readonly property bool expanded: !!root.resultExpand[tKey]
                            readonly property string bodyText: modelData.answer !== "" ? modelData.answer
                                : (modelData.error !== "" ? modelData.error
                                    : (modelData.status === "pending" ? "Running…" : ""))

                            Rectangle {
                                width: parent.width
                                height: Style.space(3)
                                radius: 1
                                color: modelData.status === "failed" || modelData.status === "timeout"
                                    ? Color.urgent : tint
                            }

                            Row {
                                width: parent.width
                                spacing: Style.space(6)
                                Text {
                                    text: root.cliLabel(modelData.cli)
                                    color: tint
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }
                                Text {
                                    text: modelData.model !== "" ? modelData.model : "default"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                width: parent.width
                                text: Model.nerdLine(modelData)
                                color: modelData.status === "failed" || modelData.status === "timeout"
                                    ? Color.urgent : root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: bodyText
                                color: modelData.answer !== "" ? root.ink
                                    : (modelData.error !== "" ? Color.urgent : root.dim)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                wrapMode: Text.Wrap
                                maximumLineCount: expanded ? 24 : 6
                                elide: expanded ? Text.ElideNone : Text.ElideRight
                            }

                            Row {
                                spacing: Style.space(8)
                                visible: modelData.answer !== ""
                                Text {
                                    text: "copy"
                                    color: root.dim
                                    font.pixelSize: Style.font.caption
                                    font.family: root.fontFamily
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyAnswer(modelData.answer)
                                    }
                                }
                                Text {
                                    text: expanded ? "less" : "more"
                                    color: root.dim
                                    font.pixelSize: Style.font.caption
                                    font.family: root.fontFamily
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleResultExpand(tKey)
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: modelData.answer !== ""
                                text: "≈ " + Model.estimateTokens(modelData.answer) + " out"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }
                    }
                }

                Item {
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
                message: "Clear Disparchy history?"
                confirmText: "Clear"
                background: Color.popups.background
                foreground: root.ink
                selectedText: Color.accent
                fontFamily: root.fontFamily
                cornerRadius: Style.cornerRadius
                onCanceled: root.clearConfirmOpen = false
                onConfirmed: {
                    root.history = []
                    if (liveRun && Model.inFlightCount(liveRun) === 0) root.liveRun = null
                    root.viewingRunId = ""
                    root.clearConfirmOpen = false
                    root.saveHistory()
                    root.rebuildHistory()
                }
            }
        }
    }
}
