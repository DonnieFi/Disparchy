# Disparchy

One prompt, several local AI CLIs — Google-bar hangdown, provider checkboxes, parallel answers.

Click the bar icon (or **Super+Shift+M** if you add the bind). Type a prompt. Tick a provider to arm it and pick its model from the arrow. **Send** (or Enter) runs the armed providers in parallel. A timeout or error on one column does not stop the others. Answers land in colored columns. **Clear** empties the prompt and hides the current answers. **Paste** on the right turns clipboard fill on. When it is on, opening an empty prompt reads text from the clipboard. **Setup** turns providers on and off for the bar. Model lists come from each CLI. Ollama and LM Studio take a URL. OpenClaw uses the gateway on port 18789 when it is up, and the local node when it is not. Hermes keeps its own default model. Timeout and default models stay on the bar-widget settings schema.

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

Summon from IPC (hangs from the bar widget):

```
omarchy-shell shell summon dkfiander.disparchy '{}'
```

## Usage

1. Open Disparchy from the bar icon (or the keybind).
2. Type a prompt (single line). Enter or **Send**.
3. Check or uncheck providers on the second row. Unchecked CLIs are skipped. **Setup** chooses which of the ten providers appear on that row.
4. Answers appear as compact slivers under the two chrome rows. **copy** / **more** on each.
5. **◷ N** toggles history in the checkbox slot. **Back** leaves a past run. Escape closes the hangdown; in-flight jobs keep running and still write history.

Default model per CLI comes from bar-widget settings / last selection. Multi-model pickers stay off this compact surface.

## Requirements

- Omarchy 4 / Quattro (`omarchy-shell`)
- `wl-paste` / `wl-copy` (text clipboard)
- Any of: `claude`, `codex`, `grok`, `agy`, `cursor-agent` (or `agent`), `openclaw`, `hermes` on PATH
- Optional HTTP: Ollama at `http://127.0.0.1:11434`, LM Studio at `http://127.0.0.1:1234`, or any OpenAI-compatible `/v1/chat/completions` URL
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

Open the bar icon. Type a short question. Arm two CLIs. Send. Screenshot the row slivers.

## License

MIT. See [LICENSE](LICENSE).
