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
[ ] 2026-09-14 — version 0.1.2, README ×3, project.md faits (LISEZMOI.txt inchangé : rien à y dire) ; reste commit + merge + release sur feu vert

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
| T6 — Version 0.1.2, doc, release | S | [ ] |
| **Total** | **~L (4-6 h)** | |
