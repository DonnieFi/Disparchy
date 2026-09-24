const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "Model.js"), "utf8")
const M = {}
vm.createContext(M)
vm.runInContext(src, M)

function eq(actual, expected, name) {
    const a = JSON.stringify(actual)
    const e = JSON.stringify(expected)
    if (a !== e) throw new Error(name + " expected " + e + " got " + a)
}

function is(cond, name) {
    if (!cond) throw new Error(name)
}

const available = [
    { id: "claude", label: "Claude", defaultModel: "sonnet" },
    { id: "codex", label: "Codex", defaultModel: "" },
    { id: "grok", label: "Grok", defaultModel: "" }
]

eq(M.emptySelection(), { models: {} }, "emptySelection")

eq(
    M.parseSelection('{"models":{"claude":"sonnet","codex":""}}'),
    { models: { claude: ["sonnet"], codex: [""] } },
    "legacy string parse"
)

eq(
    M.parseSelection('{"models":{"claude":["opus","sonnet","opus"],"mystery":["x"]}}'),
    { models: { claude: ["opus", "sonnet"] } },
    "array parse drops unknown and dedupes"
)

eq(
    M.parseSelection('{"clis":["claude"],"models":{"claude":"opus","grok":"grok-4.6"}}'),
    { models: { claude: ["opus"] } },
    "legacy clis filter drops unlisted"
)

eq(
    M.parseSelection('{"clis":["claude","not-a-cli"]}'),
    { models: { claude: [""] } },
    "legacy clis without models seeds empty string"
)

eq(
    M.parseSelection('{"clis":[],"models":{"grok":["grok-4.6"]}}'),
    { models: { grok: ["grok-4.6"] } },
    "empty clis is not a filter"
)

eq(M.parseSelection("not-json"), { models: {} }, "invalid json")

const wire = M.serializeSelection({
    clis: ["claude"],
    models: { claude: ["sonnet", "opus"], grok: [], mystery: ["x"] }
})
const written = JSON.parse(wire)
eq(written, { models: { claude: ["sonnet", "opus"] } }, "serialize omits clis and empty")
is(!Object.prototype.hasOwnProperty.call(written, "clis"), "serialize has no clis key")
is(wire.endsWith("\n"), "serialize trailing newline")

const start = { models: { claude: ["sonnet"] } }
eq(
    M.toggleModel(start, "claude", "opus"),
    { models: { claude: ["sonnet", "opus"] } },
    "toggle adds"
)
eq(start, { models: { claude: ["sonnet"] } }, "toggle does not mutate input")
eq(
    M.toggleModel({ models: { claude: ["sonnet", "opus"] } }, "claude", "sonnet"),
    { models: { claude: ["opus"] } },
    "toggle removes one"
)
eq(
    M.toggleModel({ models: { claude: ["opus"] } }, "claude", "opus"),
    { models: {} },
    "last-off deletes key"
)
eq(
    M.toggleModel({ models: { claude: ["sonnet"] } }, "claude", "opus", true),
    { models: { claude: ["sonnet", "opus"] } },
    "toggle on"
)
eq(
    M.toggleModel({ models: { claude: ["sonnet"] } }, "claude", "sonnet", false),
    { models: {} },
    "toggle off"
)
eq(
    M.toggleModel({ models: { claude: ["sonnet"] } }, "claude", "sonnet", true),
    { models: { claude: ["sonnet"] } },
    "toggle on is idempotent"
)

is(M.isArmed({ models: { claude: ["sonnet"] } }, "claude") === true, "isArmed true")
is(M.isChecked({ models: { claude: ["sonnet"] } }, "claude") === true, "isChecked alias")
is(M.isArmed({ models: {} }, "claude") === false, "isArmed false")
is(M.modelsChecked({ models: { claude: ["", "opus"] } }, "claude", "") === true, "empty model is checkable")
is(M.modelsChecked({ models: { claude: ["opus"] } }, "claude", "sonnet") === false, "modelsChecked miss")

const jobs = M.expandJobs(
    { models: { claude: ["sonnet", "opus"], grok: [""], cursor: ["auto"] } },
    available
)
eq(
    jobs.map(function (j) { return { cli: j.cli, model: j.model } }),
    [
        { cli: "claude", model: "sonnet" },
        { cli: "claude", model: "opus" },
        { cli: "grok", model: "" }
    ],
    "expandJobs multi-model available order skips missing PATH"
)
eq(jobs[2].key, M.targetKey("grok", ""), "expandJobs empty model key")

const run = {
    id: "r1",
    startedAt: "t",
    prompt: "hi",
    targets: [
        { cli: "claude", model: "sonnet", status: "pending", elapsedMs: 0, answer: "", error: "", exitCode: "", stdoutBytes: 0, stderrBytes: 0 },
        { cli: "claude", model: "opus", status: "pending", elapsedMs: 0, answer: "", error: "", exitCode: "", stdoutBytes: 0, stderrBytes: 0 }
    ]
}
const patched = M.updateTarget(run, "claude", "opus", { status: "done", answer: "ok", elapsedMs: 12 })
eq(patched.targets[0].status, "pending", "updateTarget leaves sibling")
eq(patched.targets[1].status, "done", "updateTarget matches pair")
eq(patched.targets[1].answer, "ok", "updateTarget patch answer")
eq(patched.targets[1].model, "opus", "updateTarget keeps identity")
const missed = M.updateTarget(run, "claude", "haiku", { status: "done" })
is(missed === run, "updateTarget no match returns same run")
const oldCall = M.updateTarget(run, "claude", { status: "done" })
is(oldCall === run, "updateTarget cli-only call does not smash")

eq(
    M.claimNext(run, {}),
    { cli: "claude", model: "sonnet", key: M.targetKey("claude", "sonnet") },
    "claimNext first pending"
)
eq(
    M.claimNext(run, { [M.targetKey("claude", "sonnet")]: true }),
    { cli: "claude", model: "opus", key: M.targetKey("claude", "opus") },
    "claimNext skips object runningKeys"
)
eq(
    M.claimNext(run, new Set([M.targetKey("claude", "sonnet"), M.targetKey("claude", "opus")])),
    null,
    "claimNext exhausted Set"
)
const mixed = {
    id: "r2",
    targets: [
        { cli: "grok", model: "", status: "done" },
        { cli: "claude", model: "sonnet", status: "pending" }
    ]
}
eq(
    M.claimNext(mixed, {}),
    { cli: "claude", model: "sonnet", key: M.targetKey("claude", "sonnet") },
    "claimNext skips non-pending"
)

eq(
    M.seedIfEmpty({ models: {} }, available, { modelClaude: "haiku" }),
    { models: { claude: ["haiku"], codex: [""], grok: [""] } },
    "seedIfEmpty fills available"
)
eq(
    M.seedIfEmpty({ models: { claude: ["opus"] } }, available, { modelClaude: "haiku" }),
    { models: { claude: ["opus"] } },
    "seedIfEmpty no-op when available is armed"
)
eq(
    M.seedIfEmpty({ models: { cursor: ["auto"] } }, available, { modelClaude: "sonnet" }),
    { models: { cursor: ["auto"], claude: ["sonnet"], codex: [""], grok: [""] } },
    "seedIfEmpty when armed cli is not available"
)

const created = M.newRun("hello", [
    { cli: "claude", model: "sonnet" },
    { cli: "claude", model: "" }
])
is(typeof created.id === "string" && created.id.length > 0, "newRun id")
is(typeof created.startedAt === "string" && created.startedAt.length > 0, "newRun startedAt")
eq(created.prompt, "hello", "newRun prompt")
eq(
    created.targets,
    [
        { cli: "claude", model: "sonnet", status: "pending", elapsedMs: 0, answer: "", error: "", exitCode: "", stdoutBytes: 0, stderrBytes: 0 },
        { cli: "claude", model: "", status: "pending", elapsedMs: 0, answer: "", error: "", exitCode: "", stdoutBytes: 0, stderrBytes: 0 }
    ],
    "newRun pending targets"
)

eq(M.targetKey("claude", "sonnet"), "claude\x1fsonnet", "targetKey")
eq(M.jobKey("claude", ""), "claude\x1f", "jobKey empty model")
eq(M.statusFromExit(0, ""), "done", "statusFromExit done")
eq(M.statusFromExit(124, ""), "timeout", "statusFromExit timeout code")
eq(M.statusFromExit(1, "timeout"), "timeout", "statusFromExit timeout stderr")
eq(M.statusFromExit(1, "boom"), "failed", "statusFromExit failed")

is(M.isEnabled({ models: {} }, "claude") === true, "builtin claude shown")
is(M.isEnabled({ models: {} }, "ollama") === false, "ollama hidden until enabled")
eq(
    M.toggleEnabled({ models: { claude: ["sonnet"] } }, "ollama", true).enabled,
    ["claude", "codex", "grok", "antigravity", "cursor", "ollama"],
    "toggleEnabled keeps the builtin five"
)
eq(
    M.endpointFor({ models: {} }, "ollama"),
    "http://127.0.0.1:11434",
    "ollama default endpoint"
)
eq(
    M.setEndpoint({ models: {} }, "ollama", "http://10.0.0.8:11434").endpoints.ollama,
    "http://10.0.0.8:11434",
    "setEndpoint stores a url"
)
eq(M.modelsFor("codex").length, 1, "codex waits for a live catalog")
eq(M.modelsFor("hermes")[0].label, "Hermes default", "hermes names its default")
eq(
    M.modelsFor("codex", [{ value: "gpt-6-sol", label: "GPT-6-Sol" }])[1],
    { value: "gpt-6-sol", label: "GPT-6-Sol" },
    "live catalog replaces the stale list"
)
eq(M.setEndpoint({ models: {} }, "claude", "http://nope").endpoints, undefined, "cli ignores endpoint")
eq(
    M.endpointFor({ models: {} }, "openclaw"),
    "http://127.0.0.1:18789",
    "openclaw default endpoint"
)
eq(
    M.setSecret({}, "openclaw", "sekret").openclaw,
    "sekret",
    "setSecret stores a key"
)
eq(M.setSecret({ openclaw: "sekret" }, "openclaw", ""), {}, "setSecret clears a blank key")
eq(M.setSecret({}, "claude", "sekret"), {}, "claude has no api key line")
eq(M.secretFor({ openclaw: "sekret" }, "claude"), "", "secretFor ignores other clis")
is(M.serializeSelection({ models: {} }).indexOf("sekret") < 0, "selection json has no api key")
eq(M.setAutoPaste({ models: {} }, true), { models: {}, autoPaste: true }, "autoPaste on")
eq(M.setAutoPaste({ models: {}, autoPaste: true }, false), { models: {} }, "autoPaste off")
eq(
    M.toggleCli(M.setAutoPaste({ models: {} }, true), "claude", true, {}),
    { models: { claude: ["sonnet"] }, autoPaste: true },
    "toggleCli keeps autoPaste"
)
eq(
    M.parseSelection('{"models":{},"autoPaste":true}'),
    { models: {}, autoPaste: true },
    "parse autoPaste"
)
eq(M.estimateTokens(""), 0, "empty text is zero tokens")
eq(M.estimateTokens("hello"), 2, "five chars round up to two tokens")
eq(
    M.markdownForDisplay("**bold** ![chart](https://example.com/chart.png) <IMG src='file:///tmp/p'>"),
    "**bold** [chart](https://example.com/chart.png) &lt;img src='file:///tmp/p'>",
    "answer formatting keeps markdown without image loads"
)
eq(M.markdownForDisplay("![logo][asset]\n[asset]: https://example.com/logo.svg"),
    "[logo][asset]\n[asset]: https://example.com/logo.svg", "reference images become links")
eq(M.externalLinkForDisplay("HTTPS://example.com/x"), "HTTPS://example.com/x", "web links open")
eq(M.externalLinkForDisplay("file:///tmp/secret"), "", "local links do not open")
eq(
    M.runTokens({
        prompt: "hello",
        targets: [
            { answer: "12345678" },
            { answer: "" }
        ]
    }),
    { prompt: 2, answers: 2, total: 4 },
    "run tokens add prompt and answers"
)
eq(
    M.historyTokens([
        { prompt: "hello", targets: [{ answer: "12345678" }] },
        { prompt: "abcd", targets: [{ answer: "abcd" }] }
    ]),
    { prompt: 3, answers: 3, total: 6 },
    "history tokens sum every saved run"
)
eq(
    M.tokenFooter(
        { prompt: "hello", targets: [{ answer: "12345678" }] },
        [{ prompt: "hello", targets: [{ answer: "12345678" }] }]
    ),
    "in 2  ·  out 2  ·  ≈ 4 this run  ·  ≈ 4 saved",
    "token footer"
)

const listed = M.cliList()
const commandGroup = M.setupGroup(false)
const endpointGroup = M.setupGroup(true)
is(commandGroup.length > 0, "command-line group is non-empty")
is(endpointGroup.length > 0, "endpoint group is non-empty")
is(commandGroup.length + endpointGroup.length === listed.length, "group sizes sum to cliList length")
const seen = {}
function checkGroup(group, want) {
    var prev = -1
    for (var i = 0; i < group.length; i++) {
        var id = group[i].id
        var at = -1
        for (var j = 0; j < listed.length; j++)
            if (listed[j].id === id) at = j
        is(M.needsEndpoint(id) === want, "group matches needsEndpoint")
        is(at > prev, "group keeps cliList order")
        prev = at
        seen[id] = (seen[id] || 0) + 1
    }
}
checkGroup(commandGroup, false)
checkGroup(endpointGroup, true)
for (var n = 0; n < listed.length; n++)
    is(seen[listed[n].id] === 1, "every entry lands in exactly one group")

eq(M.escapeTarget(false, false), "panel", "escape closes the panel")
eq(M.escapeTarget(false, true), "menu", "escape closes the menu first")
eq(M.escapeTarget(true, false), "confirm", "escape cancels confirm before the panel")
eq(M.escapeTarget(true, true), "confirm", "escape cancels confirm before the menu")

eq(M.resultColumns(0, 5), 1, "width 0 gives 1")
eq(M.resultColumns(279, 5), 1, "width 279 gives 1")
eq(M.resultColumns(630, 0), 1, "0 providers gives 1")
eq(M.resultColumns(567, 5), 1, "one pixel under two columns gives 1")
eq(M.resultColumns(568, 5), 2, "exact two-column boundary gives 2")
eq(M.resultColumns(855, 5), 2, "one pixel under three columns gives 2")
eq(M.resultColumns(856, 5), 3, "exact three-column boundary gives 3")

// hangWidth while a run is showing, spacing scale 1:
// max(520, min(960, 210 * n))
function hangWidth(providers) {
    var n = Math.max(1, providers)
    return Math.max(520, Math.min(960, 210 * n))
}
eq(hangWidth(1), 520, "1 provider panel is 520")
eq(hangWidth(2), 520, "2 provider panel is 520")
eq(hangWidth(3), 630, "3 provider panel is 630")
eq(hangWidth(4), 840, "4 provider panel is 840")
eq(hangWidth(5), 960, "5 provider panel is 960")
eq(M.resultColumns(hangWidth(1), 1), 1, "1 provider at 520 gives 1")
eq(M.resultColumns(hangWidth(2), 2), 1, "2 providers at 520 gives 1")
eq(M.resultColumns(hangWidth(3), 3), 2, "3 providers at 630 gives 2")
eq(M.resultColumns(hangWidth(4), 4), 2, "4 providers at 840 gives 2")
eq(M.resultColumns(hangWidth(5), 5), 3, "5 providers at 960 gives 3")

process.stdout.write("ok\n")
