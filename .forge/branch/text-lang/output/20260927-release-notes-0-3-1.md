## Hex Launcher 0.3.1 — the normal shortcut stays

- **Forced text**: when "Force the in-game text in:" is ticked, every ticked language keeps its normal shortcut (`League of Legends JP`) and also gets the forced-text shortcut (`League of Legends JP-FR`). Until now, the normal shortcut was replaced, and even removed if it already existed. Same behaviour in script mode (`create-shortcuts.ps1 -TextLocale`).
- A ticked language identical to the text language only gets its normal shortcut, as before.
- READMEs (EN / FR / JA) updated.
- 905 Pester tests.

**Upgrade**: unzip over the previous folder, then run `setup.bat` (or the Hex Launcher shortcut) again and click **Apply** to recreate the normal shortcuts. `config.json` is kept.
