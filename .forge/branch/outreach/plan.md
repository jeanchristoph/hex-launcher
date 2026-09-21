# Plan — outreach
**Objective:** Mettre Hex Launcher en état d'être diffusé : première impression, confiance, support, découverte par la recherche.
**Date:** 2026-09-21

## Tasks

### T1 — Accroche orientée joueur et GIF de démonstration en tête des README ×3
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `docs/media/demo.gif` (nouveau), `tools/make-release.ps1` (exclusion de `docs/`)
**Description:** Remplacer le paragraphe d'ouverture par une accroche qui part du problème du joueur (« Jouez à LoL en
japonais — ou 26 autres langues — depuis un raccourci, sans toucher aux fichiers du jeu »), texte FR proposé et validé
avant traduction EN/JA. Sous l'accroche, le GIF : double-clic sur le raccourci → splash → client en japonais, ~20 s,
800 px de large, ≤ 5 Mo. L'enregistrement est fait par l'utilisateur (ShareX ou Barre de jeu Windows) sur un script de
tournage fourni dans OUTPUT ; l'accroche est posée sans attendre le GIF, le GIF inséré dès qu'il est fourni.
Hébergé dans `docs/media/` (aussi utilisé par la page T5), dossier exclu de l'archive de release.
[ ]

### T2 — FAQ « Questions fréquentes » dans les README ×3
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`
**Description:** Nouvelle section avant « Dépannage », cinq questions, réponses de deux à quatre lignes, honnêtes :
*Vanguard peut-il me bannir ?* (le jeu n'est pas modifié ; relancer plus de 3 fois en 5 min peut déclencher VAN 216,
le splash prévient) · *Riot autorise-t-il cet outil ?* (non affilié, API locale du Riot Client, aucun avantage en
jeu) · *Windows dit « éditeur inconnu » / SmartScreen* (scripts en clair non signés, SHA-256 et VirusTotal publiés,
comment vérifier) · *Mac ?* (non) · *Ça ne marche plus après un patch Riot* (`launch.log`, ouvrir une issue, message
de compatibilité par patch). Texte FR proposé et validé avant traduction. La section « Confiance » existante reste,
la FAQ y renvoie.
[ ]

### T3 — make-release : lien VirusTotal à côté du SHA-256
**Effort:** S
**Files:** `tools/make-release.ps1`, `tests/make-release.tests.ps1`
**Description:** `Format-ReleaseNotes` ajoute, sous la ligne SHA-256, `VirusTotal report:
https://www.virustotal.com/gui/file/<sha256>` — l'URL est déterministe, aucun appel réseau. Le dépôt du zip sur
VirusTotal reste une étape manuelle avant `gh release create` (section Deployment) ; `make-release` l'affiche en
rappel dans sa sortie. Tests : ligne présente, empreinte en minuscules dans l'URL, ordre SHA-256 → VirusTotal → vérif.
[ ]

### T4 — Templates d'issues, Discussions, topics du dépôt
**Effort:** S
**Files:** `.github/ISSUE_TEMPLATE/bug-report.yml`, `.github/ISSUE_TEMPLATE/language-or-companion-request.yml`,
`.github/ISSUE_TEMPLATE/config.yml` (nouveaux)
**Description:** Formulaires GitHub en anglais (convention), avec une ligne « write in French or English if you
prefer ». Bug : Windows, version Hex Launcher, langue choisie, appli compagnon, contenu de `app\launch.log` (où le
trouver), fenêtre Riot ouverte/repliée. Demande : langue ou appli compagnon à ajouter. `config.yml` : questions →
Discussions. Par `gh` : activer Discussions, ajouter les topics `japanese-voice`, `riot-client`, `locale`,
`game-launcher`. Le dossier `.github/` est exclu de l'archive de release. Aucun réglage Windows.
[ ]

### T5 — Page d'atterrissage GitHub Pages FR/EN
**Effort:** M
**Files:** `docs/index.html`, `docs/fr/index.html`, `docs/style.css` (nouveaux), `docs/media/` (T1)
**Description:** Une page statique par langue, sans build ni framework : `<title>` et H1 = la question du joueur
(« How to play League of Legends with Japanese voices on any server » / « Jouer à LoL avec les voix japonaises sur
n'importe quel serveur »), GIF, trois étapes, FAQ courte (reprise de T2), bouton vers la dernière release, phrase
SHA-256/VirusTotal, non-affiliation Riot, `hreflang` FR/EN, bascule de langue. Thème sobre, cohérent avec le logo HL ;
aucune icône officielle. Activation de Pages depuis `docs/` sur `master` par `gh api`, URL posée en *homepage* du
dépôt. Texte FR validé avant traduction.
[ ]

### T6 — README ES et PT-BR
**Effort:** M
**Files:** `README.es.md`, `README.pt-BR.md` (nouveaux), ligne de langues des README ×3
**Description:** Après stabilisation du texte EN (T1, T2). Traduction complète, mention Riot comprise ; ligne des
langues mise à jour dans les cinq README. L'assistant reste FR/EN/JA (repli EN pour ces utilisateurs) — dit en une
ligne en tête de ces deux README ; l'i18n de l'assistant relève de la branche `translation`.
[ ]

## Risks
- GIF : poids et rendu ; si > 5 Mo, passer en vidéo `.mp4` hébergée comme pièce jointe GitHub.
- VirusTotal : un zip de scripts PowerShell peut récolter un ou deux faux positifs heuristiques — à assumer dans la FAQ
  plutôt qu'à cacher.
- Pages, Discussions, topics, image *social preview* : réglages du dépôt GitHub (pas de Windows) ; l'image *social
  preview* ne se pose que par l'interface web → étape Deployment.
- T1 dépend d'un enregistrement fait par l'utilisateur : l'accroche n'attend pas, le GIF s'insère après.

## Deployment
- [ ] À chaque release, avant `gh release create` : déposer le zip sur virustotal.com (le lien des notes pointe sur l'empreinte) — after T3
- [ ] Image *social preview* 1280×640 (logo HL + accroche) à poser dans Settings → General du dépôt — after T5, `output/AAAAMMJJ-social-preview.png`

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Accroche + GIF README ×3 | S | [ ] |
| T2 — FAQ README ×3 | S | [ ] |
| T3 — make-release : VirusTotal | S | [ ] |
| T4 — Templates d'issues, Discussions, topics | S | [ ] |
| T5 — Page GitHub Pages FR/EN | M | [ ] |
| T6 — README ES et PT-BR | M | [ ] |
| **Total** | **≈ 1 j** | |
