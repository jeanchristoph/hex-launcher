## Hex Launcher 0.3.1 — le raccourci normal reste là

- **Texte forcé** : quand « Forcer le texte en jeu en : » est coché, chaque langue cochée garde son raccourci normal (`League of Legends JP`) et reçoit en plus le raccourci à texte forcé (`League of Legends JP-FR`). Jusqu'ici, le raccourci normal était remplacé, et même supprimé s'il existait déjà. Même comportement en mode script (`create-shortcuts.ps1 -TextLocale`).
- Une langue cochée identique à la langue du texte n'a que son raccourci normal, comme avant.
- README (EN / FR / JA) mis à jour.
- 905 tests Pester.

**Mise à jour** : décompressez par-dessus l'ancien dossier, puis relancez `setup.bat` (ou le raccourci Hex Launcher) et cliquez sur **Appliquer** pour recréer les raccourcis normaux. `config.json` est conservé.
