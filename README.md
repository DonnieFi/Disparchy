# Disparchy

One prompt, several local AI CLIs, same overlay.

Hotkey **Super+Shift+M** (you add the bind). Prefill from the clipboard or type. Check Claude / Codex / Grok / Gemini / Cursor, each with a model (defaults allowed). Send. Answers land in the overlay and in local history.

Plugin id: `dkfiander.disparchy`  
Repo: [DonnieFi/Disparchy](https://github.com/DonnieFi/Disparchy)

No API keys in this repo. Plugins run unsandboxed inside `omarchy-shell`. Read the QML and `bin/` before you enable it. It only calls CLIs already on your PATH, with logins those CLIs already have.

## Install

```
omarchy plugin add https://github.com/DonnieFi/Disparchy.git --enable
```

Place the icon if it does not land where you want:

```
omarchy bar move dkfiander.disparchy --section right
```

Validate a checkout:

```
omarchy plugin validate .
```

## Keybind (optional)

Add to your Hyprland user binds. The plugin will not write this for you.

```
bind = SUPER SHIFT, M, exec, omarchy-shell shell toggle dkfiander.disparchy '{}'
```

Summon without the bar:

```
omarchy-shell shell summon dkfiander.disparchy '{}'
```

## Usage

1. Copy a question (or type one).
2. Open the overlay from the bar icon or the keybind.
3. Check the CLIs you want. Empty model fields use the CLI default (Claude defaults to `sonnet`).
4. Send (or Ctrl+Enter). Rows go pending → done / timeout / failed.
5. Click a done row to copy that answer (`wl-copy`).
6. History tab lists past runs. Escape closes the overlay; in-flight jobs keep running and still write history.

## Requirements

- Omarchy 4 / Quattro (`omarchy-shell`)
- `wl-paste` / `wl-copy` (text clipboard)
- Any of: `claude`, `codex`, `grok`, `gemini`, `cursor-agent` (or `agent`) on PATH
- `python3` for `bin/disparchy-run` (stdlib only)

Missing CLIs are omitted from the list, not treated as errors.

## Configure

Bar-widget settings (timeout, history cap, default model per CLI) are on the widget schema. History and last selection live in `$XDG_STATE_HOME/omarchy/dkfiander.disparchy/` with directory mode 700 and files mode 600.

## Security

Third-party plugins are arbitrary code in the long-lived shell process. Inspect source. Disparchy does not store provider tokens. It never passes `--force`, `--yolo`, `--always-approve`, or `--dangerously-skip-permissions`.

## Remove

```
omarchy plugin remove dkfiander.disparchy
```

## Demo

Copy a short question. Super+Shift+M. Confirm two targets. Send. Screenshot the two answers.

## License

MIT. See [LICENSE](LICENSE).
