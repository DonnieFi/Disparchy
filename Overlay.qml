import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
    id: root

    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    property var manifest: null

    property bool opened: false
    property string tab: "prompt"
    property string promptText: ""
    property string viewingRunId: ""
    property var settings: Model.defaultSettings()
    property var selection: Model.emptySelection()
    property var available: []
    property var history: []
    property var liveRun: null
    property bool historyPrimed: false
    property var pendingStarts: []

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateRoot: Model.stateDir(home, Quickshell.env("XDG_STATE_HOME"))
    readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("manifest.json"))
    readonly property string runnerPath: pluginDir + "/bin/disparchy-run"
    readonly property string historyPath: stateRoot + "/history.json"
    readonly property string selectionPath: stateRoot + "/selection.json"
    readonly property string statusPath: stateRoot + "/status.json"
    readonly property string promptPath: stateRoot + "/prompt.txt"
    readonly property string pluginKey: (manifest && manifest.id) ? manifest.id : Model.pluginId()

    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color border: Color.menu.border
    property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
    property color scrim: Color.menu.scrim
    property color selectedBackground: Color.menu.selectedBackground
    property color selectedText: Color.menu.selectedText
    readonly property int cornerRadius: Style.cornerRadius
    property string fontFamily: Style.font.menuFamily
    property int contentMargin: Style.spacing.panelPadding
    property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
    property int contentSpacing: Style.spacing.md
    property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
    property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
    property int rowHeight: Math.max(Style.spacing.popupRowHeight, Style.font.body + Style.spacing.xs)

    readonly property var displayRun: {
        if (tab === "history" && viewingRunId)
            return runById(viewingRunId)
        return liveRun
    }
    readonly property int inFlight: Model.inFlightCount(liveRun)
    readonly property var checkedClis: Model.selectedAvailable(selection, available)
    readonly property bool canSend: promptText.trim().length > 0
        && checkedClis.length > 0
        && inFlight === 0
        && !Model.promptTooLarge(promptText)
        && tab === "prompt"
        && viewingRunId === ""

    function open(payloadJson) {
        root.opened = true
        root.tab = "prompt"
        root.viewingRunId = ""
        root.promptText = ""
        root.discover()
        root.pasteClipboard()
        Qt.callLater(function () { promptEdit.forceActiveFocus() })
    }

    function close() {
        root.opened = false
    }

    function dismiss() {
        root.opened = false
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginKey)
    }

    function toggle() {
        if (root.opened) root.dismiss()
        else root.open("{}")
    }

    function runById(id) {
        for (var i = 0; i < history.length; i++) {
            if (history[i].id === id) return history[i]
        }
        return null
    }

    function pasteClipboard() {
        if (!pasteProc.running) pasteProc.running = true
    }

    function discover() {
        discoverProc.command = ["python3", root.runnerPath, "--discover"]
        if (!discoverProc.running) discoverProc.running = true
    }

    function applyDiscover(raw) {
        var next = Model.parseDiscover(raw)
        root.available = next
        if (Model.selectedAvailable(root.selection, next).length === 0 && next.length > 0) {
            var clis = []
            for (var i = 0; i < next.length; i++) clis.push(next[i].id)
            root.selection = { clis: clis, models: root.selection.models || {} }
            root.saveSelection()
        }
        rebuildTargets()
    }

    function applySettings(raw) {
        root.settings = Model.settingsFromShell(raw, root.pluginKey)
    }

    function applyHistory(raw) {
        var parsed = Model.parseHistory(raw)
        if (!root.historyPrimed) {
            var settled = Model.settleStale(parsed)
            root.historyPrimed = true
            root.history = settled
            var dirty = JSON.stringify(settled) !== JSON.stringify(parsed)
            if (dirty) root.saveHistory()
        } else {
            root.history = parsed
            if (liveRun && Model.inFlightCount(liveRun) === 0) {
                var found = runById(liveRun.id)
                if (found) root.liveRun = found
            }
        }
        rebuildHistory()
        rebuildResults()
    }

    function applySelection(raw) {
        root.selection = Model.parseSelection(raw)
        rebuildTargets()
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
            "for name in os.listdir(root):\n p=os.path.join(root, name)\n" +
            " if os.path.isfile(p): os.chmod(p, 0o600)\n",
            root.stateRoot]
        permProc.running = true
    }

    function rebuildTargets() {
        targetModel.clear()
        for (var i = 0; i < available.length; i++) {
            var cli = available[i]
            targetModel.append({
                cli: cli.id,
                label: cli.label,
                checked: Model.isChecked(root.selection, cli.id),
                modelValue: Model.modelForCli(cli.id, root.selection, root.settings)
            })
        }
    }

    function rebuildHistory() {
        historyModel.clear()
        for (var i = 0; i < history.length; i++) {
            var run = history[i]
            var chips = []
            for (var j = 0; j < run.targets.length; j++) {
                var t = run.targets[j]
                chips.push(t.cli + " " + Model.statusLabel(t.status))
            }
            historyModel.append({
                runId: run.id,
                startedAt: run.startedAt,
                preview: Model.previewPrompt(run.prompt, 90),
                chips: chips.join(" · ")
            })
        }
    }

    function rebuildResults() {
        resultModel.clear()
        var run = root.displayRun
        if (!run) return
        for (var i = 0; i < run.targets.length; i++) {
            var t = run.targets[i]
            resultModel.append({
                cli: t.cli,
                model: t.model,
                status: t.status,
                elapsedMs: t.elapsedMs,
                answer: t.answer,
                error: t.error,
                preview: t.status === "done"
                    ? Model.previewPrompt(t.answer, 140)
                    : Model.previewPrompt(t.error, 140)
            })
        }
    }

    function toggleTarget(cli) {
        var on = !Model.isChecked(root.selection, cli)
        root.selection = Model.toggleCli(root.selection, cli, on)
        root.saveSelection()
        rebuildTargets()
    }

    function editModel(cli, value) {
        root.selection = Model.setModel(root.selection, cli, value)
        root.saveSelection()
    }

    function send() {
        if (!root.canSend) return
        var clis = root.checkedClis
        var targets = []
        for (var i = 0; i < clis.length; i++) {
            targets.push({
                cli: clis[i],
                model: Model.modelForCli(clis[i], root.selection, root.settings),
                status: "pending",
                elapsedMs: 0,
                answer: "",
                error: ""
            })
        }
        var run = {
            id: Model.newRunId(),
            startedAt: Model.isoNow(),
            prompt: root.promptText,
            targets: targets
        }
        root.liveRun = run
        root.history = Model.upsertRun(root.history, run, root.settings.historyMaxRuns)
        root.saveHistory()
        promptFile.setText(root.promptText)
        root.tightenPerms()
        root.pendingStarts = targets
        startTimer.restart()
        root.saveStatus()
        rebuildResults()
        rebuildHistory()
    }

    function startTarget(cli, model) {
        var proc = runnerFor(cli)
        if (!proc || proc.running) return
        proc.runId = liveRun ? liveRun.id : ""
        proc.startedMs = Date.now()
        proc.command = ["python3", root.runnerPath,
            "--cli", cli,
            "--model", model || "",
            "--timeout", String(root.settings.timeoutSec),
            "--prompt-file", root.promptPath]
        proc.running = true
    }

    function runnerFor(cli) {
        if (cli === "claude") return runClaude
        if (cli === "codex") return runCodex
        if (cli === "grok") return runGrok
        if (cli === "gemini") return runGemini
        if (cli === "cursor") return runCursor
        return null
    }

    function onTargetExited(cli, code, stdout, stderr, startedMs, runId) {
        if (!liveRun || liveRun.id !== runId) return
        var elapsed = Math.max(0, Date.now() - startedMs)
        var status = "failed"
        var answer = String(stdout || "")
        var error = String(stderr || "").trim()
        if (code === 0) {
            status = "done"
            error = ""
        } else if (code === 124 || error === "timeout") {
            status = "timeout"
            error = error || "timeout"
        }
        var updated = Model.updateTarget(liveRun, cli, {
            status: status,
            elapsedMs: elapsed,
            answer: answer,
            error: error
        })
        root.liveRun = updated
        root.history = Model.upsertRun(root.history, updated, root.settings.historyMaxRuns)
        root.saveHistory()
        root.saveStatus()
        rebuildResults()
        rebuildHistory()
        if (Model.inFlightCount(updated) === 0)
            root.notifyDone(updated)
    }

    function notifyDone(run) {
        var summary = Model.settleSummary(run)
        Quickshell.execDetached(["notify-send", "--app-name=Disparchy", "Disparchy", summary])
    }

    function copyAnswer(row) {
        if (!row || row.status !== "done" || !row.answer) return
        Quickshell.execDetached(["wl-copy", "--", row.answer])
    }

    function openHistoryRun(id) {
        root.tab = "history"
        root.viewingRunId = id
        rebuildResults()
    }

    function backToHistory() {
        root.viewingRunId = ""
        rebuildResults()
    }

    function requestClearHistory() {
        if (history.length === 0) return
        clearConfirm.selectedIndex = 1
        root.clearConfirmOpen = true
    }

    function cancelClearHistory() {
        root.clearConfirmOpen = false
    }

    function confirmClearHistory() {
        root.history = []
        if (liveRun && Model.inFlightCount(liveRun) === 0) root.liveRun = null
        root.viewingRunId = ""
        root.clearConfirmOpen = false
        root.saveHistory()
        rebuildHistory()
        rebuildResults()
    }

    property bool clearConfirmOpen: false

    onDisplayRunChanged: rebuildResults()
    onInFlightChanged: saveStatus()
    onTabChanged: {
        if (tab === "prompt")
            Qt.callLater(function () { promptEdit.forceActiveFocus() })
        else
            Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }

    Component.onCompleted: {
        mkdirProc.command = ["python3", "-c",
            "import os,sys\np=sys.argv[1]\nos.makedirs(p, exist_ok=True)\nos.chmod(p, 0o700)",
            root.stateRoot]
        mkdirProc.running = true
        root.discover()
        root.tightenPerms()
    }

    ListModel { id: targetModel }
    ListModel { id: resultModel }
    ListModel { id: historyModel }

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

    FileView {
        path: root.home + "/.config/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.applySettings(text())
        onLoadFailed: root.applySettings("{}")
        onFileChanged: reload()
    }

    Timer {
        id: startTimer
        interval: 40
        repeat: false
        onTriggered: {
            var jobs = root.pendingStarts || []
            root.pendingStarts = []
            for (var i = 0; i < jobs.length; i++)
                root.startTarget(jobs[i].cli, jobs[i].model)
        }
    }

    Process {
        id: mkdirProc
    }

    Process {
        id: permProc
    }

    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = String(text || "")
                if (t && root.promptText === "") root.promptText = t
            }
        }
    }

    Process {
        id: discoverProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyDiscover(text)
        }
    }

    component TargetProc: Process {
        property string cliName: ""
        property string runId: ""
        property double startedMs: 0
        stdout: StdioCollector { id: so; waitForEnd: true }
        stderr: StdioCollector { id: se; waitForEnd: true }
        onExited: function (code) {
            var out = so.text
            var err = se.text
            var cli = cliName
            var started = startedMs
            var id = runId
            Qt.callLater(function () {
                root.onTargetExited(cli, code, out, err, started, id)
            })
        }
    }

    TargetProc { id: runClaude; cliName: "claude" }
    TargetProc { id: runCodex; cliName: "codex" }
    TargetProc { id: runGrok; cliName: "grok" }
    TargetProc { id: runGemini; cliName: "gemini" }
    TargetProc { id: runCursor; cliName: "cursor" }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "disparchy"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            color: root.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        BorderSurface {
            id: card
            width: root.cardWidth
            height: root.cardHeight
            radius: root.cornerRadius
            anchors.centerIn: parent
            color: root.background
            borderSpec: root.borderSpec
            padding: root.contentMargin

            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
                id: keyCatcher
                anchors.fill: parent
                z: root.clearConfirmOpen ? 20 : 0
                focus: true

                Keys.onPressed: function (event) {
                    if (root.clearConfirmOpen) {
                        if (clearConfirm.handleKey(event)) event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Escape) {
                        if (root.tab === "history" && root.viewingRunId) root.backToHistory()
                        else root.dismiss()
                        event.accepted = true
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                spacing: root.contentSpacing

                Item {
                    width: parent.width
                    height: root.headerHeight

                    ButtonGroup {
                        id: tabs
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        foreground: root.foreground
                        background: root.background
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        options: [
                            { value: "prompt", label: "Prompt" },
                            { value: "history", label: "History" }
                        ]
                        value: root.tab
                        onChanged: function (value) {
                            root.tab = value
                            if (value === "prompt") root.viewingRunId = ""
                            root.rebuildResults()
                        }
                    }

                    Button {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.tab === "history" && root.viewingRunId === ""
                        text: "Clear"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        enabled: historyModel.count > 0
                        onClicked: root.requestClearHistory()
                    }

                    Button {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.tab === "history" && root.viewingRunId !== ""
                        text: "Back"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        onClicked: root.backToHistory()
                    }
                }

                Item {
                    width: parent.width
                    height: visible ? parent.height - root.headerHeight - root.contentSpacing : 0
                    visible: root.tab === "prompt"

                    Column {
                        id: promptTop
                        width: parent.width
                        spacing: root.contentSpacing

                        BorderSurface {
                            width: parent.width
                            height: Style.space(110)
                            radius: root.cornerRadius
                            color: Style.controlFill(promptEdit.activeFocus, false, root.foreground, Color.accent)
                            borderSpec: Border.controlSpec(promptEdit.activeFocus ? "focus" : "normal", root.foreground, Color.accent)

                            Text {
                                visible: root.promptText.length === 0
                                anchors.fill: parent
                                anchors.margins: Style.spacing.controlPaddingX
                                text: "paste or type a prompt"
                                color: root.foreground
                                opacity: 0.45
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                wrapMode: Text.Wrap
                            }

                            TextEdit {
                                id: promptEdit
                                anchors.fill: parent
                                anchors.margins: Style.spacing.controlPaddingX
                                text: root.promptText
                                onTextChanged: root.promptText = text
                                wrapMode: TextEdit.Wrap
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                                selectedTextColor: root.foreground
                                Keys.onPressed: function (event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.dismiss()
                                        event.accepted = true
                                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                               && (event.modifiers & Qt.ControlModifier)) {
                                        root.send()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            visible: Model.promptTooLarge(root.promptText)
                            textFormat: Text.PlainText
                            text: "Prompt exceeds 32KiB cap"
                            color: Color.urgent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        Flow {
                            width: parent.width
                            spacing: Style.spacing.sm

                            Repeater {
                                model: targetModel
                                delegate: Row {
                                    required property string cli
                                    required property string label
                                    required property var checked
                                    required property string modelValue
                                    spacing: Style.space(4)

                                    Button {
                                        text: (checked ? "✓ " : "") + label
                                        selected: checked
                                        foreground: root.foreground
                                        accent: Color.accent
                                        fontFamily: root.fontFamily
                                        onClicked: root.toggleTarget(cli)
                                    }

                                    TextField {
                                        width: Style.space(120)
                                        text: modelValue
                                        placeholderText: "model"
                                        foreground: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        onEditingFinished: root.editModel(cli, text)
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            visible: available.length === 0
                            textFormat: Text.PlainText
                            text: "No local AI CLIs on PATH"
                            color: root.foreground
                            opacity: 0.6
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        Row {
                            spacing: Style.spacing.md

                            Button {
                                text: "Send"
                                enabled: root.canSend
                                selected: root.canSend
                                foreground: root.foreground
                                accent: Color.accent
                                fontFamily: root.fontFamily
                                onClicked: root.send()
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: root.inFlight > 0
                                    ? (root.inFlight + " in flight")
                                    : (root.canSend ? "Ctrl+Enter" : "")
                                color: root.foreground
                                opacity: 0.55
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }
                    }

                    ListView {
                        id: resultList
                        anchors.top: promptTop.bottom
                        anchors.topMargin: root.contentSpacing
                        anchors.bottom: parent.bottom
                        width: parent.width
                        clip: true
                        model: resultModel
                        spacing: Style.space(4)
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: resultDelegate
                    }
                }

                // History list
                ListView {
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing
                    visible: root.tab === "history" && root.viewingRunId === ""
                    clip: true
                    model: historyModel
                    spacing: Style.space(4)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property string runId
                        required property string startedAt
                        required property string preview
                        required property string chips
                        width: ListView.view.width
                        height: Math.max(root.rowHeight * 2, Style.space(48))
                        radius: root.cornerRadius
                        color: historyHover.containsMouse ? root.selectedBackground : "transparent"

                        Column {
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.rowPaddingX / 2
                            anchors.rightMargin: Style.spacing.rowPaddingX / 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.spacing.xxs

                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: preview || "(empty prompt)"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: chips
                                color: root.foreground
                                opacity: 0.55
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: historyHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openHistoryRun(runId)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: historyModel.count === 0
                        textFormat: Text.PlainText
                        text: "No runs yet"
                        color: root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }
                }

                // History run (read-only results)
                ListView {
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing
                    visible: root.tab === "history" && root.viewingRunId !== ""
                    clip: true
                    model: resultModel
                    spacing: Style.space(4)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: resultDelegate
                }
            }

            ConfirmDialog {
                id: clearConfirm
                anchors.fill: parent
                opened: root.clearConfirmOpen
                z: 30
                message: "Clear Disparchy history?"
                confirmText: "Clear"
                background: root.background
                foreground: root.foreground
                scrim: root.scrim
                selectedBackground: root.selectedBackground
                selectedText: root.selectedText
                fontFamily: root.fontFamily
                cornerRadius: root.cornerRadius
                onCanceled: root.cancelClearHistory()
                onConfirmed: root.confirmClearHistory()
            }
        }
    }

    Component {
        id: resultDelegate
        Rectangle {
            required property string cli
            required property string model
            required property string status
            required property var elapsedMs
            required property string answer
            required property string error
            required property string preview
            width: ListView.view ? ListView.view.width : root.cardWidth
            height: Math.max(root.rowHeight * 2, Style.space(44))
            radius: root.cornerRadius
            color: rowHover.containsMouse && status === "done" ? root.selectedBackground : "transparent"

            readonly property color statusColor: status === "done"
                ? Color.accent
                : (status === "pending" ? root.foreground : Color.urgent)

            Column {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX / 2
                anchors.rightMargin: Style.spacing.rowPaddingX / 2
                spacing: Style.spacing.xxs

                Row {
                    spacing: Style.spacing.sm
                    width: parent.width

                    Text {
                        textFormat: Text.PlainText
                        text: cli + (model ? " · " + model : "")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: Model.statusLabel(status)
                        color: statusColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        visible: elapsedMs > 0
                        textFormat: Text.PlainText
                        text: Model.formatElapsed(elapsedMs)
                        color: root.foreground
                        opacity: 0.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: preview || (status === "pending" ? "…" : "")
                    color: root.foreground
                    opacity: status === "done" ? 0.85 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: status === "done" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.copyAnswer({ status: status, answer: answer })
            }
        }
    }
}
