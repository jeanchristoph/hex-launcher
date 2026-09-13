# Étude de faisabilité — gestion des applications compagnon

**Date :** 2026-09-13 · **Branche :** `companion-apps` · **Machine de test :** Windows 11 Home 10.0.26200, PowerShell 5.1, winget 1.29

## Question

`install.bat` peut-il proposer une application compagnon (Porofessor, Blitz, OP.GG…), l'installer automatiquement et désinstaller la précédente, en restant dans l'univers Windows (winget, registre en lecture seule, PowerShell 5.1) ?

## Verdict : GO

Faisable pour les trois applis cibles, avec un niveau d'automatisation différent selon l'appli :

| Appli | Installation | Silencieux | Désinstallation | Silencieux | Stratégie retenue |
|---|---|---|---|---|---|
| **Blitz** | `winget install Blitz.Blitz` | ✅ testé, 14 s | `winget uninstall Blitz.Blitz` ou `QuietUninstallString` | ✅ testé | `winget` (repli `download`) |
| **OP.GG** | `OP.GG Setup x.y.z.exe /S /currentuser` | ✅ testé, 8-12 s | `Uninstall OP.GG.exe /currentuser /S` | ✅ testé, 12 s | `download` |
| **Porofessor** | `Porofessor.gg - Installer.exe /S` | ✅ testé sur install fraîche, 10 s | `OWUninstaller.exe --uninstall-app=<id>` | ❌ menu Overwolf interactif (par conception) | `download` silencieux / désinstall **interactive** |
| **Mobalytics** | `Mobalytics-Setup-latest.exe /S` | ✅ testé, 11 s (lance l'appli à la fin → refermée) | `Uninstall Mobalytics.exe /currentuser /S` | ✅ testé, 9 s | `download` |
| U.GG | app Overwolf, page en 403 pour les robots | ❌ | `OWUninstaller.exe --uninstall-app=<id>` | ⚠️ | `browser` (bonus) |

## Mécanisme commun

### Détection et désinstallation : registre `Uninstall`, lecture seule

Chaque installeur crée sa propre clé sous `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\<guid>` (per-user : Blitz, OP.GG, **Porofessor** — l'app Overwolf est enregistrée par utilisateur) ou `HKLM\...\WOW6432Node\...\Uninstall\<nom>` (per-machine : Overwolf lui-même). Toujours lire les trois ruches : HKLM, HKLM\WOW6432Node, HKCU. Le script **lit** `DisplayName`, `DisplayVersion`, `QuietUninstallString`, `UninstallString` — il n'écrit jamais dans le registre (règle projet).

Valeurs relevées sur la machine de test :

```
Blitz          HKCU  DisplayName=Blitz            Quiet="…\Programs\Blitz\Uninstall Blitz.exe" /currentuser /S
OP.GG          HKCU  DisplayName=OP.GG 2.5.5      Quiet="…\Programs\OP.GG\Uninstall OP.GG.exe" /currentuser /S
Porofessor.gg  HKCU  DisplayName=Porofessor.gg    Uninstall=C:\Program Files (x86)\Overwolf\OWUninstaller.exe --uninstall-app=pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh
Overwolf       HKLM  DisplayName=Overwolf         Uninstall="C:\Program Files (x86)\Overwolf\OWUninstaller.exe" /S
```

⚠️ `DisplayName` d'OP.GG contient la version → matcher par préfixe/regex (`^OP\.GG`), jamais par égalité stricte.
⚠️ Le `QuietUninstallString` d'OP.GG contient un chemin non normalisé (`AppData\Roaming\..\Local\…`) — fonctionne tel quel, ne pas le « corriger ».

### Désinstallation NSIS : asynchrone

Le désinstalleur NSIS (`/S`) se copie dans `%TEMP%` et **rend la main avant d'avoir fini** (retour en 1-7 s, suppression effective en ~12 s). Le script doit **sonder** la disparition de la clé `Uninstall` et de l'exécutable, avec timeout (60 s suffisent), plutôt que se fier au code de sortie.

### Vérification avant exécution d'un installeur téléchargé

`Get-AuthenticodeSignature` : `Status -eq 'Valid'` **et** `SignerCertificate.Subject` contient l'organisation attendue. Ne jamais épingler un thumbprint (les certificats se renouvellent).

| Installeur | Subject attendu |
|---|---|
| Blitz | `O="Swift Media Entertainment, Inc."` (entité légale de Blitz) |
| OP.GG | `O=OP.GG` |
| Porofessor / Overwolf | `O=Overwolf Ltd` |

Complément d'intégrité quand disponible : hash SHA-256 du manifeste winget (Blitz), SHA-512 base64 du `latest.yml` electron-updater (OP.GG) — les deux ont été vérifiés conformes.

### Aucun auto-lancement après installation silencieuse

Blitz (winget) et OP.GG (`/S`) n'ouvrent pas l'application après installation. Le lanceur reste seul maître du démarrage de l'appli compagnon.

## Détail par application

### Blitz — `winget`

- winget : `Blitz.Blitz`, manifeste à jour (2.1.634 du 2026-09-11), installeur `nullsoft`, URL versionnée `https://blitz-main.blitz.gg/Blitz-<version>.exe` (pas d'URL « latest » connue → winget est la bonne source).
- Test : `winget install --id Blitz.Blitz --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity` → exit 0, 14 s. Clé HKCU créée, exe `%LOCALAPPDATA%\Programs\Blitz\Blitz.exe`, pas de process lancé.
- Test : `winget uninstall --id Blitz.Blitz --exact --silent` → exit 0 en 1 s, clé disparue à +5 s, dossier `Programs\Blitz` vide résiduel (4 Ko), rien dans `%APPDATA%`.
- Repli si winget absent : téléchargement de l'URL du manifeste (à lire via `winget show`) — ou `browser` vers `https://blitz.gg/download`.

### OP.GG — `download`

- URL stable : `https://op.gg/desktop/download/latest` → 302 vers `https://desktop-patch.op.gg/update/general/OP.GG Setup <version>.exe`.
- Manifeste officiel : `https://desktop-patch.op.gg/update/general/latest.yml` (version, nom de fichier, `sha512` base64, `size`). ⚠️ L'ancien bucket S3 `desktop-app-update.s3.ap-northeast-2` référencé par `app-update.yml` d'une vieille installation est **obsolète** (1.1.32 de 2023) — ne pas l'utiliser.
- Installeur NSIS electron-builder, per-user, signé `O=OP.GG`.
- Test mise à jour (1.4.30 → 2.5.5) : `/S /currentuser` → exit 0, 12 s, pas d'auto-lancement.
- Test désinstallation : `QuietUninstallString` → exit 0 en 7 s, effective à 12 s, 0 fichier résiduel.
- Test réinstallation : `/S /currentuser` → exit 0, 8 s.
- Lancement : `%LOCALAPPDATA%\Programs\OP.GG\OP.GG.exe`, sans argument.

### Porofessor — `download` silencieux, désinstallation interactive

- URL stable officielle : `https://download.overwolf.com/install/Download?Name=Porofessor.gg&ExtensionId=pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh&Channel=web_dl_btn` → 302 vers `Porofessor.gg - Installer.exe` (3,3 Mo). ⚠️ Servi avec `Content-Encoding: gzip` : `Invoke-WebRequest` décompresse nativement, `curl` non. Un second `ExtensionId` apparaît sur la page Overwolf (`blkfmdg…`) — ne pas l'utiliser.
- NSIS 3.08, manifeste `asInvoker`, signé `O=Overwolf Ltd` (cert valide jusqu'en 2029). Chaîne réelle : extracteur NSIS → `OWInstaller.exe` (+ `msedgewebview2`) → relance `Overwolf.exe`. Code de sortie **1223** dans tous les cas, même en succès → ne jamais juger sur le code de sortie, sonder la clé `Uninstall` + le dossier `%LOCALAPPDATA%\Overwolf\Extensions\<id>`.
- **Installation fraîche `/S`** (Overwolf présent, app absente) : ✅ totalement silencieuse, aucune fenêtre, clé + dossier présents à t+10 s, compte Porofessor toujours connecté après le cycle. Pas d'invite UAC.
- **App déjà installée `/S`** (2 exécutions) : l'installeur ouvre le client Overwolf sur Porofessor au lieu de réinstaller. → Ne lancer l'installeur que si l'app n'est pas détectée.
- **Overwolf absent** (testé le 2026-09-13, T10) : `/S` télécharge et installe Overwolf (0.310) **puis** Porofessor — clé Overwolf à t+62 s, Porofessor à t+72 s, exit 1223. Mais **la fenêtre du setup Overwolf s'affiche** (`OverwolfSetup.exe`, webview) : l'utilisateur suit ses étapes ; pas d'UAC observé (désactivé sur la machine de test — probable sur un poste standard). Le splash retire son TopMost pendant l'exécution des installeurs pour ne pas recouvrir cette fenêtre ; `install.notice` prévient dans la confirmation. `timeoutSeconds` 300 s suffisant.
- **Désinstallation complète d'Overwolf** (`OWUninstaller.exe /S`) : 34 s, mais affiche quand même `OWUninstallMenu` et ouvre une page de feedback Chrome — comme toute désinstallation d'app Overwolf (non bloquant).
- **Désinstallation** `OWUninstaller.exe --uninstall-app=<id>` : ouvre **`OWUninstallMenu`** avec **Overwolf ET Porofessor cochés par défaut** — c'est l'explication du témoignage « tout Overwolf retiré ». Overwolf décoché + Uninstall → Porofessor seul retiré en 16 s, Overwolf et les autres extensions intacts. Aucun flag silencieux ; retour du process à 60 s avec exit 0 quel que soit le choix. Une page Chrome de feedback Overwolf s'ouvre en fin de désinstallation.
- Aucune doc officielle Overwolf sur les arguments ; le paquet Chocolatey `overwolf` (`-silent`, exit 1223 toléré) repose sur un binaire de 2021 — non représentatif, mais cohérent sur le 1223.

**Décision :** installation `download` + signature `O=Overwolf Ltd` + `/S`, succès jugé par sonde. Désinstallation **interactive par conception** : l'outil lance le menu Overwolf et informe l'utilisateur (« décochez Overwolf si vous le gardez pour d'autres apps ») — certains utilisateurs voudront légitimement retirer Overwolf aussi, c'est leur choix, jamais celui du script. L'outil vérifie ensuite l'état (clé Porofessor, clé Overwolf) et l'affiche.

### Mobalytics et U.GG — hors périmètre initial

- Mobalytics (testé le 2026-09-13, ajouté au catalogue) : canal standalone `https://desktop-app.mobalytics.gg/production/Mobalytics-Setup-latest.exe` (158 Mo), NSIS, signé `O="GAMERS NET, INC."`, per-user. Install `/S` : exit 0, 11 s, clé HKCU `Mobalytics <version>` (version dans le nom → motif `^Mobalytics`), exe `%LOCALAPPDATA%\Programs\mobalytics-desktop\Mobalytics.exe` (pas « Mobalytics Desktop.exe » comme le disaient les sources tierces), **l'installeur lance l'appli** → le script la referme. Désinstall `QuietUninstallString` (`/currentuser /S`) : effective en 9 s, 0 résidu. Page navigateur : `https://mobalytics.gg/lol/glp/app-download/`.
- U.GG : app Overwolf uniquement (`edoaelkdajnifpnkdfillhjpaimimibflhkhjngh`), page de téléchargement en 403 pour les clients non-navigateur → `browser`.

## Conséquences pour le plan

1. Le catalogue porte, par appli, une stratégie d'installation (`winget` / `download` / `browser`) et un mode de désinstallation (`silent` / `interactive`) avec message d'information optionnel.
2. Le module partagé implémente une **attente par sonde** (clé `Uninstall` + exécutable/dossier) après installation **et** désinstallation, avec timeout — les codes de sortie ne sont pas fiables (NSIS asynchrone, Overwolf 1223).
3. La vérification Authenticode par `Subject` est obligatoire avant toute exécution d'un binaire téléchargé.
4. Le registre n'est **jamais** écrit par nos scripts (règle projet) ; chaque exécution d'installeur/désinstalleur passe par une confirmation utilisateur dans le dialogue.
5. BUSINESS_RULE Porofessor : la désinstallation passe par le menu Overwolf interactif ; le script n'impose ni ne contourne le choix de garder/retirer Overwolf. Ne lancer l'installeur Porofessor que si l'app n'est pas détectée (sinon il ouvre Overwolf).
6. Prérequis à documenter dans le README (pas à appliquer par script) : winget (App Installer) présent pour Blitz ; sinon repli `browser`.

## Sources

- Overwolf, lien de téléchargement d'app : https://dev.overwolf.com/ow-native/guides/growth/creating-an-app-download-link-with-referral-id/
- Page store Porofessor : https://www.overwolf.com/app/trebonius-porofessor.gg
- winget-pkgs `Blitz.Blitz` (via `winget show`), `Overwolf.CurseForge` : https://github.com/microsoft/winget-pkgs
- OP.GG desktop : https://op.gg/desktop/en/downloads · `latest.yml` : https://desktop-patch.op.gg/update/general/latest.yml
- Mobalytics standalone : https://mobalytics.gg/lol/glp/download-welcome?isElectron=true
- Chocolatey `overwolf` (obsolète) : https://community.chocolatey.org/packages/overwolf
- Reverse engineering installeur Overwolf (tiers) : https://gist.github.com/0xdevalias/c5bd55b50f0e2da9d0c685163535d4c6
