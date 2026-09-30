## Hex Launcher 0.4.0 — installer, portable version and automatic updates

- **Two downloads to choose from**:
  - `hex-launcher-setup-0.4.0.exe` (recommended): installs into `%LOCALAPPDATA%\Programs\hex-launcher`, without administrator rights, with Hex Launcher in the Start menu and an entry in *Installed apps*. The installer is not signed: SmartScreen may show "Windows protected your PC" (*More info* → *Run anyway*, after checking the hash below).
  - `hex-launcher-portable-0.4.0.zip`: unzip it anywhere; settings stay in `data\`, next to `setup.bat`.
- **Automatic updates**: at launch, a new version published on GitHub is offered (*Install* / *Later*, with a "Don't ask me again until the next version" box). The download is checked against its SHA-256, then the launch resumes in the new version. A single request to api.github.com, with no data sent; can be turned off on the assistant's *Welcome* page.
- **Settings outside the program folder**: `config.json`, the log and the composed icons now live in `%LOCALAPPDATA%\hex-launcher\` (or `data\` when portable).
- **Uninstall** (installed version): removes the desktop shortcuts and keeps the settings.
- READMEs (EN / FR / JA) updated: new *Updates* and *Uninstall* sections.
- 1020 Pester tests.

**Upgrading from 0.3.x** (automatic updates only exist from 0.4.0 on): unzip the portable zip over the old folder, and your settings are picked up into `data\`. Or switch to the installer, then run the assistant again: the desktop shortcuts are recreated, and you can then delete the old folder.
