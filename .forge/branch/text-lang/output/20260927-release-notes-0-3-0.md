## Hex Launcher 0.3.0 — voice and text in two languages

Japanese voices with French text, or the other way round: a shortcut can now start the game with the voices in one language and the in-game text in another. No Riot setting allows it; Hex Launcher does it by replacing two text files of the game. **Riot does not allow file modifications: the account can be sanctioned, up to a ban. At your own risk.**

### Forced text

- **In the wizard** (`setup.bat`, *Shortcuts* page): tick "Force the in-game text in:" and pick the text language. Every ticked language stays the voice language. A red warning recalls the risk as soon as the box is ticked.
- **Shortcut** `League of Legends JP-FR` (JP voices, FR text), with or without a companion app. Its icon is split diagonally: voice flag at the top, text flag at the bottom, the HL logo staying above the line; with country badges, the badge itself is split.
- **Original Riot files**: the two text files (`Global`, `UI`, ~4 MB) of the chosen language are downloaded from Riot's official CDN, for the exact installed version, and cached (`%LOCALAPPDATA%\hex-launcher\text\`). They are the files signed by Riot, identical to those of a player in that language.
- **Put in place at the right time**: once the LoL client is open and its file check has passed (about fifteen seconds). Any earlier, the client would repair them.
- **Restored** at the start of the next launch through a shortcut, before any language change.
- **Never blocking**: offline, unknown format, failed integrity check → the match is played in the voice language, with a `TEXT` line in `launch.log`.
- **Splash**: in yellow under the title, "MODIFIED GAME FILES — TEXT: 日本語" (name of the text language).
- Tested for real: JP-FR, FR-JP (Japanese text with French voices), manual start, companion app, change of voice language between two launches.

### New icon set "HL logo + badges"

- The HL logo alone, without frame or flag, enlarged; every shortcut gets the country badge (split in forced text mode) and the companion app badge, like the "Official LoL + badges" set, without depending on the LoL installation.

### Other changes

- "At your own risk" clause at the top of the READMEs and of `LISEZMOI.txt`.
- Log: an abandoned wait reports its real duration.
- Wizard: the icon set list shows all five sets without scrolling; the install log only appears once it has something to say.

### Trust

- **New binary dependency**: `app\lib\native\libzstd.dll`, the official zstd decompression library (facebook/zstd 1.5.7, BSD licence), SHA-256 pinned and checked at every load.
- **Network**: besides installing companion apps, the launcher only contacts Riot's official CDN, and only in forced text mode.

### Under the hood

- New libraries under `app/lib/`: Riot patcher manifest reader, ranged downloads from the CDN, put-in-place and restore, LoL client log reader, split icon.
- Developer tools: `make-logo-icon.ps1` (icon of the new set), `watch-launch.ps1` (real-world test: records writes to the text files).
- Test suite: **903 Pester tests** (716 in 0.2.0), all I/O mocked.

### Known limits

- The LoL client (menus, shop) stays in the voice language: only the in-game text changes.
- LoL started without a Hex Launcher shortcut: the LoL client puts the original files back when it opens, and the match is played in the voice language.
- VAN 216 (Vanguard, starts too close together): unchanged, the launcher warns from the third launch in five minutes.

**Upgrade**: unzip over the previous folder or anywhere else, run `setup.bat` (or the Hex Launcher shortcut) once to recreate the shortcuts. `config.json` is kept.
