# Brief — launcher

## Objective

Faire que le lanceur enchaîne le démarrage de League of Legends sans clic sur le bouton Play du Riot Client.

Cause identifiée dans les journaux du Riot Client (`%LOCALAPPDATA%\Riot Games\Riot Client\Logs\Riot Client Logs`,
4 lancements sur 4 le 2026-09-19) : l'auto-lancement demandé par `--launch-product=league_of_legends --launch-patchline=live`
est accepté (`willAutoLaunch=true`) puis annulé 7 ms plus tard (`willAutoLaunch=false`), parce que la permission
`game:play` est évaluée avant l'authentification RSO et répond `isGranted=0 reason='UNAUTHORIZED'` ; l'intention n'est
jamais rejouée quand la permission est accordée 400 ms après. La page produit reste affichée, bouton Play `Playable`.

Le lanceur aggrave systématiquement la course en tuant `RiotClientServices` juste avant le démarrage : le client repart
à froid, sans permissions en cache, et le réseau arrive toujours après l'arbitrage.

Remède principal : ne tuer que le client de jeu (`LeagueClient*`) et laisser la session Riot chaude. Filet à froid :
rejouer `--launch-product` après authentification. Dernier recours : l'API locale du Riot Client (lockfile → port et
mot de passe, endpoint de lancement de produit). Le bouton Play reste un repli fonctionnel — jamais d'échec dur.

## Scope & rules

- Le mot de passe du `lockfile` du Riot Client ne sort jamais dans un log, un message de splash ou une exception.
- Le bouton Play du Riot Client reste un repli fonctionnel : le lanceur ne produit aucun échec dur si l'API locale ne répond pas.
- Chemin rapide : seul le client de jeu est fermé, et la langue est posée par l'API du Riot Client — écrire
  `settings.locale` dans son dos ne tient pas, il réécrit le fichier depuis sa mémoire (mesuré le 2026-09-20).
- Le chemin historique — fermeture complète de Riot, écriture du yaml, `--launch-product` — reste présent,
  testé pour lui-même, déclenché dès que l'API ne répond pas et forçable par `-NoLocalApi`.
- Un code HTTP de succès ne suffit pas à conclure : le client de jeu doit apparaître.
- Aucune mémoire sur disque ne décide du chemin de lancement : seuls `-NoLocalApi` (ligne de commande,
  dépannage — jamais posé par les raccourcis) et la case « Démarrage manuel » de l'assistant écartent l'API
  durablement ; le bouton du splash ne vaut que pour le lancement en cours. Le lanceur n'écrit jamais
  `config.json`. La règle « le poste retient ce qu'il a appris » (`launch-state.json`) est retirée le
  2026-09-20 : elle a rendu un 404 ponctuel permanent et invisible.
- Riot Client réglé par l'utilisateur pour se réduire dans la zone de notification à la fermeture de sa fenêtre,
  et non quitter : après une partie, `RiotClientServices` reste seul, sans interface — c'est l'état où la route
  de la langue répond 404.
- Vocabulaire utilisateur : le chemin de repli s'appelle « démarrage manuel » partout (splash, journal, README) —
  ce qui reste à faire, c'est appuyer sur Jouer dans le Riot Client. Case de l'assistant : « Démarrage manuel »
  sous le titre « Compatibilité Riot », note dessous (texte validé le 2026-09-20) ; bouton du splash : « Forcer en démarrage manuel ». Jamais « mode de secours »,
  « lancement classique » ni « chemin historique » (règle utilisateur, 2026-09-20, révisée le même jour). `legacy`
  reste l'identifiant de code.
- Nom de produit : « Hex Launcher » (deux mots, L majuscule) dans tout texte lu par l'utilisateur — README, LISEZMOI, titres de fenêtre, infobulles, release. `hex-launcher` reste le nom du dépôt, de l'archive, des dossiers et des fichiers (règle utilisateur, 2026-09-20).
- Fermeture du client de jeu : par l'API du Riot Client (`DELETE` de la session, arrêt propre pour Vanguard) sur
  le chemin rapide seulement ; le kill reste le repli si l'API ne ferme pas. En démarrage manuel (case de
  l'assistant, `-NoLocalApi`), fonctionnement d'avant — kill des process, aucun appel d'API (règle utilisateur,
  2026-09-20).
- L'utilisateur ne doit jamais avoir à ouvrir `config.json` : tout réglage qu'il peut avoir à corriger se corrige
  dans l'assistant (règle utilisateur, 2026-09-20).
- Lancements réels par Claude : autorisés (levée par l'utilisateur le 2026-09-20), mais **jamais plus d'un cycle
  toutes les 3-4 minutes** : VAN 216 tombe au 4ᵉ ou 5ᵉ démarrage du client de jeu en quelques minutes, que la
  fermeture soit un kill ou un arrêt propre par l'API (mesuré trois fois le 2026-09-20 : ~15 cycles avec kill le
  matin, 4 en 3 min l'après-midi, 5 en 5 min avec fermeture API à 17:30). C'est la cadence des connexions Vanguard
  qui compte. Les tests Pester restent unitaires, tout est moqué.
- Aucune écriture de journal, aucun chemin périmé, aucun recul d'horloge ne doit faire échouer un lancement.
