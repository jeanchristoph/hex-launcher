# Log — text-lang

- [2026-09-26] Étude CDN : faisable (manifest local Game.ok/Game.manifest + HTTP Range + libzstd.dll). Replanification directe sans prototype, choix utilisateur : T3 = brique CDN (L), pose/restauration en T4, renumérotation T5–T9.

- [2026-09-26] Option A retenue : étude de faisabilité du téléchargement des seuls fichiers texte (Global/UI.<locale>.wad.client) depuis le CDN Riot — une relance FR par patch (option B) coûterait ~3,8 Go de voix à chaque fois. Plan en attente de l'étude.
- [2026-09-26] Consigne : installation LoL de l'utilisateur en lecture seule pendant le dev ; T2 réduit à de la lecture + essai manuel par l'utilisateur.
- [2026-09-26] Mesure ja_JP : voix Champions 3,4 Go + Maps/Shipping 374 Mo ; texte jeu Localized/Global 3,9 Mo + UI 0,1 Mo ; Plugins client ~41 Mo. Mécanisme inversé validé : locale Riot = voix, copie des 4 Mo de texte forcé. Client LoL reste dans la langue des voix.
- [2026-09-26] Setup : pas de liste « voix » ; une case « Forcer le texte en : [select] » (+ avertissement rouge) appliquée à tous les raccourcis cochés. Langue cochée = voix, select = texte.
- [2026-09-26] Constat : seuls les fichiers de la locale active sont installés (`Game/DATA/FINAL/Champions/<Champion>.<locale>.wad.client`). Aucun réglage Riot pour séparer texte et voix → copie de .wad validée par l'utilisateur.
