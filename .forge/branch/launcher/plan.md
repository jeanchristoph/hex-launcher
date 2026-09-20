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

### T15 — Retirer la mémoire de lancement
**Effort:** S
**Files:** `app/lib/launch-state.lib.ps1` (supprimé), `app/launch-lol.ps1`, `tests/launch-state.lib.tests.ps1` (supprimé), `tests/launch-lol.tests.ps1`, `.gitignore`, `tools/make-release.ps1`, README ×3, `.forge/project.md`, `output/` (arbre de décision)
**Description:** Décision du 2026-09-20 : la mémoire a rendu le bug de T14 *collant* (un 404 ponctuel → chemin
classique pour toujours, sans rien à l'écran) et n'économise du temps que sur des pannes jamais observées
(`silent`, `timeout`). Le lanceur redevient sans état : l'API est tentée à chaque lancement sauf `-NoLocalApi`
ou case « Lancement classique » (T13) ; `launch-state.json` n'est plus ni lu ni écrit. La cause d'échec
(`Failure.Kind`, code, étape) reste rendue et journalisée, pour le support seulement. Placée avant T14, plus
simple à raisonner sur un lanceur sans état.
[x] 2026-09-20 — lib et tests supprimés, `New-LocalApiFailure` et `Get-RiotClientVersion` dans le lanceur, journal `START chemin=…` ; README ×3, project.md, arbre ; 497 verts, `-DryRun` réel passé

### T16 — Bouton « Forcer le démarrage » sur le splash — pour le lancement en cours seulement
**Effort:** M
**Files:** `app/lib/splash.lib.ps1`, `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/splash.lib.tests.ps1`, `tests/riot-client-api.lib.tests.ps1`, `tests/launch-lol.tests.ps1`, README ×3, `output/`
**Description:** Après 15 s d'attente sur le chemin rapide (un lancement normal tient en 8 à 13 s, le bouton ne
doit tenter personne quand tout va bien), le splash montre « Forcer le démarrage » (un bouton porte un verbe ;
« Mode de secours » décrit un état, il reste le nom de la case). Statut après le clic : « Démarrage forcé :
fermeture de Riot puis redémarrage… ». Un clic abandonne les boucles
d'attente (`-ShouldStop` vérifié à chaque tour de `Wait-RiotClientOperation` et `Wait-GameClientStart`,
`Kind = 'cancelled'`) et bascule tout de suite en mode de secours. Rien n'est mémorisé : le lancement suivant
retente le lancement direct ; la case de setup.bat reste le seul réglage durable. Le splash reste ignorant du
lanceur (`Add-SplashAction -Text -OnClick`, montré par lui après le délai, caché au clic et dès que le chemin
rapide rend la main). Journal : `cause=cancelled`.
Décisions de l'utilisateur (2026-09-20) : un bouton dans chaque sens sur un splash n'est pas exploitable par un
humain ; un clic qui coche la case rendrait le mode collant sans retour visible. `-NoLocalApi` reste un
interrupteur de ligne de commande pour le dépannage, jamais posé par les raccourcis.
[x] 2026-09-20 — `Add-SplashAction`/`Show`/`Hide` (état demandé dans le Tag du bouton), `-ShouldStop` dans les trois
boucles, `Kind = 'cancelled'`, statut « Démarrage forcé » ; clic vérifié en réel par harnais (bouton à 3 s, clic
→ secours en 1 s) — l'attente > 15 s ne se provoque pas à la demande, les lancements réels sont passés en 3,8 à
8,7 s sans bouton ; au passage : titre et sous-titre du splash jamais affichés depuis 0.1.0 (collision `$title` /
`[string]$Title`) corrigés, barre marquee inerte remplacée par un filet doré ; 517 verts

### T14 — Bug : Riot déjà lancé, pourtant fermé et redémarré en mode classique
**Effort:** M
**Files:** `app/lib/riot-window.lib.ps1`, `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, tests
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
[x] 2026-09-20 — Mesuré : Riot replié + jeu terminé → toutes les routes 404, port changé (API déchargée) ; aucune
route native de pilotage de l'interface ; relancer `RiotClientServices.exe` sans argument réveille la même
instance, interface et API revenues en 2 à 3 s. Codé : `Restore-RiotClientInterface` (Riot déjà en marche sans
process « Riot Client » → relance sans argument, jamais de kill, attente interface + `GET region-locale`),
`Test-RiotClientReady`, 409 parmi les codes d'attente ; sonde `tools/probe-riot-client-api.ps1` ; 533 verts.
Réel : scénario du bug (Riot replié, jeu fermé, relancement) vérifié — réveil 2,3 s, jeu par l'API en 10 s.
**RÉSERVE** : le second scénario (jeu ouvert, Riot replié, relancement immédiat) n'a pas été rejoué —
Vanguard a émis VAN 216 après la rafale de lancements/kills de la matinée, y compris sur un lancement normal ;
session arrêtée pour redémarrer Windows. À vérifier une seule fois, par l'utilisateur, quand Vanguard sera sain.

### T17 — Chemins Riot modifiables dans l'assistant
**Effort:** M
**Files:** `app/setup.ps1`, `app/lib/theme.lib.ps1`, `app/lib/launch-config.lib.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/setup.tests.ps1`, `tests/launch-config.lib.tests.ps1`, README ×3
**Description:** Page 1 : « Riot Client » et « Fichier de langue de LoL » deviennent des champs de saisie avec un
bouton « Parcourir… » (`OpenFileDialog` filtré `.exe` / `.yaml`, ouvert sur le dossier du chemin courant, sinon
`C:\Riot Games`). Le statut « Trouvé / Introuvable » se recalcule à chaque modification. Sur « Suivant », les
chemins sont enregistrés dans `config.json` seulement s'ils ont changé (`Save-LaunchRiotPaths`) ; un chemin encore
introuvable n'empêche pas d'avancer mais reste signalé en rouge, et le résumé final le rappelle. Les chemins saisis
survivent au changement de langue (portés par `Get-SetupPageSelection`). Intro réécrite en trois langues :
« corrigez-les ici » au lieu de « dans config.json » ; `detect-config.ps1` inchangé (il ne fait que détecter).
Demande de l'utilisateur (2026-09-20) : ne jamais avoir à ouvrir config.json.
[x] 2026-09-20 — champs modifiables + « Parcourir… » (`OpenFileDialog` filtré, ouvert sur le dossier du chemin
courant sinon `C:\Riot Games`), statut recalculé à chaque frappe, chemin collé entre guillemets accepté ;
`Save-LaunchRiotPaths` n'écrit que si un chemin change ; saisie conservée au changement de langue ; rappel rouge sur
la page Terminé ; i18n ×3, README ×3 ; rendu vérifié par capture (fr/en/ja, chemin du yaml sur 3 lignes) ; 559 verts

### T18 — Raccourci « Hex Launcher » sur le Bureau
**Effort:** S
**Files:** `app/create-shortcuts.ps1`, `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/create-shortcuts.tests.ps1`, `tests/setup.tests.ps1`, README ×3
**Description:** À l'étape *Raccourcis* de l'assistant (c'est elle qui écrit sur le Bureau), un raccourci
`Hex Launcher.lnk` est posé à côté des raccourcis de langue — même destination, même repli dans le
dossier du lanceur. Cible `setup.bat`, dossier de travail = racine, fenêtre réduite, infobulle « Ouvre l'assistant
de configuration ». Toujours recréé (suit un déplacement du dossier), jamais retiré par `Remove-ObsoleteShortcuts`.
Résumé final : une ligne. Nom fixe quelle que soit la langue. Icône `app\ico\<jeu>\hex-launcher-setup.ico`
(engrenage), repli sur `hex-launcher.ico` du jeu tant que le fichier n'existe pas — le .ico se produit sur la
branche `icons` (règle du 2026-09-20). Demande de l'utilisateur (2026-09-20).
[x] 2026-09-20 — `New-SetupShortcut` (vers setup.bat, racine en dossier de travail), `Resolve-IconSetFile` factorisé
pour le drapeau et l'engrenage (`$IconSetSetupIcon`, repli sur la base), `New-ShortcutWithFallback` partagé ; posé
par l'étape Raccourcis, cité dans le résumé, échec non bloquant ; i18n ×3, README ×3 ; 569 verts. Engrenage fourni
par l'utilisateur (`tools/logo/hex_launcher_gear_multisize.ico`, 8 tailles) → `app/ico/hex-launcher-setup.ico`,
commun à tous les jeux, livré par la release ; repli sur l'icône de base du jeu s'il manque.

### T19 — Raccourci relatif « Hex Launcher » dans l'archive de release
**Effort:** S
**Files:** `tools/make-release.ps1`, `tests/make-release.tests.ps1`, README ×3
**Description:** `make-release.ps1` fabrique `Hex Launcher.lnk` à la racine du staging : cible absolue du staging
(inexistante chez le joueur) + `RelativePath` `setup.bat`, que l'Explorateur résout depuis l'emplacement du `.lnk`
quand l'absolu manque — l'archive se décompresse n'importe où. Fenêtre réduite. Icône : `app\ico\hex-launcher-setup.ico`
en relatif, à vérifier (IconLocation n'a pas de résolution relative documentée). Test : présence du `.lnk`, drapeau
HasRelativePath et chaîne relative lus dans le fichier. Essai réel : staging déplacé dans un autre dossier, lien
résolu par `ShellLinkObject.Resolve` (sans interface) vers le `setup.bat` déplacé ; icône relevée par `SHGetFileInfo`.
Si l'icône ne tient pas : décision utilisateur (garder sans engrenage, ou ne pas embarquer). Demande de l'utilisateur
(2026-09-20). Réserve : déplacé hors du dossier, le `.lnk` relatif ne pointe plus sur rien — T18 reste le raccourci du Bureau.
[x] 2026-09-20 — `New-ReleaseSetupShortcut` (RelativePath = chemin du .lnk → le shell stocke « setup.bat » et pose
HasRelativePath) ; test de résolution après déplacement (`ShellLinkObject.Resolve`) ; essai réel sur l'archive extraite
ailleurs : cible résolue, engrenage affiché depuis un répertoire courant étranger ; README ×3 ; 572 verts
[!] RETIRÉE le 2026-09-20 (branche icons) : la mesure « engrenage affiché » était fausse — la sonde tournait avec le
dossier du projet comme répertoire courant, où `app\ico\…` existe. Depuis `C:\Windows` (cas de l'Explorateur), l'icône
relative rend un carré vide : le format .lnk n'a pas de repli relatif pour l'icône, seulement pour la cible. Décision de
l'utilisateur : pas de raccourci dans l'archive. `New-ReleaseSetupShortcut`, ses tests et la mention README retirés.

### T20 — Bug : jeu lancé mais boucle qui insiste (423), fenêtre Riot non repliée
**Effort:** S
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/riot-client-api.lib.tests.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Journal du 2026-09-20 15:45 : Riot replié, réveillé en 4 s, langue posée, puis `POST product-launcher`
→ code 0 après 7,1 s (délai WinHTTP) alors que Riot a exécuté la demande ; toutes les tentatives suivantes → 423
(« un client de jeu tourne » — le nôtre) jusqu'au bout des 60 s. La garde tardive de `Start-LeagueClient` concluait
`api` mais sautait le repli de la fenêtre Riot. Correctif : `Wait-RiotClientOperation -SuccessProbe` (sonde évaluée
avant chaque tentative et une dernière fois au budget épuisé ; vraie → `Kind = 'probe'`), transmise par
`Wait-RiotProductLaunch` ; le lanceur passe `Test-GameClientRunning`. `Complete-LocalApiLaunch` (repli de la fenêtre)
appelée aussi par la garde tardive. Délai de 7 s inchangé : la sonde couvre le cas.
[x] 2026-09-20 — sonde de succès, journal `GAME client de jeu déjà en marche pendant la demande (dernier code N)`,
garde tardive complète ; 8 tests ; 644 verts. Essai réel à faire par l'utilisateur au prochain lancement (scénario :
Riot replié après une partie).

### T22 — Fermeture propre du client de jeu par l'API du Riot Client
**Effort:** M
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tools/probe-riot-client-api.ps1`, tests, `output/`
**Description:** VAN 216 revient après des fermetures brutales rapprochées du client de jeu (`Stop-Process` pendant
que Vanguard y est attaché : ~15 cycles le matin, 4 lancements en 3 min l'après-midi). `CloseMainWindow` a été
essayé le 2026-09-20 02:15 et ignoré par le client ; l'API du Riot Client n'a jamais été sollicitée pour fermer.
Sonder `GET /product-session/v1/sessions` (lecture seule) pour relever l'identifiant de session du jeu, puis
**un** essai réel à la main de l'utilisateur, après redémarrage de Windows, jeu ouvert : `DELETE` sur cette session.
Ferme le jeu en quelques secondes → le lanceur l'utilise avant `Stop-Process` (dernier recours après échéance), et
mesure si la session Riot est libérée sans les 3,5–57 s d'attente (424). Sinon → tâche close, kill conservé.
T21 (ne pas relancer un jeu déjà dans la bonne langue) proposée et écartée par l'utilisateur.
[x] 2026-09-20 — essai réel : DELETE (objet session en corps, sinon 400) → 204, jeu fermé en 0,5 s avec exit code 0,
Riot Client quitté puis relancé seul en arrière-plan (état T14, déjà couvert). Lanceur : `Stop-GameClient` (API puis
kill en dernier recours, attente 5 s), lib : `Read-RiotClientResource`, `Find/Remove-RiotProductSession`,
`Stop-RiotProduct`, `-LoggedPath` (id de session = jeton du jeu, jamais journalisé) ; README ×3, project.md ; 665 verts

### T23 — Budgets rallongés : 5 min avant repli, « Forcer » dès 1 min 30
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`, README ×3
**Description:** Sur le poste de l'utilisateur, un lancement approche la minute : `$LocalApiBudgetSeconds` 60 → 300,
`$ForceStartButtonDelaySeconds` 15 → 90, `$GameClientStartTimeoutSeconds` 30 → 90 (l'apparition du client est l'étape
qui souffre le plus d'un disque lent). Commentaires des constantes et en-tête du lanceur réalignés, mention
« plus de 15 s » des README ×3 → 1 min 30. Tests des seuils mis à jour. Demande de l'utilisateur (2026-09-20), après T22.
[x] 2026-09-20 — trois seuils posés (300 / 90 / 90, puis 360 / 120 / 180 sur demande de l'utilisateur), en-tête du lanceur, README ×3, arbre de décision d'OUTPUT ;
tests des seuils + test « démarrage manuel = kill des process, aucun appel d'API » (règle utilisateur) ; 670 verts

### T24 — Section « Compatibilité Riot » dans l'assistant
**Effort:** S
**Files:** `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/setup.tests.ps1`, README ×3
**Description:** Page Raccourcis : titre doré « Compatibilité Riot », case « Démarrage manuel » (libellé raccourci,
règle utilisateur), note grise dessous : « Si le lancement automatisé ne fonctionne pas : vos paramètres sont appliqués
(langue, appli compagnon), le client Riot s'ouvre et vous devez appuyer sur « Jouer ». » — texte validé mot à mot par
l'utilisateur avant traduction. Fenêtre 620 → 680 px pour garder le journal. `Get-SetupRiotCompatibilityLayout` (pure,
testée). Option C retenue parmi trois (libellé enrichi, note seule, section). Demande de l'utilisateur (2026-09-20).
[x] 2026-09-20 — section en place, deux clés i18n ×3, « lancement direct » → « lancement automatisé » dans le journal
de l'assistant, README ×3 (case) ; 674 verts. À voir dans setup.bat par l'utilisateur.

### T25 — Bug : réveil de Riot perdu pendant sa bascule en arrière-plan
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Journal du 2026-09-20 17:00 : jeu fermé à la main, Riot replié, changement de langue aussitôt →
la relance sans argument tombe pendant que Riot démonte ses plugins (« Attempting to quit and switch to background
mode ») ; la nouvelle instance dit « Client already running, exiting » à une instance qui n'écoute plus, l'interface
ne revient jamais → 15,6 s d'attente, `PUT` 404, démarrage manuel (kill de Riot). Correctif :
`Restore-RiotClientInterface` attend 5 s (`$RiotClientInterfaceRetrySeconds`), puis rejoue la relance une fois
(journal `RIOT seconde relance…`) et attend le reste de l'échéance, portée de 15 à 30 s (choix utilisateur).
`-ShouldStop` respecté entre les deux relances. Bug relevé par l'utilisateur.
[x] 2026-09-20 — relance rejouée à 5 s, échéance 30 s ; 4 tests (une relance suffit / rejouée / reste d'échéance ≥ 1 s /
jamais rejouée après « Forcer ») ; 677 verts. Essai réel : jeu fermé à la main, Riot replié, raccourci aussitôt.

### T26 — Un seul lanceur à la fois
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Journal du 2026-09-20 17:14 : deux raccourcis cliqués à 3 s d'écart → deux lanceurs en parallèle, lignes
d'API en double, puis deux démarrages manuels successifs (chacun tuant le Riot de l'autre). Mutex système nommé pris au
démarrage ; déjà pris → splash « Un lancement est déjà en cours » 3 s, journal `START refusé — lancement déjà en cours`,
sortie sans kill ni appel d'API. Libéré à la fin du lanceur, quoi qu'il arrive (`finally`).
[x] 2026-09-20 — `Enter-LaunchLock`/`Exit-LaunchLock` (mutex `Local\HexLauncher.Launch`, abandonné repris), splash
3 s « Un lancement est déjà en cours » ; 5 tests (dont verrou tenu par un autre fil, abandonné) ; essai réel : second
raccourci refusé, premier fini en 14 s.

### T27 — Fenêtre Riot refermée pendant l'attente
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Même journal : fenêtre Riot fermée à 17:14:34 pendant la boucle de lancement → Riot en arrière-plan,
API déchargée, code 0 à chaque essai jusqu'au budget. La garde de boucle (`$guardedTick`) surveille aussi l'interface :
Riot vivant mais sans interface → `Restore-RiotClientInterface` rejoué (journal `RIOT interface disparue pendant
l'attente — réveil`), au plus une fois par disparition, jamais en rafale.
[x] 2026-09-20 — `Watch-RiotClientInterface` (drapeau « vue » par lancement) dans `$guardedTick` ; 4 tests. Essai réel
non concluant pour ce cas précis : fermer la fenêtre pendant un lancement replie Riot sans décharger l'API (session
présente), le jeu part quand même en 14,8 s — le cas « aucune session » du 17:14 reste couvert par les tests seuls.

### T28 — 424 : dire pourquoi on attend
**Effort:** M
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, `tests/riot-client-api.lib.tests.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Le 424 couvre deux attentes très différentes : session précédente à libérer (3 s à 1 min) et **patch du
jeu en cours** (journal Riot 17:14 : « Product 'league_of_legends' not up to date », 58 s de mise à jour). Sur 424, lire le
corps (`errorDescription`) et afficher sur le splash « Riot met le jeu à jour… » ou « Riot libère la session
précédente… ». Corps jamais journalisé. Textes FR validés par l'utilisateur avant écriture.
[x] 2026-09-20 — `Get-RiotClientWaitReason` (424 + « not up to date » → updating, sinon releasing), `WaitReason` sur
chaque résultat, `-OnWait` sur la boucle (une fois par changement), `Get-WaitReasonStatus` + journal `WAIT 424 : …` ;
`Send-WinHttpRequest` retiré (un seul transport) ; 12 tests ; 711 verts.

### T29 — Avertissement de cadence sur le splash (VAN 216)
**Effort:** S
**Files:** `app/lib/launch-log.lib.ps1`, `app/launch-lol.ps1`, `tests/launch-log.lib.tests.ps1`, `tests/launch-lol.tests.ps1`
**Description:** VAN 216 à 17:30 après 5 démarrages du client de jeu en 5 min, tous fermés proprement : la fermeture par
l'API ne protège pas, c'est la cadence des connexions Vanguard. Le lanceur ne peut pas l'empêcher : il compte les
`START` de `launch.log` sur les 5 dernières minutes (`Get-RecentLaunchCount`, lecture bornée aux 400 dernières lignes,
lancements refusés exclus) et, à partir du 3ᵉ, affiche 3 s « Trop de lancements rapprochés : risque d'erreur Vanguard
VAN 216 (redémarrage de Windows requis) » (texte validé mot à mot), journal `WARN`, puis continue. T21 de nouveau écartée.
[x] 2026-09-20 — `Test-LaunchBurst` (seuil 3 / fenêtre 5 min / 3 s), 7 tests ; montré à l'utilisateur en DryRun ×3 ; 693 verts.

### T30 — README : VAN 216
**Effort:** S
**Files:** README ×3
**Description:** Après l'étape 4 du lanceur : « À partir de quatre démarrages du jeu en moins de cinq minutes, Vanguard
affiche l'erreur VAN 216 et ferme le client, quelle que soit la manière dont il a été fermé. Un redémarrage de Windows est
alors nécessaire » (texte validé), plus la mention du splash qui prévient au 3ᵉ. Traduit en, ja.
[x] 2026-09-20 — README ×3.

### T31 — Plus de limite d'attente sur le lancement direct ni sur l'apparition du client
**Effort:** S
**Files:** `app/lib/riot-client-api.lib.ps1`, `app/launch-lol.ps1`, tests, notes de release
**Description:** Un patch du jeu sur une connexion lente peut durer des heures : le budget du lancement direct
(6 min) et l'attente du client de jeu (3 min) sont supprimés — `$NoTimeLimitSeconds = 0`, `Test-WaitBudgetExhausted`,
`Get-RemainingBudgetSeconds` transparent. Seuls un refus franc de l'API, le bouton « Forcer » ou la croix (T32) sortent.
Décision de l'utilisateur (« autant le faire péter », 2026-09-20).
[x] 2026-09-20 — deux budgets à ∞, 6 tests ; 700 verts.

### T32 — Croix de fermeture sur le splash
**Effort:** S
**Files:** `app/lib/splash.lib.ps1`, `app/launch-lol.ps1`, `tests/splash.lib.tests.ps1`, `tests/launch-lol.tests.ps1`, README ×3
**Description:** Croix en haut à droite du splash, visible dès le début. Un clic arrête le lanceur : la boucle en cours
rend la main (drapeau lu à chaque tour, comme « Forcer ») mais sans démarrage manuel — rien n'est tué, Riot et le jeu
restent en l'état, le compagnon n'est pas lancé. Journal `END issue=cancelled`, splash « Lancement interrompu » 1 s.
Verrou libéré : un raccourci peut être recliqué aussitôt. README ×3, une ligne. Demande de l'utilisateur (2026-09-20).
[x] 2026-09-20 — `Add-SplashCloseButton` (étiquette ✕, dorée au survol, par-dessus les contrôles ancrés),
`-ShouldAbort` sur `Start-LeagueClient` (drapeau combiné à « Forcer » pour les boucles, issue `cancelled` sans démarrage
manuel), journal `ABORT`, README ×3 ; 5 tests ; 716 verts. Montré en DryRun.

### T33 — Réveil de Riot sans limite, relance périodique
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Le réveil (30 s) menait au démarrage manuel par un faux 404 quand Riot ne rouvrait pas sa fenêtre
(17:00). Plus d'échéance : relance à 0 s, 5 s, puis toutes les 30 s (`$RiotClientRelaunchIntervalSeconds`, journal
`RIOT relance n° N après X s`) tant que fenêtre et API ne sont pas là, jusqu'à « Forcer » ou la croix. Plus de
première requête envoyée à une API absente. `$RiotClientInterfaceTimeoutSeconds` retiré.
[x] 2026-09-20 — boucle de relance (5 s puis 30 s, `Format-RiotRelaunchReason`), faux seulement sur arrêt utilisateur ou
exécutable introuvable ; tests réécrits ; notes de release : Known limits 1 retirée, sans limite + croix + motif du 424 ;
716 verts.

### T34 — make-release : notes de release remises par fichier
**Effort:** S
**Files:** `tools/make-release.ps1`, `tests/make-release.tests.ps1`
**Description:** Les notes de la release 0.2.0 sont parties tronquées (558 caractères sur 5 900) : passées en argument
`--notes "<texte>"`, PowerShell 5.1 coupe au premier guillemet double. Réparé à la main (`gh release edit --notes-file`).
`Publish-Release` écrit désormais les notes formatées dans `distelease-notes-v<version>.md` (UTF-8 sans BOM, LF,
conservé à côté du zip) et appelle `gh release create … --notes-file`. Nouveau `-NotesFile <chemin>` (prioritaire sur
`-Notes`). Tests : fichier écrit avec guillemets et retours intacts, lecture du fichier, `gh` reçoit `--notes-file`.
[x] 2026-09-20 — `Read-ReleaseNotes`, `Write-ReleaseNotesFile`, `--notes-file` ; 4 tests ; archive reconstruite sans
publier (SHA-256 identique) ; 719 verts.

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
| T15 — Retirer la mémoire de lancement | S | [x] |
| T16 — Bouton « Forcer le démarrage » sur le splash | M | [x] |
| T14 — Riot déjà lancé fermé à tort (bug 0.2.0) | M | [x] réserve : 2ᵉ scénario réel à rejouer |
| T17 — Chemins Riot modifiables dans l'assistant | M | [x] |
| T18 — Raccourci « Hex Launcher » sur le Bureau | S | [x] |
| T19 — Raccourci relatif « Hex Launcher » dans l'archive | S | [!] retirée le 2026-09-20 — l'icône d'un .lnk ne peut pas être relative |
| T20 — Bug : 423 après demande expirée, fenêtre Riot non repliée | S | [x] |
| T22 — Fermeture propre du client de jeu par l'API | M | [x] |
| T23 — Budgets 5 min / « Forcer » à 1 min 30 | S | [x] |
| T24 — Section « Compatibilité Riot » dans l'assistant | S | [x] |
| T25 — Réveil de Riot rejoué (bascule en arrière-plan) | S | [x] |
| T26 — Un seul lanceur à la fois | S | [x] |
| T27 — Fenêtre Riot refermée pendant l'attente | S | [x] |
| T28 — 424 : dire pourquoi on attend | M | [x] |
| T29 — Avertissement de cadence VAN 216 sur le splash | S | [x] |
| T30 — README : VAN 216 | S | [x] |
| T31 — Plus de limite d'attente (lancement, client de jeu) | S | [x] |
| T32 — Croix de fermeture sur le splash | S | [x] |
| T33 — Réveil de Riot sans limite, relance périodique | S | [x] |
| T34 — make-release : notes par fichier | S | [x] |
| **Total** | **~L (5-8 h)** | |
