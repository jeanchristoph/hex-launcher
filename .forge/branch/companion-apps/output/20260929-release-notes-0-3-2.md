## Hex Launcher 0.3.2 — DPM joins the companion apps

- **New companion app: DPM** (dpm.lol). Tick it in the *Companion apps* step of `setup.bat`: silent install (~12 s) from the official installer, silent uninstall on request. As for the others, the installer and the uninstaller must carry the publisher's signature (`DPMLOL SAS`/FR), otherwise they are refused.
- `League of Legends JP - DPM` shortcuts with their "D" badge; in script mode: `-Apps dpm`, `-Companions dpm`.
- READMEs (EN / FR / JA) updated.
- 907 Pester tests.

**Upgrade**: unzip over the previous folder, then run `setup.bat` (or the Hex Launcher shortcut) again to tick DPM. `config.json` is kept.
