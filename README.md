<div align="center">

<img src="docs/screenshots/ask-0.3.1.png" width="720" alt="Disparchy hangdown: one prompt, three checked providers, and a colored answer column for each">

# Disparchy

**One prompt. The checked providers answer together.**

Type a line in the bar. Disparchy sends it to the local CLIs you armed and puts each answer in its own column.

[![Omarchy](https://img.shields.io/badge/Omarchy-plugin-00d3f2?style=flat-square)](https://omarchy.org)
[![Quickshell](https://img.shields.io/badge/Quickshell-QML-5e81ac?style=flat-square)](https://quickshell.org)
[![Version](https://img.shields.io/badge/version-0.3.1-4fc9d6?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-a3be8c?style=flat-square)](LICENSE)

Plugin id: `dkfiander.disparchy` · Install: `~/.config/omarchy/plugins/dkfiander.disparchy/`  
Repo: [DonnieFi/Disparchy](https://github.com/DonnieFi/Disparchy) · Architecture: [`docs/architecture.md`](docs/architecture.md)

</div>

---

## The idea

You keep one prompt. Each checked provider runs on its own, with its own model, and a failure in one column leaves the others running.

| Provider | Talks to | Default |
|----------|----------|---------|
| **Claude** | `claude` | `sonnet` |
| **Codex** | `codex exec` | CLI default |
| **Grok** | `grok` | CLI default |
| **Antigravity** | `agy` | CLI default |
| **Cursor** | `cursor-agent` | CLI default |
| **OpenClaw** | gateway on port 18789, or the local node. An API key uses `POST /v1/chat/completions` | CLI default, or `openclaw/default` with a key |
| **Hermes** | `hermes chat --oneshot`. An API key uses `POST /v1/chat/completions` | Hermes default, or `hermes-agent` with a key |
| **Ollama** | `http://127.0.0.1:11434` | URL editable in **Setup** |
| **LM Studio** | `http://127.0.0.1:1234` | URL editable in **Setup** |

The first five sit on the bar until you change that in **Setup**. Model lists come from each CLI when you open the panel. Token counts at the bottom of a column, and in the footer, estimate tokens as the character count divided by 4, rounded up.

<div align="center">
<img src="docs/screenshots/setup-0.3.1.png" width="640" alt="Disparchy Setup: provider rows with sign-in status, enable switches, and HTTP URL fields">
</div>

**Setup** is where a provider joins the bar. The status word opens that CLI. Ollama and LM Studio take a URL on the same row.

<div align="center">
<img src="docs/screenshots/bar-icon-0.3.1.png" width="160" alt="Disparchy bar mark, a small bar-chart glyph with the active underline">
</div>

---

## Install

Plugins run **unsandboxed** inside your long-lived `omarchy-shell` process. Only add repos you trust. Read the QML and `bin/` before you enable this one ([Omarchy shell plugins](https://omarchy.org)).

```bash
omarchy plugin add https://github.com/DonnieFi/Disparchy.git --enable
omarchy bar move dkfiander.disparchy --section right
```

Dev symlink, when this checkout is the plugin root:

```bash
ln -sfn /path/to/Disparchy ~/.config/omarchy/plugins/dkfiander.disparchy
omarchy-shell shell rescanPlugins
omarchy plugin enable dkfiander.disparchy
```

Validate:

```bash
omarchy plugin validate .
# or
omarchy plugin validate ~/.config/omarchy/plugins/dkfiander.disparchy
```

Open:

```bash
omarchy-shell shell summon dkfiander.disparchy '{}'
```

QML changes need a shell restart. The runner is a new Python process on each send, so `bin/disparchy-run` updates without one.

```bash
omarchy restart shell
```

A locked session refuses that restart.

Optional key. The plugin does not write this for you. Put it in `~/.config/hypr/bindings.lua`. Super+Shift+M is Omarchy's Music key, so Disparchy uses A. If A is already ChatGPT, unbind it first.

```lua
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Disparchy", "omarchy-shell shell toggle dkfiander.disparchy '{}'")
```

---

## Usage

| Action | How |
|--------|-----|
| Open or close | Click the bar-chart icon, or Super+Shift+A if you added the bind. Esc closes |
| Ask | Type a prompt. Enter or **Send** |
| Arm a provider | Check its box. The arrow opens the model list |
| Setup | **Setup** shows or hides providers on the bar. Click the status word to sign in |
| History | **History** lists past runs. **Back** returns to the prompt |
| Paste | **Paste** fills an empty prompt from the clipboard when you open the panel. Off until you turn it on |
| Clear | **Clear** empties the prompt and hides the current answers. Dim when there is nothing to clear |
| Cancel | **Cancel** shows while a run is in flight. Pending columns become `cancelled` |

A checkbox arms that provider for the next send. **Setup** decides whether the provider appears on the row at all. HTTP rows stay available when enabled, even if the server is down.

Status words on a **Setup** row:

| Word | Meaning |
|------|---------|
| **install** | CLI is not on `PATH` |
| **sign in** | CLI is installed and the local probe says signed out |
| **open** | CLI is ready. Click to launch it |
| **gateway** | OpenClaw's gateway on `127.0.0.1:18789` answered |
| **local node** | OpenClaw is installed and the gateway is down |
| **reachable** | Ollama or LM Studio answered |
| **endpoint down** | The HTTP URL did not answer |

Sign-in opens a held terminal, `xdg-terminal-exec`, with that CLI's login command. HTTP rows have no login launch.

The header pill reads **IDLE**, **N ARMED**, **SETUP**, **N RUNNING**, or **N SAVED**.

The footer reads `in N · out N · ≈ N this run · ≈ N saved`. Each column ends with `≈ N out`.

---

## Configure

Bar-widget settings, also stored in `shell.json` under the widget entry:

| Key | Default | Notes |
|-----|---------|-------|
| `timeoutSec` | `90` | 15–300, per provider |
| `historyMaxRuns` | `50` | 10–200 |
| `modelClaude` | `sonnet` | Used when you have not picked a model |
| `modelCodex` | empty | Empty means the CLI default |
| `modelGrok` | empty | Empty means the CLI default |
| `modelAntigravity` | empty | Empty means the CLI default |
| `modelCursor` | empty | Empty means the CLI default |

Which providers are on the bar, which models you picked, and whether **Paste** is on, live in `selection.json`. That file is not in the widget schema.

Runtime state lives under `$XDG_STATE_HOME/omarchy/dkfiander.disparchy/`. When that variable is unset, the directory is `~/.local/state/omarchy/dkfiander.disparchy/`. The directory is mode `0700`. Files are mode `0600`. Nothing here is written into the plugin tree, because the shell watches that tree and reloads on every write.

| File | Purpose |
|------|---------|
| `selection.json` | Armed models, enabled providers, HTTP URLs, `autoPaste` |
| `auth.json` | API keys for OpenClaw and Hermes. Mode `0600`. Never written into the plugin tree |
| `history.json` | Past runs |
| `prompt.txt` | The prompt file each send reads |
| `status.json` | Last provider probe. Rewritten by the panel |

---

## Remove

```bash
omarchy plugin remove dkfiander.disparchy
```

That disables and removes the plugin checkout or symlink. Runtime state under `~/.local/state/omarchy/dkfiander.disparchy/` is left alone. Delete that directory if you want a clean slate.

---

## Dependencies

| Need | Required? | Notes |
|------|-----------|-------|
| Omarchy 4 / Quattro + Quickshell | yes | Bar widget host |
| Python 3 | yes | `bin/disparchy-run`, stdlib only |
| `wl-paste` and `wl-copy` | for **Paste** and **copy** | Text clipboard |
| `claude`, `codex`, `grok`, `agy`, `cursor-agent` | optional | Each one you want on the row |
| `openclaw` | optional | Gateway on port 18789, otherwise the local node |
| `hermes` | optional | Must already be the real CLI. A stub installer at that name will run on **Send** |
| Ollama or LM Studio | optional | HTTP. Defaults above |

Missing CLIs show as **install**. They are not send errors.

---

## IPC

Target **`dkfiander.disparchy`**.

```bash
omarchy-shell shell summon dkfiander.disparchy '{}'
omarchy-shell shell hide dkfiander.disparchy
omarchy-shell dkfiander.disparchy open
omarchy-shell dkfiander.disparchy close
omarchy-shell dkfiander.disparchy toggle
```

The panel does not register a second IPC handler. Open, close, show, hide, and toggle are on the bar widget.

---

## How it works

```text
prompt.txt  ──►  disparchy-run --cli … --prompt-file …
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
   local CLIs     HTTP POST     OpenClaw
                      │
                      ▼
              one column each
```

Up to six providers run at once. A seventh waits for a free slot. **Cancel** stops the queue. Columns already running finish or time out on their own.

The runner never passes `--force`, `--yolo`, `--always-approve`, or `--dangerously-skip-permissions`. It does not read `~/.grok/auth.json`. An OpenClaw or Hermes API key stays in `auth.json`. The send command receives that path, and the runner puts the key on the `Authorization` header. Codex runs as `codex exec --skip-git-repo-check`, with stdin closed, because `$HOME` is not a trusted git directory.

Command lines, the selection file, and the caps are in [`docs/architecture.md`](docs/architecture.md).

---

## Versions

Version lives in **`manifest.json`** only. Releases bump it, add a [CHANGELOG.md](CHANGELOG.md) entry, and should be tagged `vX.Y.Z`.

---

## Credits

Built for [Omarchy](https://omarchy.org) / Quickshell. The header, status pill, and tabs follow [Lanarchy](https://github.com/DonnieFi/OmarPlugs).

MIT. See [LICENSE](LICENSE).
