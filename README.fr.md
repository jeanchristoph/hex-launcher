# LoL Lang Switcher

[English](README.md) · **Français** · [日本語](README.ja.md)

Lance League of Legends dans la langue de son choix (japonais, français…) via un raccourci,
avec un petit splash animé, sans console noire. Optionnellement, lance ensuite une application
compagnon (Porofessor, Blitz, OP.GG…).

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `install.bat` | **À double-cliquer** : détecte les emplacements, génère `config.json`, crée les raccourcis sur le Bureau |
| `config.json` | Chemins Riot + appli compagnon. Généré par `install.bat`, éditable à la main si la détection ne suffit pas |
| `locales.json` | Catalogue des langues proposées à l'install (code Riot + libellé affiché) |
| `launch-lol.ps1` | Le lanceur : ferme le client Riot, force la langue, relance le jeu (+ appli compagnon) |
| `detect-config.ps1` | Appelé par `install.bat` : détecte Riot et l'appli compagnon (Porofessor, Blitz, OP.GG) |
| `create-shortcuts.ps1` | Appelé par `install.bat` : boîte de dialogue de choix des langues, puis crée un `.lnk` par langue sur le Bureau (repli dans ce dossier si le Bureau est inaccessible) |
| `make-flag-icons.ps1` | Outil : régénère les icônes drapeau de `ico/` à partir de l'icône Riot (pas nécessaire à l'usage) |
| `ico/` | Icônes : originale Riot + une variante drapeau par langue (`league-of-legends-xx.ico`) |

Les raccourcis `League of Legends XX` (un par langue cochée) sont créés sur le Bureau par `install.bat`.

## Installation sur une nouvelle machine

1. Copier ce dossier où on veut (ex. `Documents\scripts\lol`) — **sans** `config.json` s'il vient
   d'une autre machine, pour que la détection se fasse.
2. Double-cliquer sur **`install.bat`**. Il :
   - détecte le Riot Client (via `RiotClientInstalls.json`, le fichier officiel de Riot) et la
     première appli compagnon installée parmi Porofessor (Overwolf), Blitz, OP.GG — sinon aucune ;
   - écrit `config.json` (jamais écrasé s'il existe déjà : les réglages manuels sont conservés) ;
   - ouvre une **boîte de dialogue** : cocher les langues voulues (JP et FR pré-cochées la première
     fois, ensuite celles déjà installées) puis « Installer » ;
   - crée un raccourci `League of Legends XX` par langue cochée sur le Bureau, et retire ceux des
     langues décochées (obligatoire même sans changement : les `.lnk` contiennent des chemins absolus).
     Si le Bureau est inaccessible (dossier protégé, OneDrive…), ils sont créés dans ce dossier à la place.
3. Double-cliquer sur le raccourci de la langue voulue.

Pour ajouter ou retirer des langues plus tard : relancer `install.bat`, cocher/décocher.

Si la détection s'est trompée ou qu'on utilise une autre appli : éditer `config.json` (voir ci-dessous)
puis relancer `install.bat`. Pour forcer une nouvelle détection : supprimer `config.json` puis relancer.

Au premier lancement dans une nouvelle langue, le Riot Client télécharge le pack de textes + voix
(quelques centaines de Mo). C'est normal.

## `config.json`

```json
{
  "riotClientPath": "C:\\Riot Games\\Riot Client\\RiotClientServices.exe",
  "productSettingsPath": "C:\\ProgramData\\Riot Games\\Metadata\\league_of_legends.live\\league_of_legends.live.product_settings.yaml",
  "companionApp": {
    "enabled": true,
    "name": "Porofessor",
    "path": "C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe",
    "arguments": "-launchapp pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh -from-startmenu"
  }
}
```

Les `\` doivent être doublés (`\\`) — c'est du JSON.

| Clé | Description |
|---|---|
| `riotClientPath` | Chemin de `RiotClientServices.exe`. Par défaut dans `C:\Riot Games\Riot Client\`. |
| `productSettingsPath` | Le fichier yaml où Riot stocke la langue de LoL. Toujours dans `C:\ProgramData\Riot Games\Metadata\…`, sauf installation exotique. |
| `companionApp.enabled` | `true` pour lancer une application après le jeu, `false` pour n'en lancer aucune. |
| `companionApp.name` | Nom affiché dans le splash. Cosmétique. |
| `companionApp.path` | Exécutable à lancer. |
| `companionApp.arguments` | Arguments de lancement. Chaîne vide `""` si aucun. |

Si `path` n'existe pas sur la machine, le lanceur l'ignore et affiche un avertissement dans le splash —
le jeu démarre quand même.

### Exemples d'applications compagnon

**Aucune** :
```json
"companionApp": { "enabled": false }
```

**Porofessor** (via Overwolf) — configuration par défaut ci-dessus.

**Blitz** :
```json
"companionApp": {
  "enabled": true,
  "name": "Blitz",
  "path": "C:\\Users\\<utilisateur>\\AppData\\Local\\Programs\\Blitz\\Blitz.exe",
  "arguments": ""
}
```

**Autre appli Overwolf** : garder `OverwolfLauncher.exe` et remplacer l'identifiant après `-launchapp`
(visible dans les propriétés du raccourci que l'appli a créé dans le menu Démarrer).

**Rendre une appli détectable automatiquement** : ajouter une entrée dans `$CompanionCandidates` de
`detect-config.ps1` (nom, chemin, arguments). L'ordre de la liste est l'ordre de priorité.

## Langues

Toutes les langues que Riot propose sont dans `locales.json` et cochables à l'install. Le raccourci
s'appelle `League of Legends XX` (XX = partie pays du code : `ja_JP` → JP, `ko_KR` → KR).

Icône : `ico/league-of-legends-xx.ico` (xx en minuscules) — toutes les langues du catalogue ont leur
drapeau. Si l'icône manque, l'icône Riot d'origine est utilisée.

Pour une langue absente du catalogue (nouvelle locale Riot) :
1. ajouter une ligne dans `locales.json` avec le code exact tel qu'il apparaît dans `available_locales`
   du fichier yaml ;
2. (optionnel) ajouter le dessin du drapeau dans `$FlagDrawings` de `make-flag-icons.ps1` et lancer
   `powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Locales xx_XX`.

Usage sans boîte de dialogue (script, déploiement) :
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Locales ja_JP,ko_KR
```

## Comment ça marche

Le réglage « Langue » du Riot Client ne change que le lanceur, pas le jeu. La langue de LoL est lue
dans `settings.locale` du fichier `product_settings.yaml`, que le Riot Client réécrit à chaque fermeture.
Le lanceur fait donc, dans l'ordre :

1. Fermer le Riot Client et le client LoL s'ils tournent (sinon la modification serait écrasée).
2. Réécrire `settings.locale` avec la langue demandée (`default_locale`, géré par Riot, n'est pas touché).
3. Lancer le Riot Client avec `--locale=xx_XX` en plus, par sécurité.
4. Lancer l'application compagnon si activée.

## Dépannage

- **Le jeu reste dans l'ancienne langue** : le client Riot tournait encore pendant la réécriture.
  Le lanceur le ferme lui-même, mais si un processus est bloqué, le fermer à la main (zone de
  notification → Quitter) et relancer.
- **Rien ne se passe au double-clic** : ouvrir un terminal PowerShell dans le dossier et lancer
  `.\launch-lol.ps1 -Locale ja_JP` pour voir l'erreur (fichier de config introuvable, chemin faux…).
- **Caractères bizarres dans le splash** (`Ã©`, `â€¦`) : `launch-lol.ps1` a été réenregistré sans BOM.
  Il doit être en **UTF-8 avec BOM** (VS Code : barre d'état → encodage → « Enregistrer avec l'encodage »).
- **L'icône du raccourci n'est pas à jour** : cache d'icônes Windows. Clic droit → Actualiser dans le
  dossier, sinon se déconnecter/reconnecter.
- **Tester sans lancer le jeu** : `.\launch-lol.ps1 -Locale ja_JP -DryRun -YamlPath copie.yaml`
  affiche le splash et réécrit la copie, sans fermer ni lancer quoi que ce soit.
