## Hex Launcher 0.2.0 — the game starts by itself

0.1.x rewrote a yaml file and pressed **Play** for you. 0.2.0 asks the Riot Client directly: the language is set, the game is launched and the previous game client is closed cleanly — no click, no kill, and the manual start stays as a fallback that never fails hard. Along the way the setup wizard learned to fix Riot paths and put a "Hex Launcher" shortcut on the Desktop.

### Launch

- **Direct launch.** The launcher talks to the Riot Client through its local interface — the same channel the Play button uses. The Riot Client sets the language itself and starts the game. Warm session: ~10 s from click to game client; cold start of the Riot Client: ~13 s.
- **Clean close of the running game.** The game client is asked to end its session the way the Riot Client does it: gone in 0.5 s, normal exit, no more waiting for the previous session to be released. Killing the process is now the last resort only.
- **Riot Client left alone.** It is never killed on the direct path: if it is running, its session is reused; if it is minimised to the tray after a game, it is woken up — and the wake-up is replayed (after 5 s, then every 30 s) until its window is back.
- **Once the game is up, the Riot window folds to its tray icon** and stays ready for the next launch.
- **No time limit.** As long as the Riot Client answers "not yet" — a game patch in progress can take hours on a slow connection — the launcher waits, and tells you why ("Riot is updating League of Legends…", "Riot is releasing the previous game session…"). Two ways out, both yours: from 2 minutes of waiting the splash offers **Force manual start** (for this launch only, nothing is remembered), and the ✕ at the top right stops the launcher without touching anything, to try again later.
- **Manual start kept as-is.** All Riot processes closed, language written in the settings file, relaunch, and you press Play. Used whenever the direct launch does not go through; forced by `-NoLocalApi` or by the **Manual start** box of the wizard — in that mode the game client is closed the old way, with no call to the Riot Client.
- **No memory of failures.** The direct launch is attempted every time; a one-off hiccup never turns into a permanent manual start.

### Robustness

- **One launcher at a time.** A second shortcut clicked while a launch is running shows "A launch is already in progress" for 3 s and exits.
- **Riot window closed during the wait** → the launcher notices and wakes the Riot Client again instead of waiting until the budget runs out.
- **Vanguard VAN 216 warning.** From four game starts in less than five minutes, Vanguard shows error VAN 216 and closes the client, however the game was closed — a Windows restart is then required. The splash warns from the third launch in five minutes; the README explains it.
- **Nothing can break a launch**: unreadable Riot files, stale path in `config.json`, a clock that jumps backwards, a full disk for the log, a language file that cannot be written — each case is covered by a test and degrades to the next fallback.
- **No secret is ever logged.**

### Launch log

`app\launch.log` (next to `config.json`, ignored by git, not in the archive): one timestamped line per step, plus the outcome and the total time. It is the file to send when "it does not work anymore". Capped at 200 KB.

### Splash

- Tells the whole sequence: closing the game client, starting or waking the Riot Client, applying the language, asking for the launch, waiting for the game client, then companion apps — with the seconds elapsed on the current step.
- **Force manual start** button after 2 minutes.
- Outcome shown at the end (direct launch, manual start with the reason, Riot Client not found).

### Setup wizard (`setup.bat`)

- **Riot paths can be fixed on page 1**: editable fields with a **Browse…** button, status recomputed on every change — you never have to open `config.json`.
- **"Hex Launcher" shortcut on the Desktop**, gear icon, pointing at `setup.bat` — the way back into the wizard.
- **Riot compatibility section** on the Shortcuts page: the **Manual start** box, with a note saying when to tick it and what happens then (your settings are applied — language, companion app — the Riot Client opens and you press Play).
- **Icon sets**: readable labels, explicit order, preview on the Shortcuts page.
- Flag colours: twelve countries corrected to their official values.
- Window title, tooltips and READMEs say **Hex Launcher**; `hex-launcher` remains the repository, archive and file name.

### Documentation

- READMEs (EN / FR / JA): direct launch explained step by step, manual start, budgets, VAN 216, Riot compatibility box, "Trust" section — what `setup.bat` does and does not do, and how to check the archive's SHA-256.
- Riot mention reduced to non-affiliation and trademarks.
- "Built with claude_forge" section.

### Under the hood

- New libraries under `app/lib/` (Riot Client interface, launch log, Riot window, Riot install detection, flags, icon sets); `launch-lol.ps1` is fully testable, with a `-DryRun` mode.
- Developer probe in `tools/` to inspect what the Riot Client answers, secrets masked.
- Test suite: **716 Pester tests** (256 in 0.1.2), all I/O mocked; real launches measured and logged in the forge notes.

### Requirements

Windows 10/11, Windows PowerShell 5.1, Riot Client installed. No admin rights — `setup.bat` refuses to run elevated.

### Known limits

- VAN 216 is Vanguard's own rate limit on game client starts; the launcher can only warn.

**Upgrade**: unzip over the previous folder or anywhere else, run `setup.bat` (or the Hex Launcher shortcut) once to recreate the shortcuts. `config.json` is kept.
