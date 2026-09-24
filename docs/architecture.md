# Disparchy architecture

Product name **Disparchy**. Plugin id: `dkfiander.disparchy`.

This document is the contract between `Panel.qml`, `Model.js`, and `bin/disparchy-run`. Install and day-to-day use are in the [README](../README.md).

## Paths

**Plugin install** (code only):

`~/.config/omarchy/plugins/dkfiander.disparchy/`

After installing or updating, run `omarchy-restart-shell`.

**Runtime state:**

`$XDG_STATE_HOME/omarchy/dkfiander.disparchy/`

Usually `~/.local/state/omarchy/dkfiander.disparchy/`. The panel sets this directory to mode `0700` and the files in it to mode `0600`. The Security section describes the first save.

State stays out of the plugin tree. The shell watches that tree and reloads QML on every write.

| File | Purpose |
|------|---------|
| `selection.json` | Armed models, enabled providers, HTTP URLs, `autoPaste` |
| `auth.json` | API keys for OpenClaw and Hermes. The runner refuses a symlink or a file readable by group or others |
| `history.json` | Past runs, capped by `historyMaxRuns` |
| `prompt.txt` | Prompt for the current send. The runner reads this file |
| `status.json` | Last provider probe. The panel rewrites it |

## Selection

```json
{
  "models": { "claude": ["sonnet"], "codex": ["gpt-6-sol"] },
  "enabled": ["claude", "codex", "grok", "antigravity", "cursor"],
  "endpoints": { "ollama": "http://127.0.0.1:11434" },
  "autoPaste": true
}
```

| Field | When it is omitted |
|-------|--------------------|
| `enabled` | The first five providers are shown: Claude, Codex, Grok, Antigravity, Cursor |
| `endpoints` | Ollama uses `http://127.0.0.1:11434`. LM Studio uses `http://127.0.0.1:1234` |
| `autoPaste` | Clipboard fill stays off |
| a model string | The CLI default. The runner omits the model flag |

An armed provider has a non-empty model list. An empty string in that list still means the CLI default. A provider can be enabled and not armed.

HTTP providers are available when enabled, even if the server is down.

## Providers

| Id | Binary | Argv |
|----|--------|------|
| `claude` | `claude` | `-p --output-format text [--model M] -- PROMPT` |
| `codex` | `codex` | `exec --skip-git-repo-check [--model M] -- PROMPT` |
| `grok` | `grok` | `--no-auto-update -p PROMPT [--model M] --output-format plain` |
| `antigravity` | `agy` | `--output-format text [--model M] --print PROMPT` |
| `cursor` | `cursor-agent`, then `agent` | `-p --output-format text [--model M] -- PROMPT` |
| `openclaw` | `openclaw` | gateway up: `agent --message-file FILE [--model M]`. gateway down: `agent exec --message-file FILE [--model M]`. With an API key: `POST {base}/v1/chat/completions`, model `openclaw/default` when empty |
| `hermes` | `hermes` | `chat --oneshot --query-file FILE [-m M]`. With an API key: `POST {base}/v1/chat/completions`, model `hermes-agent` when empty |
| `ollama` | HTTP | `POST {base}/api/generate` with `model`, `prompt`, `stream: false` |
| `lmstudio` | HTTP | `POST {base}/v1/chat/completions` |

`--print` on Antigravity consumes the next argument, so `--output-format` comes first. Cursor never receives `-m`.

OpenClaw's gateway probe is a TCP connect to `127.0.0.1:18789` with a 0.4s timeout.

An empty Ollama model becomes `llama3.2`. An empty LM Studio model becomes `local`. Hermes omits `-m` when the model is empty.

Codex needs `--skip-git-repo-check` because the working directory is `$HOME`, which is not a trusted git directory. Stdin is `DEVNULL`. The runner does not stop a Codex send because `codex login status` printed "Not logged in". That string can disagree with a working `codex exec`.

## Runner flags

```bash
bin/disparchy-run --cli codex --model gpt-6-sol --timeout 90 --prompt-file prompt.txt
bin/disparchy-run --models
bin/disparchy-run --status
bin/disparchy-run --discover
```

| Flag | Prints |
|------|--------|
| `--models` | `cli`, model id, label. At most 30 ids per CLI |
| `--status` | `cli`, `installed` or `missing`, then a label |
| `--discover` | one CLI id per line, for binaries on `PATH` and HTTP servers that answered |

Status labels include `signed-in`, `signed-out`, `gateway`, and `local node`. The panel turns those into **install**, **sign in**, **open**, **gateway**, **local node**, **reachable**, and **endpoint down**.

Grok's signed-in check is the size of `~/.grok/auth.json`. The file contents are not read.

## Caps

| Limit | Value |
|-------|-------|
| Prompt | 32 KiB. Larger prompts never start |
| Stdout | 256 KiB, then `[truncated]` |
| Timeout | `timeoutSec`, 15–300, default 90. The process exit is 124 |
| In flight | 6 slots. Further armed providers wait |
| Working directory | `$HOME` |
| Environment | `TERM=dumb`. No shell interpolation |

## Slots

`Panel.qml` owns six `Process` objects, `slot0` through `slot5`. A pump claims the next pending target when a slot frees. **Cancel** sets the run idle, marks targets still waiting as `cancelled`, and does not start another slot. A column that already started runs until it exits or hits the timeout.

One failure does not cancel its siblings.

## Tokens

`estimateTokens` is `ceil(character count / 4)`. The column line is `≈ N out`. The footer is `in N · out N · ≈ N this run · ≈ N saved`, where "saved" sums the history file. This is not provider usage.

## Security

The plugin is unsandboxed code in `omarchy-shell`. API keys for OpenClaw and Hermes are stored in `auth.json` in the state folder (`$XDG_STATE_HOME/omarchy/dkfiander.disparchy/`, default `~/.local/state/omarchy/dkfiander.disparchy/`). They are never written into the plugin folder. The first save creates that file at the process umask, usually `0644`. A later atomic rewrite keeps the mode the file already has, so a file that is already `0600` stays `0600`. After saving, the plugin sets the state files to mode `0600`, and the runner refuses to read `auth.json` if it is a symlink or readable by group or others. The panel also sets the state folder to mode `0700`, including when that folder already exists with a wider mode. A save can create the folder through Quickshell before that step, at the normal directory mode, usually `0755`. Parent directories are not changed. Once the state folder is `0700`, other users cannot reach `auth.json` during the window when the file is still `0644`. The plugin never passes `--force`, `--yolo`, `--always-approve`, or `--dangerously-skip-permissions`.

Sign-in is `xdg-terminal-exec --hold --title=Disparchy --` plus the CLI login command. HTTP providers have no login launch.
