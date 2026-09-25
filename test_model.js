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
    M.parseProviderStatus("openclaw\tinstalled\tgateway\tkey:saved\nhermes\tmissing\t\tkey:none\n"),
    [
        { cli: "openclaw", installed: "installed", auth: "gateway", key: "saved" },
        { cli: "hermes", installed: "missing", auth: "", key: "none" }
    ],
    "status rows keep key:saved and key:none"
)
eq(
    M.parseProviderStatus("openclaw\tinstalled\tgateway\tkey:refused\n")[0].key,
    "refused",
    "key:refused stays refused"
)
eq(
    M.parseProviderStatus("openclaw\tinstalled\tgateway\tfixture-openclaw-key\n")[0].key,
    "none",
    "a status cell that is not key:saved or key:refused is not a key"
)
eq(
    M.keyFileNote("auth file must be mode 600"),
    "Other users can read this key's file. Replace it to fix that.",
    "loose auth file note"
)
eq(
    M.keyFileNote("auth file refused\n"),
    "Other users can read this key's file. Replace it to fix that.",
    "refused auth file note"
)
eq(M.keyFileNote("connection refused"), "", "other send errors stay raw")
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

eq(M.resultColumns(0, 5, 280, 8), 1, "width 0 gives 1")
eq(M.resultColumns(279, 5, 280, 8), 1, "width 279 gives 1")
eq(M.resultColumns(630, 0, 280, 8), 1, "0 providers gives 1")
eq(M.resultColumns(567, 5, 280, 8), 1, "one pixel under two columns gives 1")
eq(M.resultColumns(568, 5, 280, 8), 2, "exact two-column boundary gives 2")
eq(M.resultColumns(855, 5, 280, 8), 2, "one pixel under three columns gives 2")
eq(M.resultColumns(856, 5, 280, 8), 3, "exact three-column boundary gives 3")

var insets = 16
var minWidth = 680
for (var providers = 1; providers <= 5; providers++) {
    var fitted = M.panelWidth(providers, 1920, minWidth, 280, 8, insets)
    eq(M.resultColumns(fitted - insets, providers, 280, 8), Math.min(providers, 3),
        "wide screen columns for " + providers)
}
eq(M.panelWidth(0, 1920, minWidth, 280, 8, insets), 680, "0 armed stays at the Setup minimum")
eq(M.panelWidth(1, 1920, minWidth, 280, 8, insets), 680, "1 provider stays at the Setup minimum")
eq(M.panelWidth(2, 1920, minWidth, 280, 8, insets), 680, "2 providers stay at 680 with wider columns")
eq(M.panelWidth(3, 1920, minWidth, 280, 8, insets), 3 * 280 + 16 + insets, "3 providers fit three columns")
eq(M.panelWidth(5, 1920, minWidth, 280, 8, insets), 3 * 280 + 16 + insets, "5 providers still cap at three columns")
eq(M.panelWidth(3, 700, minWidth, 280, 8, insets), 700, "a 700 screen caps 3 providers")
eq(M.resultColumns(M.panelWidth(3, 700, minWidth, 280, 8, insets) - insets, 3, 280, 8), 2,
    "3 providers on a 700 screen wrap to 2")
eq(M.panelWidth(1, 400, minWidth, 280, 8, insets), 400, "a 400 screen wins over the 680 minimum")
eq(M.panelWidth(3, 400, minWidth, 280, 8, insets), 400, "3 providers on a 400 screen stay at 400")
eq(M.panelWidth(1, 3840, 1360, 560, 16, 32), 1360, "scale 2 with 1 provider is the scaled minimum")
eq(M.panelWidth(2, 3840, 1360, 560, 16, 32), 1360, "scale 2 with 2 providers stays at the minimum")
eq(M.panelWidth(3, 3840, 1360, 560, 16, 32), 3 * 560 + 32 + 32, "scale 2 with 3 providers")
eq(M.panelWidth(3, NaN, minWidth, 280, 8, insets), 3 * 280 + 16 + insets, "missing screen does not cap")
eq(M.panelWidth(3, 0, minWidth, 280, 8, insets), 3 * 280 + 16 + insets, "non-positive screen does not cap")
eq(M.panelWidth(3, -20, minWidth, 280, 8, insets), 3 * 280 + 16 + insets, "negative screen does not cap")
eq(M.panelWidth(NaN, 1920, minWidth, 280, 8, insets), 680, "non-finite provider count falls back to one")
is(isFinite(M.panelWidth(3, 1920, NaN, 280, 8, insets)), "non-finite minimum stays finite")
is(isFinite(M.panelWidth(3, 1920, minWidth, NaN, 8, insets)), "non-finite column width stays finite")
is(isFinite(M.panelWidth(3, 1920, minWidth, 280, NaN, insets)), "non-finite gap stays finite")
is(isFinite(M.panelWidth(3, 1920, minWidth, 280, 8, NaN)), "non-finite insets stay finite")
eq(M.widthCount(0, 0), 0, "no armed providers and no run")
eq(M.widthCount(1, 0), 1, "open uses the armed count when nothing is shown")
eq(M.widthCount(1, 3), 3, "a shown run widens past the armed count")
eq(M.widthCount(2, 2), 2, "a sent run uses its provider count")
eq(M.widthCount(4, 1), 4, "more armed than the shown run keeps the armed count")
eq(M.widthCount(NaN, 3), 3, "a bad armed count still follows the shown run")
eq(M.resultColumns(1136, 5, 560, 16), 2, "scale 2 width 1136 gives 2")
eq(M.resultColumns(1135, 5, 560, 16), 1, "scale 2 width 1135 gives 1")
eq(M.resultColumns(1136, 5, 0, 16), 1, "minWidth 0 falls back to 1")
eq(M.resultColumns(1136, 5, NaN, 16), 1, "minWidth NaN falls back to 1")

process.stdout.write("ok\n")
