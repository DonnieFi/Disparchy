# Changelog

All notable changes to Disparchy (`dkfiander.disparchy`) are documented here.
The version in `manifest.json` is the single source of truth.

## 0.6.0, 2026-09-25

- OpenClaw and Hermes API keys are read and written only by the runner. Setup's key field is write-only: Save, Replace, and Remove, and no part of the key is shown
- `--set-key` stores a key from stdin. `--status` reports `key:saved` or `key:none` and does not print the key

## 0.4.0, 2026-09-24

- Added the theme-aware dispatch mark to the bar and panel header, with light and dark SVG/PNG assets
- Rendered provider answers as Markdown in bordered comparison cards, with scrollable expanded replies
- Added active lane motion and disabled image loading from answer Markdown; copy still uses the original text
- Gave Ask a multiline composer and compact provider chips; stacked Clear above Send or Cancel
- Styled Setup and History to match Ask, with roomy two-column provider cards and auto-paste in Setup, off by default

## 0.3.1, 2026-09-23

- Replaced the overlay with a one-line hangdown. One prompt, provider checkboxes, parallel answer columns
- **Setup** shows or hides providers on the bar. Click a status word to sign in. Ollama and LM Studio take a URL
- Model lists come from each CLI. Codex runs through `codex exec --skip-git-repo-check` with stdin closed
- OpenClaw uses the gateway on port 18789 when it is up, and the local node when it is not
- Header, status pill, and **Ask** / **Setup** / **History** / **Paste** tabs follow the Lanarchy panel
- Footer and each column show a character-based token estimate
- **Clear**, **Cancel**, and optional clipboard paste
- **Setup** has an API key line under OpenClaw and Hermes. The key stays in `auth.json` and is sent as a bearer token

## 0.1.0, 2026-09-23

- First plugin. Overlay, bar icon, parallel CLI runs, local history
