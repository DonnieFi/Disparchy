# Disparchy architecture

Product name **Disparchy**. Plugin id: `dkfiander.disparchy`.

This document is the contract between `Panel.qml`, `Model.js`, and `bin/disparchy-run`. Install and day-to-day use are in the [README](../README.md).

## Paths

**Plugin install** (code only):

`~/.config/omarchy/plugins/dkfiander.disparchy/`

After installing or updating, run `omarchy-restart-shell`.

**Runtime state:**

`$XDG_STATE_HOME/omarchy/dkfiander.disparchy/`

Usually `~/.local/state/omarchy/dkfiander.disparchy/`. The panel sets this directory to mode `0700` and the files it writes to mode `0600`. It does not read or write `auth.json`. The runner creates that file itself at mode `0600`.

State stays out of the plugin tree. The shell watches that tree and reloads QML on every write.

| File | Purpose |
|------|---------|
| `selection.json` | Armed models, enabled providers, HTTP URLs, `autoPaste` |
| `auth.json` | API keys for OpenClaw and Hermes. Only `bin/disparchy-run` reads or writes this file. It refuses a symlink, anything that is not a regular file, or a file readable by group or others |
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
| `claude` | `claude` | `-p --output-format text [--model M]`, prompt on stdin |
| `codex` | `codex` | `exec --skip-git-repo-check [--model M] -`, prompt on stdin |
| `grok` | `grok` | `--no-auto-update --prompt-file FILE [--model M] --output-format plain` |
| `antigravity` | `agy` | `--input-format stream-json --output-format stream-json [--model M]`, prompt on stdin as one `{"event":"user",...}` message. The runner prints the `result` event's `response` |
| `cursor` | `cursor-agent`, then `agent` | `-p --output-format text [--model M]`, prompt on stdin |
| `openclaw` | `openclaw` | gateway up: `agent --message-file FILE [--model M]`. gateway down: `agent exec --message-file FILE [--model M]`. With an API key: `POST {base}/v1/chat/completions`, model `openclaw/default` when empty |
| `hermes` | `hermes` | `chat --oneshot --query-file FILE [-m M]`. With an API key: `POST {base}/v1/chat/completions`, model `hermes-agent` when empty |
| `ollama` | HTTP | `POST {base}/api/generate` with `model`, `prompt`, `stream: false` |
| `lmstudio` | HTTP | `POST {base}/v1/chat/completions` |

The prompt text is never an argument, because any local user can read another process's command line. `argv_for` takes only the prompt file path. For the same reason, **copy** runs a bare `wl-copy` and writes the answer to its stdin, since `wl-copy` keeps running while it owns the clipboard. Cursor never receives `-m`.

OpenClaw's gateway probe is a TCP connect to `127.0.0.1:18789` with a 0.4s timeout.

An empty Ollama model becomes `llama3.2`. An empty LM Studio model becomes `local`. Hermes omits `-m` when the model is empty.

Codex needs `--skip-git-repo-check` because the working directory is `$HOME`, which is not a trusted git directory. `-` makes it read the prompt from stdin. The runner does not stop a Codex send because `codex login status` printed "Not logged in". That string can disagree with a working `codex exec`.

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
| `--status` | `cli`, `installed` or `missing`, a label, then `key:none`, `key:saved`, `key:refused`, or `key:unusable` |
| `--set-key <cli>` | Reads one API key from stdin until EOF and stores it. Empty stdin removes that provider's key. The key is never an argument |
| `--discover` | one CLI id per line, for binaries on `PATH` and HTTP servers that answered |

Status labels include `signed-in`, `signed-out`, `gateway`, and `local node`. The panel turns those into **install**, **sign in**, **open**, **gateway**, **local node**, **reachable**, and **endpoint down**.

Grok's signed-in check is the size of `~/.grok/auth.json`. The file contents are not read.

## Caps

| Limit | Value |
|-------|-------|
| Prompt | 32 KiB. Larger prompts never start |
| Stdout | 256 KiB, then `[truncated]` |
| HTTP response | 8 MiB for an answer, 1 MiB for a model list. A larger, truncated, or non-JSON body fails the column |
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

The plugin is unsandboxed code in `omarchy-shell`. API keys for OpenClaw and Hermes stay in `auth.json` in the state folder (`$XDG_STATE_HOME/omarchy/dkfiander.disparchy/`, default `~/.local/state/omarchy/dkfiander.disparchy/`). Only `bin/disparchy-run` reads or writes that file. The panel never opens it, and the key is not copied into a panel property, the history file, or settings. `--set-key <cli>` reads the key from stdin until EOF, never from argv or the environment. If the state directory is missing, the runner creates it at mode `0700`. It refuses a symlink or a non-regular file for that directory or for `auth.json`, and then writes nothing. Otherwise it writes a temporary file in the same directory, opened with `O_CREAT|O_EXCL` at mode `0600` so the umask cannot widen it, fsyncs that file, and renames it over `auth.json`. Empty stdin, after one trailing newline is stripped, removes that provider's key and leaves the others. `--status` adds `key:none`, `key:saved`, `key:refused`, or `key:unusable` and never prints any part of a key. `key:none` means `auth.json` is missing (`lstat` raises `FileNotFoundError`) or the strict read succeeds and this provider has no non-empty key. `key:saved` means that read passes and the provider's key is non-empty. `key:refused` is only a regular file owned by the current user, whose JSON is a dict, and whose only fault is a mode with group or other bits. `key:unusable` is everything else: a symlink, another owner, a non-regular file, broken or non-dict JSON, or an `OSError` on the file or the state folder. One unusable column does not stop the other rows. The runner still refuses to read `auth.json` in those unusable cases and when the mode is loose. `--set-key` accepts only a missing file or a parseable dict in a regular file this user owns, including a loose mode, and the rewrite replaces it at mode `0600`. It does not overwrite a broken or unparseable file, and an empty-stdin remove refuses in that same unusable state. The plugin never passes `--force`, `--yolo`, `--always-approve`, or `--dangerously-skip-permissions`.

Sign-in is `xdg-terminal-exec --hold --title=Disparchy --` plus the CLI login command. HTTP providers have no login launch.
