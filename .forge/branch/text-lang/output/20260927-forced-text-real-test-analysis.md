# Essai réel du texte forcé — analyse de l'échec et autre moyen

**Date :** 2026-09-27 · **Branche :** `text-lang` · **Sources (lecture seule) :** `app\launch.log`, `C:\Riot Games\League of Legends\Logs\LeagueClient Logs\*_LeagueClient.log`, dates et SHA-256 des fichiers installés.

## 1. Ce qui s'est passé (13:18, raccourci ja_JP voix / fr_FR texte)

| Temps client | Heure | Événement | Source |
|---|---|---|---|
| 0 s | 13:18:14 | Client LoL démarré, détecté par le lanceur | launch.log |
| +3 s | 13:18:17 | Fichiers texte fr_FR téléchargés (3 s) et posés sous les noms ja_JP | launch.log |
| +11,3 s | — | `rcp-be-lol-patch` : « Patcher Verifying game install » puis « Performing install verification » | LeagueClient.log |
| +11,9 s | — | « Install failed to verify due to 0 missing files, **2 inconsistent files** » → « Starting game update » | LeagueClient.log |
| +14,06 s | — | `rcp-be-lol-login` : « Login failed because we couldn't process the id-token » — `ID_TOKEN_INVALID_FORMAT` → erreur de connexion affichée | LeagueClient.log |
| +14,5 s | 13:18:27–28 | « Game update successful » : Global/UI.ja_JP réécrits, `Game.db` mis à jour | LeagueClient.log + dates |

État après coup : les deux fichiers installés ont le même SHA-256 que la sauvegarde ja_JP — l'installation est revenue à l'identique, réparée par Riot.

## 2. Ce que ça apprend

- **Pas de surveillance continue** : le client LoL fait **une seule** vérification de l'installation, ~11 s après son démarrage (plugin `rcp-be-lol-patch`). Les 10 journaux relevés (21 → 27/09) en contiennent chacun exactement une, y compris celui du 25/09 où une partie a été lancée à +200 s sans nouvelle vérification.
- La pose « à l'apparition du client » tombait **avant** cette vérification : elle était donc forcément annulée.
- **Erreur de connexion** : `ID_TOKEN_INVALID_FORMAT` n'apparaît dans aucun des 9 journaux précédents, y compris ceux où la vérification avait échoué après un patch (21, 22, 24/09). Elle est donc **corrélée** à notre pose, mais la cause n'est pas prouvée (connexion pendant la réparation, ou coïncidence).
- Riot journalise la modification (« 2 inconsistent files ») : c'est un signal côté détection, même si ce message apparaît aussi après chaque patch.

## 3. Autre moyen proposé : poser après la vérification et la connexion

Fenêtre visée : **après** la vérification unique du client et la connexion réussie, **avant** le début d'une partie (`League of Legends.exe`, seul lecteur de Global/UI).

- Attendre que l'API locale du client LoL (lockfile `C:\Riot Games\League of Legends\lockfile`, lecture seule, requêtes GET) indique :
  - patcher au repos et à jour : `GET /patcher/v1/products/league_of_legends/state` ;
  - connexion réussie : `GET /lol-login/v1/session` → `state = SUCCEEDED`.
- Poser seulement à ce moment ; délai maximal (ex. 3 min), sinon renoncer (partie dans la langue des voix).
- Restauration inchangée : au lancement suivant, avant le changement de langue. Si elle manque (LoL lancé autrement), la vérification du démarrage suivant répare de toute façon.

## 4. Risques et inconnues

- **Le jeu peut contrôler lui-même** ses fichiers au chargement (build « packedvan », Vanguard) : seul un essai réel le dira.
- **Connexion** : si l'erreur de jeton venait de la modification elle-même, et pas du moment choisi, elle peut revenir à la connexion suivante.
- Les deux points d'API du client LoL ne sont pas documentés par Riot (usage communautaire) : en cas de réponse inattendue, on renonce proprement.
- Le risque de ban reste entier : c'est toujours une modification de fichiers du jeu.
