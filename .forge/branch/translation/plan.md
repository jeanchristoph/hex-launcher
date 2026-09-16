# Plan — translation
**Objective:** Extraire toutes les chaînes utilisateur de l'assistant (`setup.ps1`) et du moteur (`manage-companion-app.ps1`, `create-shortcuts.ps1`, `detect-config.ps1`) dans des dictionnaires JSON FR/EN/JA, langue de Windows par défaut (repli anglais), bascule en direct dans la fenêtre — version 0.1.4.
**Date:** 2026-09-16

## Tasks

### T1 — Bibliothèque i18n (résolution de langue + dictionnaire)
**Effort:** M
**Files:** `app/lib/i18n.lib.ps1` (nouveau), `tests/i18n.lib.tests.ps1` (nouveau)
**Description:** Lib dot-sourcée, même style que `launch-config.lib.ps1`. `$SupportedUiLanguages = @('fr','en','ja')`, `$DefaultUiLanguage = 'en'`. `Resolve-UiLanguage -Requested -WindowsCulture` (pure) : `-Requested` valide → lui ; sinon deux premières lettres de la culture (`fr-CA` → `fr`, `ja-JP` → `ja`) si supportées ; sinon `en`. `Read-TranslationCatalog -Folder -Language` : lit `<Folder>\<lang>.json` en UTF-8 (`ConvertFrom-Json`, clés plates `section.key`), rend une hashtable. `Initialize-Translation -Language [-Folder]` : charge la langue + `en` comme repli dans `$script:Translation`. `Get-Text -Key [-Arguments]` : chaîne de la langue, sinon `en`, sinon la clé elle-même (jamais de throw) ; formatage `.NET -f` sur `{0}`, `{1}`. `Get-UiLanguage` rend la langue active. Tests : résolution (fr-FR, fr-CA, ja-JP, de-DE → en, `-Requested` prioritaire, `-Requested` inconnu ignoré), repli en/clé, formatage, fichier absent → throw explicite.
[x] 2026-09-16 — i18n.lib.ps1 (Resolve-UiLanguage, Initialize-Translation, Get-Text, replis en → clé), 16 tests verts

### T2 — Dictionnaires fr / en / ja
**Effort:** M
**Files:** `app/i18n/fr.json`, `app/i18n/en.json`, `app/i18n/ja.json` (nouveaux), `tests/i18n.catalog.tests.ps1` (nouveau)
**Description:** Inventaire exhaustif des chaînes utilisateur des quatre scripts (titres d'étapes et de pages, boutons, textes d'aide, statuts de détection, bilans, journal, avertissements `Write-Warning`, messages `Write-Host`, `throw` destinés à l'utilisateur, boîtes de dialogue script-mode, sous-titres de splash). Clés par section : `setup.*`, `companion.*`, `shortcuts.*`, `detect.*`, `common.*`. Le français reprend les chaînes actuelles à l'identique ; anglais et japonais rédigés (japonais : registre poli です/ます, termes Riot conservés — « Riot Client », « League of Legends »). Pluriels par clés distinctes (`shortcuts.created.one` / `.many`). Tests de catalogue : les trois fichiers ont exactement le même jeu de clés ; aucune valeur vide ; les placeholders `{n}` de chaque clé sont identiques dans les trois langues ; JSON valide en UTF-8.
[x] 2026-09-16 — fr/en/ja.json, 102 clés en 5 sections, 6 tests de catalogue (clés, placeholders, valeurs, nommage)

### T3 — Assistant `setup.ps1` branché sur les dictionnaires
**Effort:** M
**Files:** `app/setup.ps1`, `tests/setup.tests.ps1`
**Description:** Paramètre `-Language` (optionnel) ; `Initialize-Translation (Resolve-UiLanguage $Language (Get-UICulture).Name)` avant toute construction. Les hashtables `$SetupStepTitles` / `$SetupPageTitles` deviennent des fonctions `Get-SetupStepTitle` / `Get-SetupPageTitle` (réévaluées à chaque affichage, prérequis de T4). Toute chaîne littérale remplacée par `Get-Text`. Dette corrigée au passage : `New-DetectionItem` porte un champ `IsFound` au lieu du statut textuel comparé par regex (`-replace '^Introuvable — '`). Tests existants : langue forcée `fr` dans le bootstrap du fichier de tests (indépendance de la culture de la machine) ; assertions sur les textes maintenues via `Get-Text` ; nouveau test : le titre du bouton Suivant change avec la langue active.
[x] 2026-09-16 — -Language, Get-SetupPageTitle/Get-SetupStepTitle, toutes chaînes via Get-Text, IsFound/MissingReason ; 82 tests setup, suite à 322 verts

### T4 — Sélecteur de langue dans la fenêtre
**Effort:** M
**Files:** `app/setup.ps1`, `app/lib/theme.lib.ps1`, `tests/setup.tests.ps1`, `tests/theme.lib.tests.ps1`
**Description:** `New-ThemedComboBox` dans la lib de thème (palette LoL, `DropDownList`). Sélecteur en bas de la colonne gauche : libellés natifs « Français · English · 日本語 », valeur active présélectionnée. `Set-SetupLanguage -Language` : `Initialize-Translation`, puis `Update-SetupSidebar`, titre de page, `Update-SetupNavigation`, `Show-SetupPage $state.StepId` en conservant les cases cochées : `Get-SetupPageSelection` (pure : clés cochées des listes présentes) lue avant, réinjectée en présélection après (`$state.PendingSelection`, consommée par les pages apps et shortcuts). Bascule gelée pendant `IsBusy`. Tests : `Set-SetupLanguage` change le texte du bouton et des étapes ; sélection conservée après bascule (simulation sans WinForms via `PendingSelection`) ; langue inconnue ignorée.
[x] 2026-09-16 — New-ThemedComboBox, sélecteur natif en bas de colonne, Set-SetupLanguage + PendingSelection, focus/sync combo ; 334 verts, rendu contrôlé fr/en/ja

### T5 — Moteur multilingue (script-mode inclus)
**Effort:** M
**Files:** `app/manage-companion-app.ps1`, `app/create-shortcuts.ps1`, `app/detect-config.ps1`, `tests/manage-companion-app.tests.ps1`, `tests/create-shortcuts.tests.ps1`
**Description:** Chaque script gagne `-Language` (optionnel) et initialise la traduction dans son bloc Main uniquement si `$script:Translation` est vide (dot-sourcé par `setup.ps1`, il hérite de la langue de l'hôte). Chaînes → `Get-Text` : étapes `Write-CompanionStep`, `Write-Warning`, `Write-Host`, `throw` utilisateur, sous-titres de splash, boîtes de dialogue des pickers WinForms script-mode (titres, aides, boutons), `Format-CompanionActions`, `Get-CompanionChoiceLabel`. Tests existants : langue forcée `fr` dans le bootstrap ; assertions via `Get-Text` là où elles portaient sur des chaînes.
[x] 2026-09-16 — -Language sur les 3 scripts, 54 chaînes via Get-Text, notices du catalogue en objet fr/en/ja (Get-LocalizedValue), double encodage UTF-8 du catalogue réparé ; 337 verts + smoke script-mode en/ja

### T6 — Version 0.1.4, documentation, release
**Effort:** S
**Files:** `app/version.txt`, `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`, `.forge/project.md`
**Description:** `version.txt` → 0.1.4. README ×3 : l'assistant parle FR/EN/JA, langue de Windows par défaut, sélecteur dans la fenêtre, paramètre `-Language fr|en|ja` sur `setup.ps1` et les scripts moteur ; `LISEZMOI.txt` idem en deux lignes. `project.md` : lib i18n, dossier `app/i18n/`, convention « aucune chaîne utilisateur littérale dans les scripts ». Puis, sur feu vert : commit, merge `master`, `make-release.ps1 -Publish`.
[x] 2026-09-16 — version 0.1.4, README ×3, LISEZMOI, project.md ; commit 1869d7b, master fast-forwardé, release v0.1.4 publiée (zip avec i18n, sans config.json)

## Risks
- Qualité du japonais : rédigé par Claude, relecture humaine recommandée avant release (registre, longueur des libellés dans les 230 px de la colonne).
- Rendu japonais WinForms : `Segoe UI` n'a pas de glyphes CJK — Windows applique le font linking (Yu Gothic UI) automatiquement ; à contrôler visuellement sur la planche, sinon `New-ThemeFont` bascule sur `Yu Gothic UI` quand la langue active est `ja`.
- Largeur des textes : l'anglais est plus court, le japonais plus compact, mais certains libellés français longs (« Désinstaller les applis décochées présentes sur ce PC ») fixent les gabarits — vérifier chaque page dans les trois langues.
- Culture de la machine de test : sans langue forcée, les tests dépendraient de Windows — d'où le bootstrap `fr` explicite dans chaque fichier de tests.

## Deployment
None

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Lib i18n | M | [x] |
| T2 — Dictionnaires fr/en/ja | M | [x] |
| T3 — setup.ps1 branché | M | [x] |
| T4 — Sélecteur de langue | M | [x] |
| T5 — Moteur multilingue | M | [x] |
| T6 — Version 0.1.4, doc, release | S | [x] |
| **Total** | **~XL (1,5-2 j)** | |
