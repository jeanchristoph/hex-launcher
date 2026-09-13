# hex-launcher

[English](README.md) · **Français** · [日本語](README.ja.md)

> **Projet non affilié à Riot Games.** hex-launcher a été créé dans le cadre de la politique [« Legal Jibber Jabber »](https://www.riotgames.com/en/legal) de Riot Games. Riot Games ne soutient ni ne sponsorise ce projet. League of Legends et Riot Games sont des marques ou marques déposées de Riot Games, Inc. Ce projet n'embarque aucun visuel Riot : ses icônes sont originales.

**Windows uniquement, pour l'instant** (Windows 10/11, PowerShell 5.1 inclus — macOS non pris en charge).

Assistant de lancement League of Legends pour Windows : démarre le jeu dans la langue de son choix
(japonais, français…) depuis un raccourci, avec un petit splash animé et sans console noire, et gère les
**applications compagnon** (Porofessor, Blitz, OP.GG, Mobalytics) — on coche celles qu'on veut, l'outil les
installe, et on obtient un raccourci par langue × appli compagnon
(`League of Legends JP - Blitz`, `League of Legends JP - Porofessor`…).

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `install.bat` | **À double-cliquer** : ouvre l'assistant d'installation (une fenêtre : détection, applis compagnon, raccourcis) |
| `LISEZMOI.txt` | Démarrage rapide en trois lignes (FR/EN) |
| `app/` | Le moteur — rien à y modifier |
| `app/install.ps1` | L'assistant d'installation (fenêtre unique au thème LoL) |
| `app/config.json` | Chemins Riot + liste des applis compagnon. Généré par `install.bat`, éditable à la main si la détection ne suffit pas |
| `app/locales.json` | Catalogue des langues proposées à l'install (code Riot + libellé affiché) |
| `app/companion-apps.json` | Catalogue des applis compagnon : comment détecter, installer, désinstaller et lancer chacune, et qui signe ses binaires |
| `app/launch-lol.ps1` | Le lanceur : ferme le client Riot, force la langue, relance le jeu (+ l'appli compagnon donnée par `-Companion`) |
| `app/detect-config.ps1` | Appelé par `install.bat` : détecte Riot et les applis compagnon déjà installées |
| `app/manage-companion-app.ps1` | Appelé par `install.bat` : choix des applis compagnon, installation des manquantes, désinstallation sur demande |
| `app/create-shortcuts.ps1` | Appelé par `install.bat` : choix des langues et des compagnons, puis un `.lnk` par combinaison sur le Bureau (repli dans ce dossier si le Bureau est inaccessible) |
| `app/lib/companion-app.lib.ps1` | Fonctions partagées : catalogue, détection via le registre (lecture seule), commande de désinstallation, vérification de signature Authenticode |
| `app/lib/launch-config.lib.ps1` | Fonctions partagées : lecture/écriture de `config.json`, migration de l'ancien format à une seule appli |
| `app/lib/splash.lib.ps1` | Splash animé partagé (lancement du jeu, installation des applis compagnon) |
| `tests/` | Tests Pester (`Invoke-Pester -Path tests`) |
| `app/make-flag-icons.ps1` | Outil : régénère les icônes drapeau de `ico/` à partir de l'icône de base originale (pas nécessaire à l'usage) |
| `app/ico/` | Icônes : base originale (monogramme H) + une variante drapeau par langue (`hex-launcher-xx.ico`) |

## Installation sur une nouvelle machine

0. **[Télécharger la dernière version](https://github.com/jeanchristoph/hex-launcher/releases/latest)** (`hex-launcher-x.y.z.zip`) et la décompresser — ou cloner le dépôt.
1. Copier ce dossier où on veut (ex. `Documents\hex-launcher`) — **sans** `config.json` s'il vient
   d'une autre machine, pour que la détection se fasse.
2. Double-cliquer sur **`install.bat`** (jamais « Exécuter en tant qu'administrateur » : l'outil refuse, volontairement). Une fenêtre, trois étapes :
   - **[1/3] Détection** — trouve le Riot Client (via `RiotClientInstalls.json`, le fichier officiel de Riot) et toutes
     les applis compagnon du catalogue déjà installées, puis écrit `config.json` (jamais écrasé s'il existe déjà :
     les réglages manuels sont conservés) ;
   - **[2/3] Applis compagnon** — une boîte de dialogue liste chaque appli du catalogue avec une case à cocher,
     pré-cochée d'après le choix précédent (sinon d'après ce qui est installé). Les applis cochées absentes sont
     installées. Une case à part, **décochée par défaut**, permet aussi de désinstaller les applis décochées
     présentes. Une confirmation liste exactement ce qui va se passer ; « Annuler » ne touche à rien ;
   - **[3/3] Raccourcis** — une boîte de dialogue pour cocher les langues (JP et FR pré-cochées la première fois) et
     les applis compagnon à combiner. Un raccourci par langue × appli est créé sur le Bureau
     (`League of Legends JP - Blitz`) ; sans compagnon coché, simplement `League of Legends JP`. Les raccourcis
     obsolètes de ce lanceur sont retirés. Si le Bureau est inaccessible (dossier protégé, OneDrive…), ils sont
     créés dans ce dossier à la place.
3. Double-cliquer sur le raccourci de la langue et du compagnon voulus.

Pour ajouter ou retirer des langues ou des applis compagnon plus tard : relancer `install.bat`.

Si la détection s'est trompée : éditer `app\config.json` (voir ci-dessous) puis relancer `install.bat`.
Pour forcer une nouvelle détection : supprimer `app\config.json` puis relancer.

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

Icône : chaque raccourci reçoit la variante drapeau de sa langue (`app/ico/hex-launcher-xx.ico`, par exemple
`hex-launcher-jp.ico` pour `ja_JP`). Sans drapeau pour une langue, l'icône de base `app/ico/hex-launcher.ico` est utilisée.

Pour une langue absente du catalogue (nouvelle locale Riot) :
1. ajouter une ligne dans `locales.json` avec le code exact tel qu'il apparaît dans `available_locales`
   du fichier yaml ;
2. (optionnel) ajouter le dessin du drapeau dans `$FlagDrawings` de `make-flag-icons.ps1` et lancer
   `powershell -NoProfile -ExecutionPolicy Bypass -File app\make-flag-icons.ps1 -Locales xx_XX`.

## Comment ça marche

Le réglage « Langue » du Riot Client ne change que le lanceur, pas le jeu. La langue de LoL est lue
dans `settings.locale` du fichier `product_settings.yaml`, que le Riot Client réécrit à chaque fermeture.
Le lanceur fait donc, dans l'ordre :

1. Fermer le Riot Client et le client LoL s'ils tournent (sinon la modification serait écrasée).
2. Réécrire `settings.locale` avec la langue demandée (`default_locale`, géré par Riot, n'est pas touché).
3. Lancer le Riot Client avec `--locale=xx_XX` en plus, par sécurité.
4. Fermer les autres applis compagnon de `config.json`, puis lancer celle nommée par `-Companion`, s'il y en a une.

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
- **« Ne pas exécuter en tant qu'administrateur »** : `install.bat` a été lancé élevé. Le lancer normalement.
- **« winget indisponible »** : App Installer manque sur ce Windows. L'installer depuis le Microsoft Store,
  ou laisser l'outil ouvrir la page de téléchargement de Blitz dans le navigateur.
- **« désinstalleur … non signé »** : le désinstalleur trouvé dans le registre n'est pas signé par l'éditeur attendu ;
  l'outil ne le lance pas. Désinstaller l'appli depuis « Applications installées » de Windows.
- **L'appli compagnon est toujours là après « Désinstaller »** : le dialogue de l'éditeur a été fermé sans
  confirmer (Overwolf), ou la désinstallation a pris plus de temps que prévu. Rien d'autre n'a été installé ;
  relancer `install.bat`.
- **Tester sans lancer le jeu** : `.\app\launch-lol.ps1 -Locale ja_JP -DryRun -YamlPath copie.yaml`
  affiche le splash et réécrit la copie, sans fermer ni lancer quoi que ce soit.
  `app\manage-companion-app.ps1 -DryRun` affiche les actions appli compagnon sans les exécuter.
