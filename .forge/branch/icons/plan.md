# Plan — icons
**Objective:** Différencier les raccourcis « langue × appli compagnon » par une pastille originale haut-droite (couleur + lettre par compagnon), composée à la demande sur l'icône drapeau, sans logo tiers — version 0.1.2.
**Date:** 2026-09-14

## Tasks

### T1 — Pastille déclarée dans le catalogue compagnon
**Effort:** S
**Files:** `app/companion-apps.json`, `app/lib/companion-app.lib.ps1`, `tests/companion-app.lib.tests.ps1`
**Description:** Ajouter `badge: { "glyph": "P", "color": "#7A3FC9" }` aux 4 entrées (Porofessor P violet, Blitz B rouge `#E0432B`, OP.GG O cyan `#1FA8D8`, Mobalytics M vert `#2FB56A`). `Get-CompanionBadge $App` : renvoie l'objet validé (glyph 1-2 caractères, couleur `#RRGGBB`) ou `$null` avec warning si absent/invalide — dégradation gracieuse, jamais de throw à l'installation. Tests : 4 badges valides, badge absent → `$null` + warning, couleur invalide → `$null`.
[x] 2026-09-14 — Get-CompanionBadge + Test-CompanionBadge, 6 tests, suite à 256 verts

### T2 — Bibliothèque .ico partagée (lecture + écriture)
**Effort:** S
**Files:** `app/lib/icon.lib.ps1` (nouveau), `app/make-flag-icons.ps1`, `tests/icon.lib.tests.ps1`
**Description:** Déplacer `Write-Ico` de `make-flag-icons.ps1` vers la lib (DRY, dot-source dans le générateur). Ajouter `Read-IcoEntries $Path` → `[{ Size; Bitmap }]` : parse l'en-tête (6 o + 16 o/entrée) ; entrée PNG (signature `89 50 4E 47`) → `Bitmap::FromStream` ; entrée DIB → repli `New-Object Drawing.Icon($Path, $Size)`.`ToBitmap()`. Tests : round-trip écriture/lecture 6 tailles, pixel conservé, fichier tronqué → throw explicite, `make-flag-icons.ps1` toujours fonctionnel (test existant ou smoke `-Locales fr_FR -OutDir TestDrive:`).
[x] 2026-09-14 — icon.lib.ps1 (Write-Ico, Read-IcoEntries PNG/DIB), 8 tests dont smoke du générateur

### T3 — Composition de la pastille
**Effort:** M
**Files:** `app/lib/icon-badge.lib.ps1` (nouveau), `tests/icon-badge.lib.tests.ps1`
**Description:** `Add-CompanionBadge -SourceIco -Badge -DestinationIco` : pour chaque entrée, dessine en GDI+ (AntiAlias) un disque Ø 34 % du côté, centre à 58 % du diamètre du coin haut-droit (déborde du cadre), anneau `#0A0E14` (`Palette.Night`) d'épaisseur 2 % (min 1 px), lettre en `GenericSansSerif` gras blanc à 70 % du diamètre, centrée — lettre omise sous 32 px (point de couleur seul). Métriques dans un objet `$BadgeShape` en fraction du côté, comme `$Shape` du générateur. Écrit via `Write-Ico`. Tests : pixel au centre de la pastille = couleur du badge à 256/48/32/16 ; pixel du drapeau hors pastille inchangé ; 16 px sans lettre (centre = couleur pleine) ; sortie relue par `Read-IcoEntries` avec 6 tailles.
[x] 2026-09-14 — icon-badge.lib.ps1 (lettre en GraphicsPath centrée sur ses bornes), 11 tests, planche de contrôle validée

### T4 — Raccourcis compagnon sur icône composée
**Effort:** S
**Files:** `app/create-shortcuts.ps1`, `tests/create-shortcuts.tests.ps1`, `.gitignore`
**Description:** `Resolve-IconPath` prend la combinaison : sans compagnon → inchangé ; avec compagnon et badge → compose `ico\companion\hex-launcher-<xx>-<id>.ico` (dossier gitignoré, regénéré à chaque exécution pour suivre le catalogue) ; badge `$null` ou échec de composition → warning + icône drapeau seule (l'installation aboutit toujours). Tests : chemin composé attendu, repli sans badge, repli sur erreur de composition (mock `Add-CompanionBadge` qui throw), `IconLocation` du `.lnk`.
[x] 2026-09-14 — Resolve-ShortcutIconPath, pastilles lues du catalogue à la demande ; couleur dans le nom du fichier + purge des variantes (cache d'icônes Explorer) ; 12 tests + run réel sur le Bureau

### T5 — Release sans icônes générées
**Effort:** XS
**Files:** `tools/make-release.ps1`, `tests/make-release.tests.ps1`
**Description:** Exclure `app\ico\companion\` du staging (`$ReleaseExcludedDirs`) : les icônes composées sont propres à chaque installation, comme `config.json`. Test : un fichier dans `ico\companion\` n'est pas dans le zip.
[x] 2026-09-14 — $ReleaseExcludedDirs + Test-ReleaseExcludedDir, 1 test

### T6 — Version 0.1.2, documentation, release
**Effort:** S
**Files:** `app/version.txt`, `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`, `.forge/project.md`
**Description:** `version.txt` → 0.1.2. README ×3 : une ligne « les raccourcis compagnon portent une pastille de couleur (P/B/O/M) » + note que le rafraîchissement du cache d'icônes Windows peut demander une déconnexion (documenté, jamais exécuté). `project.md` : nouvelles libs et dossier `ico\companion\`. Puis, sur feu vert : commit, merge `master`, `make-release.ps1 -Publish`.
[x] 2026-09-14 — version 0.1.2, README ×3, project.md ; commit c5bbf4e, master fast-forwardé, release v0.1.2 publiée (zip sans ico/companion)

### T7 — Aplat des icônes drapeau
**Effort:** M
**Files:** `.forge/branch/icons/output/20260916-flatten-icon.ps1`, `tmp/flat_icons/`, puis `app/ico/*.ico`
**Description:** Les `.ico` de `app/ico` sont des images raster déposées (pas générées par `make-flag-icons.ps1`) ; un outil GDI+ retraite chaque entrée : cadre extérieur → or plat (reflets supprimés, liserés sombres et ombre extérieure conservés) ; drapeau → bandes plates sans pliures (masque du drapeau par remplissage depuis le cadre intérieur, arrêt sur le contour sombre du logo) ; logo HL intact. Étape 1 : essai sur FR dans `tmp/flat_icons/` (PNG 256 + `.ico`), validation visuelle. Étape 2 : extension aux 27 autres icônes, 6 tailles, puis régénération des pastilles compagnon.
[x] T7.1 — 2026-09-16 : logo HL vectoriel validé (SVG dans output/, cadre or + logo, fond transparent) — le raster aplati a été abandonné au profit du vectoriel
[x] T7.2 — 2026-09-17 : générateur réécrit autour du SVG (resvg + drapeaux GDI+), 29 .ico régénérés, tests verts, docs à jour
[x] 2026-09-17 — Logo vectoriel original (SVG source de vérité) + 29 icônes plates ; reste : contrôle sur le Bureau, version, release

### T8 — Jeux d'icônes sélectionnables
**Effort:** M
**Files:** `app/ico/flat/` (défaut) et `app/ico/classic/` (anciennes icônes restaurées), `app/lib/icon-set.lib.ps1` (nouveau), `app/create-shortcuts.ps1`, `app/lib/launch-config.lib.ps1`, `app/setup.ps1`, `tools/make-flag-icons.ps1`, `tests/icon-set.lib.tests.ps1` (nouveau), `tests/create-shortcuts.tests.ps1`, `tests/setup.tests.ps1`, README ×3, `.forge/project.md`
**Description:** Un jeu d'icônes = un sous-dossier de `app/ico/` contenant `hex-launcher.ico`, découvert dynamiquement (`Get-IconSets`) ; pas de manifeste : le nom du dossier est le nom du jeu, `flat` est le défaut (repli : premier dossier par ordre alphabétique). `setup.bat` (page Raccourcis) propose le jeu, présélection = `iconSet` de `config.json` ou défaut, choix enregistré dans `config.json` puis raccourcis créés avec ce jeu ; mode script `create-shortcuts.ps1 -IconSet classic`. `Resolve-IconPath` cherche dans le jeu choisi, repli sur le jeu par défaut (jeu ou icône absents). Pastilles compagnon nommées avec le jeu. `tools/make-flag-icons.ps1` écrit dans `app/ico/flat`. Tests : découverte (deux jeux, dossier sans hex-launcher.ico ignoré, racine vide), défaut, repli, `iconSet` persisté, liste de la page setup.
[x] T8.1 — 2026-09-17 : app/ico/flat (générées) + app/ico/classic (anciennes restaurées depuis git), lib icon-set (11 tests), générateur vers flat
[x] T8.2 — 2026-09-17 : -IconSet, Set-ActiveIconSet, repli en chaîne, pastilles dans ico/<jeu>/companion (choix utilisateur), iconSet mémorisé par Select-IconSetForConfig, .gitignore et release
[x] T8.3 — 2026-09-17 : liste des jeux + aperçu hex-launcher.ico (PictureBox 64 px) sur la page Raccourcis, icône de fenêtre depuis le jeu par défaut ; 322 tests verts ; README ×3, project.md

## Risks
- `.ico` à entrées DIB (non PNG) : le repli `System.Drawing.Icon` ne rend pas l'entrée 256 px → la lib lève un throw explicite plutôt qu'une icône incomplète ; nos `.ico` actuels sont tous PNG.
- Cache d'icônes Explorer : une pastille modifiée peut ne pas s'afficher avant relance d'Explorer — documenté, pas d'action système.
- Police : `GenericSansSerif` garantit une fonte disponible sans dépendre d'Arial.

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Pastille dans le catalogue | S | [x] |
| T2 — Lib .ico partagée | S | [x] |
| T3 — Composition de la pastille | M | [x] |
| T4 — Raccourcis sur icône composée | S | [x] |
| T5 — Release sans icônes générées | XS | [x] |
| T6 — Version 0.1.2, doc, release | S | [x] |
| T7 — Aplat des icônes drapeau | M | [x] |
| T8 — Jeux d'icônes sélectionnables | M | [x] |
| **Total** | **~XL (8-11 h)** | |
