# Brief — icons

## Objective

Différencier visuellement les raccourcis « langue × appli compagnon » par une pastille originale en coin de l'icône
(couleur + lettre propres à chaque compagnon : Porofessor, Blitz, OP.GG, Mobalytics), sans aucun logo tiers.
La pastille est définie dans `companion-apps.json`, composée à la demande sur l'icône drapeau par `create-shortcuts.ps1`,
lisible de 256 à 16 px (couleur seule en dessous de 32 px). Livraison en version 0.1.2.

## Scope & rules

- Aucun actif de Riot n'entre dans le dépôt ni dans la release : l'icône officielle du jeu est **référencée** depuis
  le binaire installé (`IconLocation`), jamais copiée, jamais extraite vers un fichier du projet, et aucune pastille
  n'est composée dessus.
