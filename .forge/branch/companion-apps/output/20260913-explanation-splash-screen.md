# Splash screen

## 1. Définition

Fenêtre affichée pendant le démarrage d'un programme pour montrer que quelque chose se passe (logo, barre de progression, étape en cours). Exemples : Photoshop, IntelliJ IDEA, client Riot officiel. Améliore l'UX en évitant que l'utilisateur croie que le programme a gelé.

## 2. Dans ce projet

La fonction `New-SplashWindow` du fichier `launch-lol.ps1` (lignes 59–108) crée un splash screen en `System.Windows.Forms.Form` sans bordure (`FormBorderStyle = 'None'`), centrée à l'écran (`StartPosition = 'CenterScreen'`), toujours au premier plan (`TopMost = $true`), et absent de la barre des tâches (`ShowInTaskbar = $false`).

**Palette visuelle :**
- Fond : `#0A0E14` (noir Riot)
- Titre : « LEAGUE OF LEGENDS » en or (`#C8AA6E`), Segoe UI 16 Bold, centré, hauteur 60 px
- Sous-titre : code locale (ex. `日本語`) en blanc, Segoe UI 12, hauteur 30 px
- ProgressBar : style `Marquee` (barre infinie animée), hauteur 6 px
- Label de statut : texte gris (`#A09B8C`), Segoe UI 9, remplit l'espace restant

**Contrôle du statut :**
- `Update-SplashStatus` (lignes 110–113) met à jour le texte du label et pompe les messages Windows avec `[System.Windows.Forms.Application]::DoEvents()` pour redessiner la fenêtre en temps réel.
- Les étapes affichées : « Fermeture du client Riot… », « Application de la langue… », « Lancement de League of Legends… », « Lancement de [application compagnon]… ».

**Raison du `Wait-WithAnimation` (lignes 116–122) :**
- `[System.Windows.Forms.Application]::DoEvents()` pompe la file des messages Windows par petits pas de 50 ms, permettant à la barre Marquee de s'animer et à la fenêtre de rester réactive.
- Un simple `Start-Sleep -Seconds N` bloquerait le thread UI — la barre se figerait, la fenêtre paraîtrait morte, et les événements accumulerait en arrière-plan.
- L'approche `Wait-WithAnimation` alternates : tirer les messages, attendre 50 ms, recommencer jusqu'au deadline.

**Piège d'encodage :**
- Le fichier `launch-lol.ps1` **doit être en UTF-8 avec BOM**, sinon les caractères accentués et non-latin du splash (ex. « `français` », « `日本語` ») s'affichent corrompus.
- PowerShell 5.1 sur Windows utilise par défaut UTF-16LE ; le BOM est nécessaire pour forcer la lecture UTF-8 lors du dot-sourcing ou du lancement du script.

## 3. Schéma ASCII de la fenêtre

```
┌─────────────────────────────────────────────┐
│                                             │  42 px (TopMargin du titre)
│          LEAGUE OF LEGENDS                  │  60 px (titre)
│                                             │
│              日本語                          │  30 px (langue)
│                                             │
│ ▓▓▓▒▒▒▓▓▓▒▒▒▓▓▓▒▒▒▓▓▓ ← barre Marquee      │  6 px
│                                             │
│ Lancement de Porofessor…                   │  ← remplissage restant
│                                             │
└─────────────────────────────────────────────┘

Dimens. : 420 × 170 px
CenterScreen ; TopMost ; No TaskBar
Fond : #0A0E14 ; Titre or (#C8AA6E) ; Texte blanc/gris (#A09B8C)
```

## 4. Justification de sa présence

Le raccourci Windows lance `powershell -WindowStyle Hidden`, ce qui masque la console PowerShell. Sans splash screen, l'utilisateur attend 2–3 secondes sans aucun feedback visuel, ce qui le pousse à croire que :
- Rien ne s'est lancé
- Le PC est gelé
- Il faut re-cliquer ou forcer l'arrêt

Le splash apaise cette incertitude en montrant chaque étape (fermeture des anciens process, application de la langue, lancement, etc.) et en animant une barre infinie, signalant un travail en cours.

## 5. Piste d'évolution

La fonction `Wait-CompanionState` dans `lib/companion-app.lib.ps1` (lignes 128–136) accepte un paramètre `-OnTick` (scriptblock) appelé à chaque seconde d'attente. Cela permet de réutiliser le même style de splash animé durant l'installation de l'application compagnon (`manage-companion-app.ps1`) :

```powershell
# Sketch d'intégration
$splash = New-SplashWindow $appName
$result = Wait-CompanionState -App $app -Installed $true -TimeoutSeconds 30 -OnTick {
    Update-SplashStatus $splash "Installation en cours…"
}
$splash.Close()
```

Au lieu de bloquer sans feedback, l'utilisateur verrait l'avancement en temps réel et la fenêtre resterait réactive, cohérente avec l'UX du lancement de LoL.

---

**Termes clés :** `System.Windows.Forms.Form` · `FormBorderStyle` · `TopMost` · `ProgressBar.Style = 'Marquee'` · `DoEvents()` · UTF-8 BOM · `Wait-CompanionState -OnTick`
