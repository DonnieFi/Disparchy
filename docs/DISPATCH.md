# Disparchy

Omarchy Quattro plugin: one prompt, many CLI+model voices.

- Display name: **Disparchy**
- Plugin id: `dkfiander.disparchy`
- Hotkey: Super+Shift+M (README bind only; plugin does not write Hyprland config)
- Status: spec locked enough for manifest + runner contract

## Goal

Hotkey or bar icon opens one overlay:
- prompt = clipboard text (if any) or typed text
- pick one or more CLI+model targets
- fire the same prompt in parallel
- show answers in the overlay
- keep a local history

No API keys in QML or the repo. Unsandboxed plugin; talk to already-installed CLIs only.

## Out

- UniFi
- GitHub / PR badge (use robzolkos/omarchy-github)
- Interactive coding-agent sessions
- `--dangerously-skip-permissions` / yolo / force / trust flags
- OAuth or stored provider tokens
- Silent keybind install

## Kinds

- `overlay` — summoned surface (primary)
- `bar-widget` — one icon; click toggles the same overlay
- optional later: `service` if a background runner is cleaner than overlay-owned Processes

## Prompt

On open:
1. If `wl-paste` returns non-empty text, prefill the box.
2. User may edit, replace, or clear.
3. Empty prompt → Send disabled; show “paste or type a prompt”.
4. Image clipboard → ignore for v1 (text only).

## Targets (CLI + model)

Each target is `{ cli, model, label, enabled }`.

Discovered CLIs (skip if not on PATH):

| cli | binary | default model | frozen one-shot (no yolo / force / always-approve) |
|-----|--------|---------------|-----------------------------------------------------|
| claude | `claude` | `sonnet` | `claude -p --output-format text [--model M] -- PROMPT` |
| codex | `codex` | CLI default | `codex exec [--model M] -- PROMPT` |
| grok | `grok` | CLI default | `grok --no-auto-update -p PROMPT [--model M] --output-format plain` |
| gemini | `gemini` | CLI default | `gemini -p PROMPT [-m M]` |
| cursor | `cursor-agent` then `agent` | CLI default | `cursor-agent -p --output-format text [-m M] -- PROMPT` |

Prompt is a single argv element. cwd = `$HOME` in v1. Runner: `bin/disparchy-run`.

## Run

- Parallel, one process per selected target.
- Timeout per target (default 90s, setting).
- Cap prompt size (e.g. 32 KiB) and stdout (e.g. 256 KiB); truncate with a marker.
- Overlay rows: pending → done | timeout | failed (exit + short stderr).
- Notify when the last in-flight target settles (“3/3 done” or “2 ok, 1 failed”).
- Click a row: copy that answer (`wl-copy`).
- Escape: close overlay; in-flight jobs keep running and land in history.

## History (required)

Store under `$XDG_STATE_HOME/omarchy/<plugin-id>/history.json` (mode 600 dir + file).

Each run:
- id, startedAt, prompt (full text)
- targets[{ cli, model, status, elapsedMs, answer, error }]

UI:
- Overlay has Prompt | History
- History: newest first, prompt preview + target chips
- Open a run: same layout as live results (read-only)
- Cap: 50 runs or 2 MiB, whichever first; drop oldest
- Clear history action

No cloud. No secrets in history.

## Settings (inline on bar-widget schema)

- timeoutSec
- historyMaxRuns
- defaultModels per cli (strings)

Codex app-server URL: **not in v1**.

## IPC

`omarchy-shell shell summon <id> '{}'`
`omarchy-shell shell toggle <id> '{}'`

Hyprland example in README only:

```
bind = SUPER SHIFT, M, exec, omarchy-shell shell toggle <id> '{}'
```

## Security README block (required)

Plugins run unsandboxed inside omarchy-shell. Inspect source before enable.
This plugin runs local CLIs with your existing logins. It never stores API keys.

Install:

```
omarchy plugin add <repo> --enable
```

## Demo path (X)

1. Copy a short question.
2. Super+Shift+M — box already filled.
3. Check grok + claude.
4. Send.
5. Two answers side by side in dense rows.
6. Screenshot.

## Open before code

- Display name + plugin id
- Confirm real argv for each CLI on PATH
- History in same overlay vs a second panel
- Whether bar icon is required for v1 or overlay-only is enough
