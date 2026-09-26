# Brief — text-lang

## Objective

1. **Avertissement dans les README (FR/EN/JA)** : ajouter une clause de non-responsabilité — en cas de sanction (ban) du compte Riot, l'auteur n'est pas responsable ; l'utilisateur utilise l'outil à ses propres risques.
2. **Nouveau mode « texte / voix séparés »** : permettre un raccourci qui lance le jeu avec les **textes dans une langue** et les **voix dans une autre**. Ce mode touchant aux fichiers du jeu, un **avertissement en rouge** (risque de ban) est affiché dans le lanceur.
3. **Icône du raccourci mixte** : icône coupée par un **trait noir en diagonale** — **drapeau de la langue des voix en haut**, **drapeau de la langue des textes en bas**.

## Scope & rules

- Mécanisme : aucun réglage Riot officiel. Locale Riot = langue des VOIX (cochée, fonctionnement habituel) ; le lanceur copie les fichiers TEXTE de la langue forcée (`Localized/Global.<texte>.wad.client` + `UI.<texte>.wad.client`, ~4 Mo) à la place de ceux de la langue des voix, avec sauvegarde des originaux ; refait à chaque lancement mixte (patch/réparation Riot restaure). Le client LoL (Plugins) reste dans la langue des voix — hors périmètre.
- Setup : fonctionnement habituel inchangé (langue cochée = langue du raccourci). Nouvelle case « Forcer le texte en : [select des langues] » avec avertissement rouge ; cochée → chaque raccourci garde la voix de sa langue cochée, le texte est forcé dans la langue du select. Décochée → aucun changement.
- Source des fichiers texte de la langue forcée : CDN Riot public (`…/channels/public/bundles/`), fichiers repérés dans le manifest local de la version installée (`Game.ok` + `Game.manifest`, lecture seule) ; cache `%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\`. Jamais de changement de locale Riot pour les obtenir. Décompression zstd via `libzstd.dll` officielle (hash épinglé) — aucun exécutable tiers.
- Toute erreur (hors ligne, format inconnu, contrôle d'intégrité) → lancement normal dans la langue des voix + ligne `launch.log`.
- Avertissement rouge (risque de ban) : dans le setup uniquement (page Raccourcis, case « Forcer le texte en »). Pas d'avertissement dans le splash.
- **Installation LoL de l'utilisateur intouchable pendant le développement** : lecture seule (listes, tailles, yaml) ; aucune copie, écriture, suppression, changement de langue ni lancement. Tests = mocks / dossier factice sous le scratchpad ou `TestDrive:` ; essai réel uniquement fait par l'utilisateur lui-même.
- Textes utilisateur (README, i18n) : proposer le français d'abord, traduire en/ja après validation.
