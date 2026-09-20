# Plan — launcher
**Objective:** Lancer League of Legends sans clic sur Play, en pilotant le Riot Client par son API locale, repli sur le rejeu de `--launch-product`.
**Date:** 2026-09-19

## Tasks

### T1 — Lanceur testable (Main gardé)
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1` (nouveau)
**Description:** `launch-lol.ps1` est le seul script moteur sans garde de Main : envelopper le Main dans
`if ($MyInvocation.InvocationName -ne '.')` et rendre `-Locale` non obligatoire (le dot-sourcing d'un paramètre
`Mandatory` ouvre une invite interactive), la garde validant sa présence et son format. Tests : `Get-LocaleLabel`
(libellé du catalogue, repli sur le code, catalogue absent), `Set-LeagueLocale` (`settings.locale` seul réécrit,
`default_locale` intact), listes de process ciblées, `Start-CompanionApp` (chemin absent → `$false`).
[x] 2026-09-19 — Main gardé, `-Locale` validé dans la garde, 14 tests ; deux tests du voile nuit réalignés sur le comportement livré en 0.1.6

### T2 — Adapter de l'API locale du Riot Client
**Effort:** M
**Files:** `app/lib/riot-client-api.lib.ps1` (nouveau), `tests/riot-client-api.lib.tests.ps1` (nouveau)
**Description:** Port sortant vers le Riot Client, seule porte d'entrée de son API locale.
`Read-RiotClientLockfile` : `%LOCALAPPDATA%\Riot Games\Riot Client\Config\lockfile` → objet
`{ name, processId, port, password, protocol }` ; fichier absent ou malformé → `$null` avec warning, jamais de throw.
`Invoke-RiotClientRequest -Method -Path` : HTTPS sur `127.0.0.1:<port>`, en-tête Basic `riot:<mot de passe>`,
certificat auto-signé accepté par un rappel de validation posé puis restauré dans un `finally`, TLS 1.2, échéance courte.
`Wait-RiotClientReady` : sonde l'API jusqu'à échéance (pattern `Wait-CompanionState` de `companion-app.lib.ps1`).
`Start-RiotProduct -ProductId -PatchlineId` → `$true` / `$false`. L'endpoint de lancement est relevé sur
`swagger/v3/openapi.json` du Riot Client et consigné dans OUTPUT — jamais supposé.
Aucun mot de passe de lockfile dans un log, un message ou une exception.
[x] 2026-09-20 — lib écrite, transport basculé sur WinHTTP (renégociation TLS refusée par `Invoke-WebRequest`), endpoint confirmé sur la machine ; 20 tests

### T3 — Lancement par l'API, repli sur le rejeu
**Effort:** M
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** `Start-LeagueClient` en trois temps : démarrer `RiotClientServices` comme aujourd'hui (le yaml est
déjà réécrit à ce moment) ; attendre le lockfile puis la session prête ; lancer le produit par l'API.
Échec (lockfile absent, HTTP en erreur, échéance dépassée) → repli : rejouer `--launch-product=league_of_legends
--launch-patchline=live`, puis laisser le bouton Play. Statut du splash à chaque étape.
Tests : succès API sans rejeu, lockfile absent → rejeu, API en erreur → rejeu, échec total → aucun throw.
[x] 2026-09-20 — `Wait-RiotProductLaunch` rejoue le lancement (aucune sonde ne prédit l'instant utile), repli et splash en place ; 19 tests

### T4 — Essai réel, version, documentation
**Effort:** S
**Files:** `app/version.txt`, `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`, `.forge/project.md`
**Description:** Essai sur le Bureau depuis un raccourci langue × compagnon : jeu lancé sans clic, `settings.locale`
conservé après coup (journaux du Riot Client relus). Version 0.2.0, README ×3 et `project.md` : nouvelle lib et
lancement par l'API locale.
[x] 2026-09-20 — essai réel : jeu lancé sans clic en 17 s, `settings.locale` appliqué et `default_locale` intact ; version 0.2.0, README ×3, project.md, relevé d'API dans OUTPUT ; suite à 421 verts

### T5 — Distinguer l'attente du refus définitif
**Effort:** S
**Files:** `app/lib/riot-client-api.lib.ps1`, `tests/riot-client-api.lib.tests.ps1`
**Description:** `Start-RiotProduct` rend le résultat de l'appel plutôt qu'un booléen ; la boucle ne réessaie que
sur les codes d'attente et rend la main immédiatement sur un refus définitif (404, 401, 403), pour ne pas faire
patienter 30 s avant le repli.
[x] 2026-09-20 — `Test-RiotClientRetryableStatus`, pire cas ramené de 30 s à une tentative ; 45 tests

### T6 — Session chaude : langue par l'API, chemin historique conservé en repli
**Effort:** M
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/riot-client-api.lib.tests.ps1`, `tests/launch-lol.tests.ps1`, README ×3, `.forge/project.md`, `output/`
**Description:** Chemin rapide : fermer le seul client de jeu, démarrer le Riot Client s'il est éteint, poser la
langue par `PUT /riotclient/product-locales/...` (le Riot Client écrit alors le yaml lui-même), lancer par l'API,
puis vérifier que le client de jeu apparaît vraiment — un endpoint déprécié chez Riot continue de répondre sans
agir. `Wait-RiotClientOperation` factorise la boucle d'attente des deux opérations. Chemin historique conservé
intact (`Start-LeagueClientByCommandLine`), déclenché sur tout échec et forçable par `-NoLocalApi`. `424` rejoint
les codes d'attente.
[x] 2026-09-20 — trois essais réels : session chaude 11,3 s, démarrage à froid 12,7 s (jeu lancé et langue prise
dans les deux cas), `-NoLocalApi` bascule bien sur le chemin historique (Riot fermé, relancé avec
`--launch-product`, bouton Play) ; suite à 442 verts

### T7 — Robustesse : aucune faille ne doit casser un lancement
**Effort:** M
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/riot-client-api.lib.tests.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Audit du chemin rapide et de son repli, six correctifs : le chemin historique lance le jeu même
si le fichier de langue est inaccessible (il vient de fermer Riot, abandonner laisserait l'utilisateur sans rien) ;
un client de jeu apparu juste après l'échéance n'est plus tué pour être relancé ; `Start-Process` et la résolution
du lockfile ne lèvent plus d'exception sur un chemin périmé ; les boucles mesurent un écoulement (`Stopwatch`) et
non l'heure système, qu'un recul d'horloge rendrait inatteignable ; budget unique de 60 s pour le chemin rapide et
30 s laissées au client de jeu pour apparaître ; objets COM libérés à chaque requête.
[x] 2026-09-20 — six failles corrigées, chacune couverte par un test ; issue du lancement rendue lisible
(`api` / `legacy` / `failed`) et affichée dans le splash ; 452 verts

### T8 — Mémoire de lancement
**Effort:** M
**Files:** `app/lib/launch-state.lib.ps1` (nouveau), `app/launch-lol.ps1`, `tests/launch-state.lib.tests.ps1` (nouveau), `.gitignore`, `tools/make-release.ps1`, README ×3, `.forge/project.md`
**Description:** `launch-state.json` retient ce que le poste a appris de l'API locale : deux échecs consécutifs
l'écartent des lancements suivants — l'attente n'est plus payée à chaque partie — et un changement de version du
Riot Client la fait retenter, une mise à jour pouvant aussi bien réparer son API que la casser. Fichier séparé de
`config.json` (intentions de l'utilisateur d'un côté, observations de la machine de l'autre), gitignoré et hors
release. Aucune case à cocher : l'utilisateur n'a rien à diagnostiquer.
[x] 2026-09-20 — trois essais réels : mémoire créée au premier lancement, chemin rapide écarté après deux échecs
(5,2 s, mémoire inchangée car rien n'est tenté), retenté et réussi après changement de version ; 469 verts

### T9 — La mémoire distingue la cause de l'échec
**Effort:** S
**Files:** `app/lib/launch-state.lib.ps1`, `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, tests
**Description:** Le chemin rapide rend *pourquoi* il a échoué, et le seuil de renoncement suit la cause : `route`
(404, 401, 403) une fois suffit, `silent` (lancement accepté sans effet) deux, `timeout` cinq — deux mauvais jours
sur une machine lente ne doivent pas priver le poste du lancement direct. Code et étape conservés pour le support.
[x] 2026-09-20 — seuils par cause, compteur remis à zéro quand la cause ou la version change ; `423` ajouté aux
codes d'attente après mesure (session verrouillée tant que le jeu tourne)

### T10 — Journal de lancement horodaté
**Effort:** M
**Files:** `app/lib/launch-log.lib.ps1` (nouveau), `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/launch-log.lib.tests.ps1` (nouveau), `.gitignore`, `tools/make-release.ps1`
**Description:** `launch.log`, une ligne horodatée par étape : démarrage et décision de la mémoire, fermetures de
process, chaque appel d'API avec code et durée, tours de boucle sans tentative, apparition du client de jeu,
bascule sur le chemin classique et sa cause, appli compagnon, issue finale. Jamais le mot de passe du lockfile.
Borné à 200 Ko, écriture impossible sans conséquence sur le lancement.
[x] 2026-09-20 — utilité immédiate : il a révélé 57 s de refus `424` qu'aucun essai n'avait montrées, et la
disparition du Riot Client rattrapée par la garde. UTF-8 avec BOM pour être lisible sans précaution.

### T11 — Le splash raconte toute la séquence
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Un scriptblock `OnStatus` (même principe qu'`OnTick`, sans coupler la logique à l'interface)
annonce chaque étape — démarrage du Riot Client, application de la langue, demande de lancement, préparation du
jeu, reprise classique — et le tick accole les secondes écoulées sur les attentes longues.
[x] 2026-09-20 — plus de splash figé pendant la phase API, qui peut durer d'une seconde à une minute

### T12 — Riot rangé dans la zone de notification
**Effort:** M
**Files:** `app/lib/riot-window.lib.ps1` (nouveau), `app/launch-lol.ps1`, `tests/riot-window.lib.tests.ps1` (nouveau)
**Description:** Une fois le client de jeu détecté, demander la fermeture de la fenêtre du Riot Client : une partie
en cours, il se replie sur son icône près de l'horloge au lieu de quitter. Fenêtre trouvée par `EnumWindows` sur le
process `Riot Client` et la classe `Chrome_WidgetWin_1`. Jamais sur le chemin classique, où elle sert à cliquer Play.
[x] 2026-09-20 — mesuré : 7 process → 1, 1 107 Mo → 475 Mo, icône conservée, API toujours répondante. Le masquage
(`SW_HIDE`) avait été essayé d'abord et écarté : rien de rendu, 0,4 % d'un cœur économisé.

### T13 — Case « lancement classique » dans l'assistant
**Effort:** M
**Files:** `app/setup.ps1`, `app/lib/launch-config.lib.ps1`, `app/launch-lol.ps1`, `app/i18n/{fr,en,ja}.json`, tests
**Description:** Champ `useLocalApi` dans `config.json` et case sur la page Raccourcis, décochée par défaut :
« Lancement classique — à cocher si le jeu ne démarre pas ». Trois voix peuvent écarter l'API — le raccourci
(`-NoLocalApi`), ce choix, la mémoire des échecs — il suffit d'une. Filet pour les utilisateurs quand personne
n'est disponible pour déboguer.
[x] 2026-09-20 — réglage lu par le lanceur, case mémorisée comme le jeu d'icônes, i18n ×3, 518 verts

### T14 — Bug : Riot déjà lancé, pourtant fermé et redémarré en mode classique
**Effort:** M
**Files:** `app/lib/riot-window.lib.ps1`, `app/lib/riot-client-api.lib.ps1`, `app/lib/launch-state.lib.ps1`, `app/launch-lol.ps1`, tests
**Description:** Constaté par l'utilisateur sur la 0.2.0, release retirée le 2026-09-20. Le journal montre la
séquence exacte : un premier lancement réussit par l'API et **ferme la fenêtre du Riot Client** (T12) ; au
lancement suivant, Riot tourne encore mais **sans interface**, et dans cet état `PUT /riotclient/product-locales/…`
répond **404 en 0,0 s**. Le lanceur y voit une route disparue → bascule classique → tout Riot fermé. Puis la
mémoire, avec son seuil `route = 1` (T9), écarte l'API d'office pour tous les lancements suivants.

Deux décisions se combinent mal : T12 produit un état de Riot où certaines routes n'existent plus, et T9 rend ce
404 définitif dès la première occurrence.

**Mesurer d'abord**, Riot Client tournant fenêtre fermée : quelles routes répondent encore ? (`GET region-locale`,
`PUT product-locales`, `POST product-launcher`, `GET swagger`). Puis, si l'interface est relancée (ou Riot
redémarré), la route revient-elle ? Hypothèse à vérifier : la route de la langue appartient à un plugin de
l'interface, détruit avec elle.

**Pistes selon la mesure** : (a) traiter le 404 sur un Riot sans fenêtre comme un état transitoire — redémarrer
Riot proprement puis retenter l'API, au lieu de basculer classique ; (b) ne compter en mémoire un `route` qu'après
confirmation sur un Riot fraîchement démarré, jamais sur un Riot dégradé ; (c) en dernier recours, ne plus fermer
la fenêtre (renoncer aux 600 Mo de T12) — à n'envisager que si rien d'autre ne tient.

**Test à écrire** : « Riot déjà lancé, fenêtre fermée → le lanceur ne le ferme pas et ne bascule pas en
classique ». Et un test réel enchaînant deux lancements à 60 s d'intervalle, le second devant rester sur l'API.
[ ]

## Risks
- Endpoint non documenté par Riot : relevé sur `swagger/v3/openapi.json` à l'exécution, et le repli rend l'échec non bloquant.
- `ServerCertificateValidationCallback` est global à .NET : posé puis restauré dans un `finally`.
- Le Riot Client réécrit le yaml à sa fermeture (`.DESCRIPTION` du lanceur) : vérifié en T4 ; la locale reste écrite avant tout lancement.
- Vanguard peut retarder l'ouverture de session : couvert par l'échéance de `Wait-RiotClientReady`.

## Deployment
None

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Lanceur testable | S | [x] |
| T2 — Adapter API locale | M | [x] |
| T3 — Lancement + repli | M | [x] |
| T4 — Essai, version, doc | S | [x] |
| T5 — Attente vs refus définitif | S | [x] |
| T6 — Session chaude + repli historique | M | [x] |
| T7 — Robustesse | M | [x] |
| T8 — Mémoire de lancement | M | [x] |
| T9 — Cause de l'échec mémorisée | S | [x] |
| T10 — Journal horodaté | M | [x] |
| T11 — Splash détaillé | S | [x] |
| T12 — Riot dans la zone de notification | M | [x] |
| T13 — Case dans l'assistant | M | [x] |
| T14 — Riot déjà lancé fermé à tort (bug 0.2.0) | M | [ ] |
| **Total** | **~L (5-8 h)** | |
