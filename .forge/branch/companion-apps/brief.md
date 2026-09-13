# Brief — companion-apps

## Objective

Ajouter au lanceur existant (sélecteur de langue conservé tel quel) une fonctionnalité de **gestion de l'application compagnon** : à l'installation (`install.bat`), l'outil demande à l'utilisateur quelle appli compagnon il veut (Porofessor, Blitz, OP.GG…) et se charge de **l'installer** sur la machine (téléchargement de l'installeur officiel + exécution). Une seule appli compagnon à la fois : si une autre est déjà présente, l'outil la **désinstalle** avant d'installer la nouvelle.

Première étape : **étude de faisabilité** (sources de téléchargement stables, désinstallation silencieuse via les clés `Uninstall` du registre ou `winget`, cas Overwolf/Porofessor). Si c'est faisable : implémentation, puis **renommage du dépôt** (ex. `lol-launcher-helper`) et mise à jour des README pour refléter ce positionnement élargi.

## Scope & rules
- Registre et configuration Windows en **lecture seule** : le code généré ne fait que lire les clés `Uninstall` ; toute écriture (clés, services, tâches planifiées, démarrage auto…) est interdite. Les installeurs/désinstalleurs tiers écrivent leurs propres clés — ils ne s'exécutent qu'avec autorisation explicite.
- Périmètre Windows uniquement (winget, registre, PowerShell 5.1) — pas de gestionnaire de paquets tiers.
- Désinstallation d'une app Overwolf (Porofessor) : **interactive par conception** — l'outil ouvre `OWUninstaller.exe --uninstall-app=<id>` (menu Overwolf, Overwolf coché par défaut) et laisse l'utilisateur décider s'il garde ou retire Overwolf. Jamais de contournement du menu, jamais de désinstallation d'Overwolf décidée par le script.
- Périmètre étendu le 2026-09-13 : Mobalytics rejoint le catalogue (4ᵉ appli) ; le splash du lanceur est réutilisé pendant l'installation/désinstallation de l'appli compagnon.
- Modèle révisé le 2026-09-13 (Option A) : **plusieurs applis compagnon** peuvent être installées ; un raccourci = une langue × une appli (`launch-lol.ps1 -Locale xx_XX -Companion <id>`) ; `config.json` porte la liste `companionApps`. La désinstallation d'une appli n'a lieu que sur demande explicite de l'utilisateur (case décochée par défaut), jamais par exclusivité.
