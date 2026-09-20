# Hex Launcher

[English](README.md) · **Français** · [日本語](README.ja.md)

> **Projet non affilié à Riot Games.** Riot Games ne soutient ni ne sponsorise ce projet. League of Legends et Riot Games sont des marques ou marques déposées de Riot Games, Inc.

**Windows uniquement, pour l'instant** (Windows 10/11, PowerShell 5.1 inclus — macOS non pris en charge).

Assistant de lancement League of Legends pour Windows : démarre le jeu dans la langue de son choix
(japonais, français…) depuis un raccourci, avec un petit splash animé et sans console noire, et gère les
**applications compagnon** (Porofessor, Blitz, OP.GG, Mobalytics) — on coche celles qu'on veut, l'outil les
installe, et on obtient un raccourci par langue × appli compagnon
(`League of Legends JP - Blitz`, `League of Legends JP - Porofessor`…).

> **Aucune donnée collectée, aucune télémétrie, aucun compte.** L'outil ne parle qu'au Riot Client de votre PC, ne va sur
> Internet que pour une appli compagnon que vous avez cochée, refuse le mode administrateur et n'installe rien sans votre
> clic sur *Appliquer*. `setup.bat` tient en une ligne, tout le code est en clair. Détails : [Confiance](#confiance--ce-que-fait-setupbat-ce-quil-ne-fait-pas).

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `setup.bat` | **À double-cliquer** (ex-`install.bat`) : ouvre l'assistant de configuration (une fenêtre : détection, applis compagnon, raccourcis) |
| `LISEZMOI.txt` | Démarrage rapide en trois lignes (FR/EN) |
| `app/` | Le moteur — rien à y modifier |
| `app/setup.ps1` | L'assistant de configuration (fenêtre unique au thème LoL) |
| `app/config.json` | Chemins Riot + liste des applis compagnon. Généré par `setup.bat` ; les chemins Riot se corrigent sur sa page *Bienvenue* (saisie ou *Parcourir…*), jamais à la main |
| `app/locales.json` | Catalogue des langues proposées à l'install (code Riot + libellé affiché) |
| `app/companion-apps.json` | Catalogue des applis compagnon : comment détecter, installer, désinstaller et lancer chacune, et qui signe ses binaires |
| `app/launch-lol.ps1` | Le lanceur : ferme le client Riot, force la langue, relance le jeu (+ l'appli compagnon donnée par `-Companion`) |
| `app/detect-config.ps1` | Appelé par `setup.bat` : détecte Riot et les applis compagnon déjà installées |
| `app/manage-companion-app.ps1` | Appelé par `setup.bat` : choix des applis compagnon, installation des manquantes, désinstallation sur demande |
| `app/create-shortcuts.ps1` | Appelé par `setup.bat` : choix des langues et des compagnons, puis un `.lnk` par combinaison sur le Bureau (repli dans ce dossier si le Bureau est inaccessible) |
| `app/lib/companion-app.lib.ps1` | Fonctions partagées : catalogue, détection via le registre (lecture seule), commande de désinstallation, vérification de signature Authenticode |
| `app/lib/icon.lib.ps1` / `icon-badge.lib.ps1` | Lecture/écriture des `.ico`, icône d'un binaire lue en mémoire, composition des pastilles compagnon et pays |
| `app/lib/flag.lib.ps1` / `riot-install.lib.ps1` | Drapeaux dessinés en GDI+ (une seule définition pour les icônes et les pastilles pays) ; Riot Client et `LeagueClient.exe` lus dans `RiotClientInstalls.json` |
| `app/lib/i18n.lib.ps1` / `app/i18n/` | Traductions de l'assistant et de la console : un dictionnaire `fr.json` / `en.json` / `ja.json` par langue, mêmes clés partout |
| `app/lib/launch-config.lib.ps1` | Fonctions partagées : lecture/écriture de `config.json`, migration de l'ancien format à une seule appli |
| `app/lib/splash.lib.ps1` | Splash animé partagé (lancement du jeu, installation des applis compagnon) |
| `tests/` | Tests Pester (`Invoke-Pester -Path tests`) |
| `tools/` | Développement uniquement, hors release : `make-release.ps1`, `make-flag-icons.ps1` (régénère toutes les icônes de `app/ico/` depuis le logo vectoriel), `logo/make-logo-svg.py` + `logo/hex-launcher-logo-drawing.png` → `logo/hex-launcher-logo.svg` (logo HL original, source de vérité) |
| `app/ico/` | Jeux d'icônes, un dossier chacun : `flat/` (défaut : drapeau plat derrière le logo HL) et `classic/` (les anciennes icônes en relief) ; chacun contient l'icône de base + une variante drapeau par langue (`hex-launcher-xx.ico`) et un sous-dossier généré `companion/` avec les icônes drapeau + pastille composées sur ce poste. `original/` et `original-badges/` ne contiennent qu'un marqueur `icon-source.json` : l'icône officielle du jeu, référencée depuis `LeagueClient.exe` installé — nue, ou avec pastilles pays et compagnon composées sur ce poste |

## Confiance — ce que fait `setup.bat`, ce qu'il ne fait pas

Cliquer sur un `.bat` inconnu fait peur, à juste titre. Voici de quoi vérifier par vous-même :

- **Il se lit.** `setup.bat` tient en une ligne — ouvrez-le dans le Bloc-notes : il ouvre `app\setup.ps1`, sans console.
  Tout le code est dans `app\`, en clair (PowerShell), identique à ce dépôt public.
- **Aucune donnée collectée, aucune télémétrie, aucun compte, aucun serveur.** Hex Launcher ne parle qu'au Riot Client
  de *votre* PC (`127.0.0.1`, son API locale) et ne contacte Internet que pour télécharger une appli compagnon *que
  vous avez cochée*, depuis le site de son éditeur ou winget. Le journal `app\launch.log` reste dans le dossier.
- **Jamais administrateur** : lancé « en tant qu'administrateur », il refuse. Registre Windows lu seulement (pour
  détecter les applis déjà installées), jamais écrit. Il n'écrit que dans son propre dossier (`config.json`, icônes
  composées), sur le Bureau (les raccourcis) et, le temps d'une installation que vous avez demandée, l'installeur de
  l'appli compagnon dans le dossier temporaire de Windows.
- **Rien sans votre clic.** Une appli compagnon n'est installée ou désinstallée qu'après *Appliquer*, la liste exacte
  des actions étant affichée avant. La page d'accueil ne modifie rien.
- **Le jeu n'est pas modifié.** Seule la langue change, par l'API officielle locale du Riot Client (ce que fait son
  propre réglage) ; aucun fichier de League of Legends n'est touché.
- **Vérifiable.** Chaque release publie l'empreinte SHA-256 de son zip ; comparez avec
  `Get-FileHash hex-launcher-x.y.z.zip` dans PowerShell. Le code source est ce dépôt.

## Mise en route sur une nouvelle machine

0. **[Télécharger la dernière version](https://github.com/jeanchristoph/hex-launcher/releases/latest)** (`hex-launcher-x.y.z.zip`) et la décompresser — ou cloner le dépôt.
1. Copier ce dossier où on veut (ex. `Documents\hex-launcher`) — **sans** `config.json` s'il vient
   d'une autre machine, pour que la détection se fasse.
2. Double-cliquer sur **`setup.bat`** (jamais « Exécuter en tant qu'administrateur » : l'outil refuse, volontairement). Une fenêtre, trois étapes :
   - **[1/3] Détection** — trouve le Riot Client (via `RiotClientInstalls.json`, le fichier officiel de Riot) et toutes
     les applis compagnon du catalogue déjà installées, puis écrit `config.json` (jamais écrasé s'il existe déjà :
     les réglages manuels sont conservés). Les deux chemins Riot sont affichés dans des champs modifiables avec un
     bouton *Parcourir…* : un chemin faux se corrige sur place, est enregistré sur *Suivant*, et reste signalé en
     rouge tant qu'il ne mène pas à un vrai fichier ;
   - **[2/3] Applis compagnon** — une boîte de dialogue liste chaque appli du catalogue avec une case à cocher,
     pré-cochée d'après le choix précédent (sinon d'après ce qui est installé). Les applis cochées absentes sont
     installées. Une case à part, **décochée par défaut**, permet aussi de désinstaller les applis décochées
     présentes. Une confirmation liste exactement ce qui va se passer ; « Annuler » ne touche à rien ;
   - **[3/3] Raccourcis** — une boîte de dialogue pour cocher les langues (JP et FR pré-cochées la première fois) et
     les applis compagnon à combiner. Un raccourci par langue × appli est créé sur le Bureau
     (`League of Legends JP - Blitz`) ; sans compagnon coché, simplement `League of Legends JP`. Les raccourcis
     obsolètes de ce lanceur sont retirés. Si le Bureau est inaccessible (dossier protégé, OneDrive…), ils sont
     créés dans ce dossier à la place. Un raccourci **Hex Launcher** (icône engrenage) est posé
     au même endroit : il rouvre cet assistant.
3. Double-cliquer sur le raccourci de la langue et du compagnon voulus.

Pour ajouter ou retirer des langues ou des applis compagnon plus tard : double-cliquer sur **Hex Launcher**
(ou relancer `setup.bat`).

L'assistant lui-même parle **français, anglais et japonais** : il s'ouvre dans la langue d'affichage de Windows
(anglais pour toute autre langue) et le sélecteur en bas de la colonne de gauche bascule à tout moment sans
perdre ce qui est coché. Pour forcer une langue : `powershell -File app\setup.ps1 -Language ja`
(même paramètre `-Language fr|en|ja` sur `detect-config.ps1`, `manage-companion-app.ps1` et `create-shortcuts.ps1`).

Si la détection s'est trompée : relancer `setup.bat` et corriger le chemin sur la page *Bienvenue* — il n'y a
jamais besoin d'ouvrir `config.json`. Pour forcer une nouvelle détection : supprimer `app\config.json` puis relancer.

Au premier lancement dans une nouvelle langue, le Riot Client télécharge le pack de textes + voix
(quelques centaines de Mo). C'est normal.

## Applications compagnon

Plusieurs applis compagnon peuvent cohabiter ; chaque raccourci en lance exactement une après le jeu, et
**ferme d'abord les autres** (deux overlays en même temps entrent en conflit) — un raccourci sans compagnon les ferme toutes.
Pour Porofessor, cela revient à fermer le client Overwolf.
Rien n'est jamais désinstallé sans avoir coché la case « désinstaller » (ou passé `-UninstallOthers`).

| Appli | Installation | Désinstallation |
|---|---|---|
| **Porofessor** (Overwolf) | Installeur officiel Overwolf, silencieux (~10 s) quand Overwolf est déjà présent. Sans Overwolf, sa fenêtre d'installation s'affiche : suivez-la (~1 min, une invite UAC est probable) | **Interactive** : Overwolf ouvre son propre menu de désinstallation avec *Overwolf* **et** *Porofessor* cochés. Décochez Overwolf si vous l'utilisez pour d'autres applis, puis cliquez sur Uninstall. L'outil ne décide jamais à votre place |
| **Blitz** | `winget install Blitz.Blitz`, silencieux (~15 s) | Silencieuse |
| **OP.GG** | Installeur officiel depuis `op.gg`, silencieux (~10 s) | Silencieuse |
| **Mobalytics** | Installeur officiel autonome depuis `mobalytics.gg`, silencieux (~10 s) | Silencieuse |

Règles de sûreté, toutes appliquées par le code :
- l'outil refuse de tourner élevé (administrateur) — les installeurs sont per-user, et les commandes de
  désinstallation sont lues dans le registre utilisateur, que n'importe quel programme à vous pourrait altérer ;
- tout binaire exécuté — installeur téléchargé **ou** désinstalleur lu dans le registre — doit porter une signature
  Authenticode valide émise pour l'éditeur nommé dans le catalogue (`Overwolf Ltd`/IL, `OP.GG`/KR,
  `Swift Media Entertainment, Inc.`/US pour Blitz, `GAMERS NET, INC.`/US pour Mobalytics). Non signé ou éditeur
  inattendu → refusé, avec un message renvoyant vers « Applications installées » de Windows ;
- l'outil lui-même n'écrit jamais dans le registre Windows : il **lit** seulement les clés `Uninstall` ;
- si l'installeur lance l'appli à la fin (Mobalytics), elle est refermée — elle démarrera avec le jeu.

Si l'installation automatique est impossible (winget absent, réseau coupé), la page de téléchargement officielle
s'ouvre dans le navigateur : installez l'appli vous-même, le lanceur la prend en compte dès qu'elle existe.

Après la désinstallation d'une appli Overwolf, Overwolf ouvre une page de feedback dans le navigateur ; la fermer suffit.

Usage scripté (déploiement) :
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps blitz,opgg                   # dialogue de confirmation
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps blitz -UninstallOthers -Force # aucun dialogue
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps none -DryRun                 # montre ce qui serait fait
powershell -NoProfile -ExecutionPolicy Bypass -File app\create-shortcuts.ps1 -Locales ja_JP,ko_KR -Companions blitz,opgg
```
Identifiants : `porofessor`, `blitz`, `opgg`, `mobalytics`, `none`. Codes de sortie : 0 ok · 1 erreur · 2 annulé ou refusé.

### Ajouter une appli au catalogue

Une entrée dans `companion-apps.json` ; l'ordre de la liste est la priorité de détection.

```json
{
  "id": "opgg",
  "name": "OP.GG",
  "signer":       { "organization": "OP.GG", "country": "KR" },
  "badge":        { "glyph": "O", "color": "#1FA8D8" },
  "processNames": ["OP.GG"],
  "launch":    { "path": "%LOCALAPPDATA%\\Programs\\OP.GG\\OP.GG.exe", "arguments": "" },
  "detect":    { "registryDisplayNamePattern": "^OP\\.GG", "path": "%LOCALAPPDATA%\\Programs\\OP.GG\\OP.GG.exe" },
  "install":   { "strategy": "download", "url": "https://op.gg/desktop/download/latest", "arguments": "/S /currentuser",
                 "timeoutSeconds": 180, "fallback": "browser", "browserUrl": "https://op.gg/desktop" },
  "uninstall": { "mode": "silent" }
}
```

| Clé | Description |
|---|---|
| `signer.organization` / `signer.country` | `O=` et `C=` du certificat de signature de code de l'éditeur, exacts et sensibles à la casse. À lire avec `Get-AuthenticodeSignature <exe>` → `SignerCertificate.Subject`. Obligatoire pour chaque appli : installeurs et désinstalleurs sont refusés sinon |
| `badge.glyph` / `badge.color` / `badge.glyphColor` | Pastille des raccourcis de cette appli : une lettre (deux au plus) sur un disque de couleur `#RRGGBB`, dessinée par le lanceur — jamais un logo tiers. `glyphColor` (optionnel) fixe la couleur de la lettre ; sinon elle est sombre sur disque clair, blanche sur disque sombre. Pastille absente ou invalide : le raccourci garde l'icône drapeau seule |
| `processNames` | Process fermés avant une désinstallation, et après une installation qui a lancé l'appli |
| `launch.path` / `launch.arguments` | Ce que le lanceur démarre après le jeu. Les variables `%VAR%` sont résolues |
| `detect.registryDisplayNamePattern` | Regex comparée au `DisplayName` des clés `Uninstall` du registre (HKLM, HKLM\WOW6432Node, HKCU). OP.GG et Mobalytics mettent leur version dans le nom, d'où des motifs par préfixe |
| `detect.path` | Repli : l'appli est considérée installée si ce chemin existe |
| `install.strategy` | `winget` (+ `wingetId`), `download` (+ `url` en https, `arguments`) ou `browser` (+ `browserUrl` en https) |
| `install.fallback` | Stratégie utilisée si la principale échoue (en général `browser`) ; ses propres champs sont requis aussi |
| `install.notice` | Texte affiché dans la confirmation avant installation (ex. la note sur le setup Overwolf) |
| `install.timeoutSeconds` | Attente maximale de l'apparition de l'appli après le retour de l'installeur (les codes de sortie ne sont pas fiables : désinstalleurs NSIS asynchrones, Overwolf renvoie 1223 même en succès). Obligatoire, > 0 |
| `uninstall.mode` | `silent` (`QuietUninstallString`, sinon `UninstallString` + `/S`) ou `interactive` (`UninstallString` telle quelle, l'éditeur affiche son propre dialogue) |
| `uninstall.dialogProcessNames` | Mode interactif : process du dialogue de l'éditeur à attendre (Overwolf : `OWUninstallMenu`) |
| `uninstall.notice` | Texte affiché dans la confirmation avant désinstallation (ex. l'avertissement Overwolf) |

## `app\config.json`

```json
{
  "riotClientPath": "C:\\Riot Games\\Riot Client\\RiotClientServices.exe",
  "productSettingsPath": "C:\\ProgramData\\Riot Games\\Metadata\\league_of_legends.live\\league_of_legends.live.product_settings.yaml",
  "companionApps": [
    { "id": "porofessor", "name": "Porofessor", "path": "C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe",
      "arguments": "-launchapp pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh -from-startmenu" },
    { "id": "blitz", "name": "Blitz", "path": "C:\\Users\\<utilisateur>\\AppData\\Local\\Programs\\Blitz\\Blitz.exe", "arguments": "" }
  ]
}
```

Les `\` doivent être doublés (`\\`) — c'est du JSON. `companionApps` est écrit par `manage-companion-app.ps1`
depuis le catalogue ; on peut toujours ajouter une entrée à la main pour une appli hors catalogue (n'importe quel
`id`, utilisé par `-Companion`). Un `config.json` d'une version antérieure (bloc unique `companionApp`) est migré
automatiquement à la prochaine lecture.

| Clé | Description |
|---|---|
| `riotClientPath` | Chemin de `RiotClientServices.exe`. Par défaut dans `C:\Riot Games\Riot Client\`. |
| `productSettingsPath` | Le fichier yaml où Riot stocke la langue de LoL. Toujours dans `C:\ProgramData\Riot Games\Metadata\…`, sauf installation exotique. |
| `companionApps[].id` | Identifiant utilisé par les raccourcis (`launch-lol.ps1 -Companion <id>`). |
| `companionApps[].name` | Nom affiché dans le splash. Cosmétique. |
| `companionApps[].path` | Exécutable à lancer. |
| `companionApps[].arguments` | Arguments de lancement. Chaîne vide `""` si aucun. |

Si un `path` n'existe pas sur la machine, le lanceur l'ignore et affiche un avertissement dans le splash —
le jeu démarre quand même. Idem si un raccourci demande un `id` absent de la liste.

**Autre appli Overwolf** : garder `OverwolfLauncher.exe` et remplacer l'identifiant après `-launchapp`
(visible dans les propriétés du raccourci que l'appli a créé dans le menu Démarrer).

## Langues

Toutes les langues que Riot propose sont dans `locales.json` et cochables à l'install. Le raccourci
s'appelle `League of Legends XX` (XX = partie pays du code : `ja_JP` → JP, `ko_KR` → KR), suivi de
` - <appli compagnon>` quand une appli lui est attachée.

Icône : chaque raccourci reçoit la variante drapeau de sa langue dans le jeu d'icônes choisi (`app/ico/<jeu>/hex-launcher-xx.ico`,
par exemple `hex-launcher-jp.ico` pour `ja_JP`) ; sans drapeau → l'icône de base du jeu, puis le jeu par défaut. Le jeu se
choisit sur la page *Raccourcis* de `setup.bat` (avec un aperçu de son icône de base) et reste mémorisé dans `config.json`
(`iconSet`) ; en mode script : `create-shortcuts.ps1 -IconSet classic`. Tout dossier déposé dans `app/ico/` qui contient
un `hex-launcher.ico` devient un jeu sélectionnable. Les jeux livrés s'affichent dans un ordre fixe et sous un libellé
traduit (« LoL officielle + pastilles », « LoL officielle, nue », « Classique (relief) », « Drapeau plat + logo HL ») ;
un jeu ajouté s'affiche après, sous le nom de son dossier. Installation neuve : `original-badges` est présélectionné ;
`flat` reste le jeu de repli (icône de fenêtre, drapeau manquant, LoL introuvable).
Un raccourci avec appli compagnon porte en plus une pastille de couleur en haut à droite — P Porofessor, B Blitz,
O OP.GG, M Mobalytics — composée à l'installation dans `app/ico/<jeu>/companion/` (la lettre disparaît sous 32 px, la couleur reste).
Les couleurs de pastille sont celles du catalogue ; un jeu peut les styler par un `badge-style.json` dans son dossier :
`{ "nightVeil": true, "reducedPalette": false }` — voile nuit des drapeaux et/ou leur palette réduite (`flat` prend le
voile, `classic` ni l'un ni l'autre). Les deux jeux livrés portent le fichier avec toutes les clés explicites, modèle pour un nouveau jeu.

Deux jeux « externes » utilisent l'icône officielle de League of Legends, référencée depuis le `LeagueClient.exe` installé
(dossier lu dans `RiotClientInstalls.json`) — jamais copiée dans le projet, jamais distribuée :
- `original` : l'icône nue (`IconLocation` pointe sur le binaire). Les raccourcis ne se distinguent alors que par leur nom.
- `original-badges` : l'icône surmontée d'une pastille pays (drapeau miniature, couleurs officielles brutes) puis, en dessous,
  de la pastille compagnon ; sous 32 px seule la pastille pays subsiste. Le `.ico` composé est écrit dans
  `app/ico/original-badges/companion/`, propre à ce poste et hors release.
Un tel jeu est un dossier sans `.ico`, marqué par `icon-source.json` : `{ "source": "league-client", "badges": true }`.
Si `LeagueClient.exe` est introuvable, les raccourcis reçoivent les icônes du jeu par défaut.

Pour une langue absente du catalogue (nouvelle locale Riot) :
1. ajouter une ligne dans `locales.json` avec le code exact tel qu'il apparaît dans `available_locales`
   du fichier yaml ;
2. (optionnel) ajouter le dessin du drapeau dans `$FlagDrawings` de `app/lib/flag.lib.ps1` (il sert aux icônes et à la
   pastille pays) et lancer `powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-flag-icons.ps1 -Locales xx_XX`.

### Icônes

Le jeu `flat` est construit à partir du logo vectoriel `tools/logo/hex-launcher-logo.svg` (cadre or +
monogramme HL + gemme, fond transparent) : `tools/make-flag-icons.ps1` le rend avec `resvg` à 256/128/64/48/32/16 px et le
compose sur un drapeau plat atténué, dessiné en GDI+ (`$FlagDrawings` de `app/lib/flag.lib.ps1`) et découpé à l'intérieur du cadre, dans `app/ico/flat/`. Nécessite `resvg` dans le PATH
(`scoop install resvg`) ; tout régénérer avec `powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-flag-icons.ps1`
(`-Base` pour les seules icônes unies bleue/verte, `-PreviewDir` pour obtenir aussi des PNG 256 px). Le SVG lui-même
est produit par `python tools\logo\make-logo-svg.py` depuis le dessin de référence `tools/logo/hex-launcher-logo-drawing.png`
(Python 3, Pillow, numpy, `potrace` et `resvg` dans le PATH ; `--preview DOSSIER` écrit des planches de contrôle). Le drapeau est
atténué pour que le logo ressorte : chaque couleur de drapeau est ramenée à une palette de 8 teintes (`$FlagPalette`),
puis le bloc `$Background` applique `Saturation` 0,72 et un voile nuit (`VeilAlpha` 60/255).

## Comment ça marche

Le réglage « Langue » du Riot Client ne change que le lanceur, pas le jeu. La langue de LoL est lue
dans `settings.locale` du fichier `product_settings.yaml`, que le Riot Client réécrit à chaque fermeture.
Le lanceur fait donc, dans l'ordre :

1. Fermer le client de jeu s'il tourne. Le Riot Client, lui, est laissé allumé — et démarré s'il ne l'est pas.
2. Poser la langue par l'API locale du Riot Client, qui écrit alors `settings.locale` lui-même
   (écrire ce fichier dans son dos ne tient pas : il le réécrit depuis sa mémoire en quelques secondes).
3. Lui demander le jeu par la même API — l'équivalent du clic sur **Play** — puis vérifier que le client de
   jeu apparaît vraiment avant de considérer que c'est gagné.
4. À défaut : le démarrage manuel reprend la main — tout Riot fermé, `settings.locale` réécrit
   (`default_locale`, géré par Riot, n'est jamais touché), relance avec `--launch-product`, et c'est à vous
   d'appuyer sur **Jouer** dans le Riot Client : le lanceur n'échoue jamais. `-NoLocalApi` force ce démarrage manuel.
   Si l'attente s'éternise (plus de 15 s), le splash propose **Forcer en démarrage manuel** : un clic passe en
   démarrage manuel pour ce lancement seulement — rien n'est mémorisé.
5. Fermer les autres applis compagnon de `config.json`, puis lancer celle nommée par `-Companion`, s'il y en a une.

Le lanceur n'a pas de mémoire : le lancement direct est tenté à chaque fois. S'il échoue régulièrement sur votre
poste, cochez « Démarrage manuel — appuyer sur Jouer dans Riot » dans `setup.bat` — le lanceur y passe alors d'emblée.

## Fabriqué avec claude_forge

Ce lanceur a été développé avec [Claude Code](https://claude.com/claude-code) et le skill
**[claude_forge](https://github.com/jeanchristoph/claude_forge)** : un workflow de développement par branche —
brief validé avant la première ligne de code, plan structuré, journal des décisions tenu en temps réel, tests écrits
en même temps que le code. Les fichiers de suivi sont dans `.forge/` : chaque branche y garde son brief, son plan et son
journal, lisibles par n'importe qui.

## Développer

Utiliser le lanceur ne demande rien de plus que Windows 10/11. Contribuer, si :

| Besoin | Outil | Origine |
|---|---|---|
| Exécuter les scripts, interface WinForms, dessin GDI+ | Windows PowerShell 5.1, .NET Framework (`System.Drawing`, `System.Windows.Forms`) | intégrés à Windows |
| Tests | Pester 3.4 | livré avec Windows PowerShell 5.1 |
| Régénérer le jeu d'icônes `flat` (`tools/make-flag-icons.ps1`) | `resvg` (SVG → PNG) | `scoop install resvg` |
| Régénérer le logo SVG (`tools/logo/make-logo-svg.py`) | Python 3 avec Pillow et numpy, `potrace` (PNG → SVG), `resvg` | `pip install pillow numpy` · `scoop install potrace resvg` |
| Publier une release (`tools/make-release.ps1 -Publish`) | GitHub CLI `gh`, authentifié | `scoop install gh` ou https://cli.github.com |

Tout ce qui est dans `tools/` et `tests/` reste hors du zip de release. Les couleurs des drapeaux passent par la palette
réduite et l'atténuation de `app/lib/palette.lib.ps1` ; les pastilles compagnon n'en prennent le voile nuit et/ou la palette réduite que dans les jeux qui le demandent (`badge-style.json`).

## Tests

Pester 3.4 est livré avec Windows PowerShell 5.1 — rien à installer :
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path tests"
```
Installeurs, désinstalleurs, réseau et registre sont mockés : les tests ne touchent jamais à la machine.

## Dépannage

- **Le jeu reste dans l'ancienne langue** : le client Riot tournait encore pendant la réécriture.
  Le lanceur le ferme lui-même, mais si un processus est bloqué, le fermer à la main (zone de
  notification → Quitter) et relancer.
- **Rien ne se passe au double-clic** : ouvrir un terminal PowerShell dans le dossier et lancer
  `.\app\launch-lol.ps1 -Locale ja_JP` pour voir l'erreur (fichier de config introuvable, chemin faux…).
- **Caractères bizarres dans le splash ou les dialogues** (`Ã©`, `â€¦`) : un `.ps1` a été réenregistré sans BOM.
  Tous les scripts (`launch-lol.ps1`, `manage-companion-app.ps1`, `create-shortcuts.ps1`, `lib\*.ps1`) doivent
  être en **UTF-8 avec BOM** (VS Code : barre d'état → encodage → « Enregistrer avec l'encodage »).
- **L'icône du raccourci n'est pas à jour** : cache d'icônes Windows. Clic droit → Actualiser dans le
  dossier, sinon se déconnecter/reconnecter.
- **« Ne pas exécuter en tant qu'administrateur »** : `setup.bat` a été lancé élevé. Le lancer normalement.
- **« winget indisponible »** : App Installer manque sur ce Windows. L'installer depuis le Microsoft Store,
  ou laisser l'outil ouvrir la page de téléchargement de Blitz dans le navigateur.
- **« désinstalleur … non signé »** : le désinstalleur trouvé dans le registre n'est pas signé par l'éditeur attendu ;
  l'outil ne le lance pas. Désinstaller l'appli depuis « Applications installées » de Windows.
- **L'appli compagnon est toujours là après « Désinstaller »** : le dialogue de l'éditeur a été fermé sans
  confirmer (Overwolf), ou la désinstallation a pris plus de temps que prévu. Rien d'autre n'a été installé ;
  relancer `setup.bat`.
- **Tester sans lancer le jeu** : `.\app\launch-lol.ps1 -Locale ja_JP -DryRun -YamlPath copie.yaml`
  affiche le splash et réécrit la copie, sans fermer ni lancer quoi que ce soit.
  `app\manage-companion-app.ps1 -DryRun` affiche les actions appli compagnon sans les exécuter.
