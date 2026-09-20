# Lancement de League of Legends — arbre de décision

Comportement de `app/launch-lol.ps1` à partir de la version 0.1.7. Relevé d'API et mesures qui justifient chaque
branche : `20260920-riot-client-local-api.md`.

## Pourquoi deux chemins

Le chemin historique — fermer tout Riot, écrire `settings.locale` dans le yaml, relancer avec `--launch-product` —
laisse le Riot Client sur sa page produit, bouton **Play** en attente : il annule l'auto-lancement parce qu'il
arbitre la permission `game:play` avant l'authentification RSO. Il reste néanmoins en place comme repli, parce
qu'il ne dépend d'aucune API non documentée.

Le chemin rapide passe par l'API locale du Riot Client : la langue est **posée** (`PUT`) au lieu d'être écrite dans
son dos, et le jeu est lancé comme le ferait le bouton Play. Le Riot Client n'est jamais fermé — il est démarré
s'il ne tourne pas.

| | Chemin rapide | Chemin historique |
|---|---|---|
| Processus fermés | client de jeu seul (`LeagueClient*`) | tous les process Riot |
| Riot Client éteint | démarré, puis on attend son API | démarré avec `--launch-product` |
| Langue appliquée par | `PUT` à l'API, le Riot Client écrit le yaml | écriture directe du yaml |
| Lancement | `POST` à l'API locale | `--launch-product` en ligne de commande |
| Jeu effectivement lancé | oui (vérifié par la présence du process) | souvent non → bouton Play |
| Dépend d'une API non documentée | oui | non |

## L'arbre complet

```
╔═ ENTRÉE ══════════════════════════════════════════════════════════════════════════╗

Raccourci .lnk → powershell -WindowStyle Hidden -File launch-lol.ps1
                 -Locale xx_XX [-Companion id] [-ConfigPath p] [-YamlPath p]
                 [-NoLocalApi] [-DryRun]

① -Locale présent et au format xx_XX ?
   ├── absent ──────► throw "-Locale est requis (ex. ja_JP)"   ⛔ FIN, rien touché
   ├── mal formé ───► erreur de validation du paramètre        ⛔ FIN, rien touché
   └── valide

② Read-LaunchConfig (config.json, ou -ConfigPath)
   ├── fichier absent / illisible ──► throw                    ⛔ FIN, rien touché
   └── lu : riotClientPath · productSettingsPath · companionApps[] · iconSet
            -YamlPath fourni ? il prime sur productSettingsPath

③ New-SplashWindow — sous-titre = libellé de la langue (Get-LocaleLabel)
   ├── locales.json absent, ou langue hors catalogue → le code xx_XX sert de libellé
   └── le splash reste affiché jusqu'au bout (fermé dans un finally, même sur erreur)

④ -DryRun ?
   ├── oui ──► aucun process fermé, aucun lancement
   │           settings.locale écrit dans le yaml · compagnon seulement vérifié (Test-Path)
   │           ──────────────────────────────────────────────►  ⑩ puis FIN (mode test)
   └── non

⑤ -NoLocalApi demandé, OU case « Mode de secours » cochée dans setup.bat (useLocalApi = false) ?
   ├── oui ─────────────────────────────────────────────────────────────────────┐
   └── non                                                                       │
                                                                                 │
╔═ ⑥ CHEMIN RAPIDE — API locale du Riot Client ═════════════════════════╗        │
                                                                                 │
6.1 Stop-GameClientProcesses                                                     │
    ferme LeagueClient · LeagueClientUx · LeagueClientUxRender  (puis 2 s)       │
    RiotClientServices · RiotClientUx · RiotClientUxRender : JAMAIS touchés      │
    └── aucun de ces process ne tournait → rien à faire, on continue             │
                                                                                 │
6.2 Test-RiotClientRunning ?                                                     │
    ├── non ──► Start-RiotClient : RiotClientServices.exe, sans argument         │
    │           de produit (son API suffira)                                     │
    └── oui ──► session en cours réutilisée, rien n'est redémarré                │
                                                                                 │
    ⏱ Passé 2 min depuis le clic sur le raccourci, le splash montre le bouton    │
    « Forcer le démarrage » : un clic lève un drapeau que chaque boucle ci-dessous │
    lit en tête de tour (ShouldStop) → abandon immédiat, cause 'cancelled' ──────► │
    Rien n'est mémorisé : le lancement suivant retente le chemin rapide.           │
                                                                                 │
6.3 Wait-RiotProductLocale — boucle, 1 tentative/s, échéance 30 s                │
    à chaque tour : Read-RiotClientLockfile (Config\lockfile, lu en partage)     │
    ├── absent / illisible / 5 champs manquants / port non numérique             │
    │   └── on attend sans rien dire (le Riot Client démarre encore)             │
    └── lu → PUT /riotclient/product-locales/products/…/patchlines/live          │
             corps = "xx_XX"                                                     │
        ├── 2xx ──► langue posée ; le Riot Client écrit le yaml lui-même → 6.4   │
        ├── 0 · 424 · 464 ──► réessai au tour suivant                            │
        └── 401 · 403 · 404 · 5xx ──► refus définitif, avertissement ──────────► │
    échéance atteinte sans succès ──► avertissement ─────────────────────────────┤
                                                                                 │
6.4 Wait-RiotProductLaunch — même boucle, mêmes règles                           │
    POST /product-launcher/v1/products/league_of_legends/patchlines/live         │
    ├── 2xx (200 + identifiant de session) ──► 6.5                               │
    ├── 0 · 424 · 464 ──► réessai                                                │
    └── refus définitif ──► avertissement ─────────────────────────────────────► │
    échéance atteinte sans succès ──► avertissement ─────────────────────────────┤
                                                                                 │
6.5 Wait-GameClientStart — 3 min : un LeagueClient* apparaît-il ?                │
    ├── oui ──► ✅ SUCCÈS PAR L'API                                    ──► ⑩    │
    ├── « Forcer le démarrage » cliqué ──► cause 'cancelled' ─────────────────►  │
    └── non ──► l'API a dit oui sans rien faire (cas de l'endpoint                │
                déprécié) ────────────────────────────────────────────────────►  │
                                                                                 ▼
╔═ ⑨ CHEMIN HISTORIQUE — ligne de commande (repli 1) ═══════════════════════════════╗

9.1 Stop-RiotProcesses
    ferme les six : client de jeu ET Riot Client  (puis 2 s)
    nécessaire, car la langue va repasser par le yaml et un Riot Client vivant
    le réécrirait depuis sa mémoire

9.2 Set-LeagueLocale
    settings.locale ← "xx_XX"      default_locale : jamais touché (géré par Riot)

9.3 Start-Process RiotClientServices.exe
    --launch-product=league_of_legends --launch-patchline=live --locale=xx_XX
    ├── Riot honore l'intention ──────────► ✅ SUCCÈS EN SECOURS           ──► ⑩
    └── Riot l'annule tout seul :
        willAutoLaunch=true → game:play isGranted=0 'UNAUTHORIZED' → willAutoLaunch=false
        (la permission arrive 400 ms trop tard, l'intention n'est jamais rejouée)
        └──► ⚠️ REPLI 2 : page produit ouverte, bouton Play actif       ──► ⑩
             aucun échec dur, aucune exception

╔═ ⑩ APPLIS COMPAGNON — identique après les deux chemins ═══════════════════════════╗

10.1 Find-LaunchCompanion (config.json, -Companion)

10.2 Stop-OtherCompanionApps
     ferme les compagnons déclarés dans config.json autres que celui demandé
     (un seul overlay actif en partie ; celui demandé est laissé s'il tourne déjà)

10.3 Quel compagnon ?
     ├── trouvé ──► Start-CompanionApp
     │              ├── binaire présent ──► lancé (avec ses arguments s'il en a)
     │              └── binaire absent ───► "introuvable — ignoré (vérifier config.json)"
     │                                      le jeu reste lancé
     ├── -Companion donné mais inconnu de config.json
     │              ──► "absente de config.json — ignorée (relancer setup.bat)"
     └── aucun -Companion ──► rien à lancer

⑫ finally → Close-SplashWindow        toujours exécuté, y compris sur throw
```

## Pas de mémoire de lancement

Le lanceur est sans état : chaque lancement tente le chemin rapide, sauf `-NoLocalApi` ou la case « Mode de
secours » de l'assistant. Une mémoire des échecs (`launch-state.json`) a existé en 0.2.0 et a été retirée le
2026-09-20 : un `404` ponctuel — Riot resté sans interface après une partie — la faisait basculer en mode de
secours pour tous les lancements suivants, sans rien montrer. Une panne visible (attente longue, puis la case)
vaut mieux qu'une décision cachée. La cause de l'échec (`route` / `silent` / `timeout`, code, étape) reste
journalisée pour le support, sans effet sur les lancements suivants.

## Issues possibles, et ce que voit l'utilisateur

| Issue | Jeu lancé | Langue appliquée | Ce qui s'affiche |
|---|---|---|---|
| Succès par l'API (6.5) | oui | oui, posée par l'API | splash, puis le client de jeu |
| Succès en mode de secours (9.3) | oui | oui, via le yaml | splash, fenêtre Riot, puis le client de jeu |
| Démarrage forcé (bouton du splash, puis 9.3) | oui | oui, via le yaml | « Démarrage forcé : fermeture de Riot puis redémarrage… », fenêtre Riot, puis le client de jeu |
| Repli 2 (9.3 annulé) | non | oui, via le yaml | fenêtre Riot, bouton **Play** à cliquer |
| `-Locale` absent ou invalide | non | non | erreur, aucun process touché |
| `config.json` absent | non | non | erreur, aucun process touché |
| Compagnon introuvable | oui | oui | message dans le splash, le jeu part quand même |

## Ne pas confondre 6.4 et « auto-lancement annulé »

Ce sont deux mécanismes distincts, et leur différence est la raison d'être du chemin rapide.

| | 6.4 `POST` de lancement (chemin rapide) | 9.3 auto-lancement annulé (chemin historique) |
|---|---|---|
| Nature | requête HTTP à l'API locale | argument `--launch-product` au démarrage du client |
| Ce qu'on observe | un code de réponse : `464`, `200`… | rien — seuls les journaux du Riot Client en parlent |
| Nombre de tentatives | autant que l'échéance le permet | une seule, jamais rejouée par Riot |
| Issue d'un refus | on réessaie, puis on replie | la page produit reste ouverte sur **Play** |

Dans les deux cas, c'est le même arbitrage de permission côté Riot :

```
willAutoLaunch=true                              ← intention acceptée
game:play isGranted=0 reason='UNAUTHORIZED'      ← 7 ms plus tard
willAutoLaunch=false                             ← intention abandonnée
game:play isGranted=1                            ← 400 ms trop tard, jamais rejouée
```

En ligne de commande, cette intention est évaluée une seule fois, trop tôt, et Riot ne la rejoue pas. Par l'API,
chaque `POST` est une demande neuve : le code `464` est la version visible et réessayable de ce que le chemin
historique subit en silence. La boucle rejoue donc l'intention que le Riot Client, lui, ne rejoue jamais.

## La boucle commune

Les étapes 6.3 et 6.4 partagent `Wait-RiotClientOperation` : elle relit le lockfile à chaque tour — il n'existe pas
encore quand le Riot Client démarre — rejoue l'opération sur un code d'attente, et rend la main immédiatement sur
un refus définitif. Un seul endroit décide donc de ce qui se réessaie.

| Code | Sens observé | Réaction |
|---|---|---|
| `200` / `201` / `204` | accepté | on poursuit |
| `0` | connexion pas établie — le serveur local démarre encore | réessai |
| `423` | session verrouillée : un client de jeu tourne toujours | réessai |
| `424` | session en cours de libération après la fermeture du jeu | réessai |
| `464` | session pas prête — authentification RSO en cours | réessai |
| `401` / `403` | autorisation refusée | chemin historique, sans attendre |
| `404` | route disparue d'une version à l'autre | chemin historique, sans attendre |

### Le coût de la libération de session

Mesuré le 2026-09-20, après avoir fermé le client de jeu, le Riot Client refuse tout nouveau lancement pendant un
délai très variable :

| Situation | Délai avant `200` |
|---|---|
| jeu établi depuis plusieurs minutes | **3,5 s** |
| jeu lancé quelques secondes plus tôt | **57 s** — le heartbeat de sa session doit expirer |
| jeu encore en cours d'exécution | jamais : `423` tant qu'il tourne |

C'est ce qui explique qu'un même lancement prenne 4 s ou une minute selon le moment. La boucle réessaie, donc le
résultat est le même — seule l'attente change. Et comme ces refus sont classés `timeout` (cinq échecs avant
renoncement), une machine lente ou un enchaînement malheureux ne prive jamais le poste du chemin rapide.

Une fermeture propre du client de jeu (`CloseMainWindow`, l'équivalent d'un clic sur la croix) a été essayée pour
raccourcir ce délai : le client LoL l'ignore purement et simplement — huit process toujours là après quinze
secondes. Le `Stop-Process` reste donc le seul moyen de le fermer.

## Mesures de bout en bout (2026-09-20)

Trois essais réels, depuis le lanceur complet, splash compris.

| Scénario | Chemin emprunté | Lanceur rendu | Jeu lancé | Langue prise |
|---|---|---|---|---|
| Riot Client et jeu déjà ouverts | rapide, session réutilisée (pid inchangé) | 11,3 s | oui, 11,4 s | `ja_JP` |
| Tout Riot fermé (démarrage à froid) | rapide, Riot Client démarré par le lanceur | 12,7 s | oui, 12,7 s | `fr_FR` |
| `-NoLocalApi` | historique (`--launch-product`, nouveau pid) | 5,3 s | non → bouton Play | `fr_FR` (yaml) |

L'API elle-même répond bien plus vite que ces chiffres — 3,4 s sur une session ouverte, 8,2 s à froid. L'écart
tient aux temporisations du splash (2 s après la fermeture du client de jeu, 1 s par tour de boucle, puis les
étapes des applis compagnon), pas à l'API.

Ces durées viennent d'un poste rapide : elles décrivent ce qui a été mesuré, elles ne servent pas de seuil. Les
échéances sont volontairement larges pour une machine lente — un budget unique de 6 min couvre la pose de la langue
et l'acceptation du lancement (plutôt que deux compteurs qui se cumuleraient), et 3 min sont laissées au client de
jeu pour apparaître, l'étape la plus sensible à un disque lent ou à Vanguard.

Si ce pire cas se répète, la case « Mode de secours » de l'assistant écarte le chemin rapide.

## Ce qui ne peut pas faire échouer un lancement

Audit du 2026-09-20, chaque point vérifié par un test :

| Situation | Comportement |
|---|---|
| Fichier de langue introuvable au moment du repli | avertissement, le jeu est lancé quand même — abandonner laisserait l'utilisateur sans jeu, Riot venant d'être fermé |
| `riotClientPath` périmé dans `config.json` | message clair dans le splash, aucune exception |
| Client de jeu apparu juste après l'échéance | reconnu comme un succès — le repli ne le tue plus pour le relancer |
| `%LOCALAPPDATA%` non défini | lockfile considéré absent, pas d'exception |
| Horloge système qui recule pendant l'attente | sans effet : les boucles mesurent un écoulement (`Stopwatch`), pas une heure |

## Pourquoi l'étape 6.5 existe

Une route de Riot ne meurt pas franchement : elle continue de répondre en ayant perdu son effet.
`POST /riotclient/new-args` porte la mention « deprecated, will be removed June 2022 » ; en 2026 il répond
toujours `204` et ne lance plus rien. Conclure au succès sur le seul code HTTP exposerait donc le lanceur à croire
qu'il a démarré le jeu alors que rien ne se passe, sans jamais déclencher le repli. La présence effective du
client de jeu est la seule preuve qui ne mente pas.

## Pourquoi la langue passe par l'API

Avec le Riot Client allumé, écrire `settings.locale` à la main ne tient pas : mesuré le 2026-09-20, `fr_FR` écrit
dans le yaml est revenu à `ja_JP` en quelques secondes, le Riot Client ayant réécrit le fichier depuis son état en
mémoire. Posée par `PUT`, la langue est en revanche conservée, écrite par le Riot Client lui-même, et le client de
jeu démarre bien avec `--locale=fr_FR`. C'est ce qui rend la session chaude possible — et donc le gain de vitesse.

## Forcer le chemin historique

```
powershell -NoProfile -ExecutionPolicy Bypass -File launch-lol.ps1 -Locale ja_JP -NoLocalApi
```

Réservé au dépannage : les raccourcis du Bureau ne passent pas ce paramètre — `Get-LauncherArguments` ne produit
que `-Locale` et `-Companion`. Pour l'utiliser en permanence, cocher « Mode de secours » dans setup.bat
(`useLocalApi = false` dans `config.json`), que le lanceur lit à chaque démarrage.

Vérifié le 2026-09-20 : tous les process Riot fermés, yaml réécrit, `RiotClientServices` relancé avec
`--launch-product`, bouton Play en attente.
