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
- Le poste retient ce qu'il a appris de l'API locale (`launch-state.json`) : deux échecs consécutifs l'écartent,
  un changement de version du Riot Client la fait retenter. L'utilisateur n'a jamais à diagnostiquer lui-même.
- Aucune écriture de mémoire, aucun chemin périmé, aucun recul d'horloge ne doit faire échouer un lancement.
