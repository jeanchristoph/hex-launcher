# Log — text-lang

- [2026-09-27 13:20] T9 : doc FR validée, EN/JA traduits (agent) ; suite complète 851/851. Plan entièrement coché — essai réel par l'utilisateur à faire.
- [2026-09-27 13:05] T8 : case et liste empilées (demi-colonne de 250 px trop étroite pour les deux) ; textes validés FR puis EN/JA ; contrôles ajoutés à $SetupPageControlNames (IconSetList et LegacyLaunchBox n'y sont pas — préexistant).
- [2026-09-27 12:40] T7 : lib dédiée icon-split.lib.ps1 ; tige des icônes renommée Get-CombinationIconStem (voix-texte-compagnon) ; avertissement « Icône coupée … non composée » validé FR puis EN/JA. Drapeaux à emblème centré (JP, KR) moins lisibles une fois coupés.
- [2026-09-27 11:50] T6 : nom « League of Legends JP-FR » — « / » interdit dans un nom de fichier, « ⁄ » (U+2044) rejeté par WScript.Shell (conversion ANSI → « / ») ; infobulles validées (nom du compagnon seul, pas « appli compagnon »).
- [2026-09-27 11:30] T5 : restauration au début de chaque lancement (avant le changement de langue), pose après l'apparition du client LoL (patch Riot terminé) ; démarrage manuel : attente du client 10 min au plus (choix utilisateur). Textes splash validés : « Texte du jeu en {langue}… », « Texte forcé indisponible — jeu dans la langue des voix ».
- [2026-09-27 11:24] T4 : pas de dossier de sauvegarde — les fichiers de la voix amorcent son cache CDN (identiques pour ce manifest) ; restauration via le cache, retéléchargée si un patch a changé le manifest ; marqueur hors du dossier du jeu.
- [2026-09-27 11:16] T3 terminé : riot-cdn.lib.ps1 (transport) séparé de riot-text-files.lib.ps1 (Game.ok/manifest/cache) — fichier ajouté au plan, SRP.
- [2026-09-27 11:09] T3.3 : essai CDN réel vers le scratchpad — Global.ja_JP (0,6 s) et UI.ja_JP (2,1 s, 18 petites plages) identiques SHA-256 aux fichiers installés ; Global.fr_FR 4 082 247 o en 0,2 s.
- [2026-09-27 11:05] T3.2 : manifest réel lu en lecture seule — hash_type = 4 (BLAKE3) → contrôle réduit aux tailles + magic RW ; Global.fr_FR = 7 chunks / 1 bundle, UI.fr_FR = 17 chunks / 6 bundles.
- [2026-09-27 11:02] T3.1 : zstd 1.5.7 win64 (release officielle sans empreinte publiée) → SHA-256 du zip et de la DLL épinglés par nous ; DLL chargée par chemin absolu après contrôle d'empreinte.
- [2026-09-27 11:02] T3 : téléchargement par plages en PowerShell (mockable) plutôt qu'un ChunkDownloader C# ; seuls zstd et le lecteur RMAN sont en C#.
- [2026-09-27 10:59] T2 : relevé lecture seule — Global (Localized/) + UI (racine FINAL/) remplacés sous le nom de la locale voix ; Common.<locale> des cartes laissé, à vérifier à l'essai.
- [2026-09-27 10:58] T1 : clause « à vos risques / ban » validée en FR, traduite EN/JA ; phrase « ne va sur Internet que… » à revoir en T9 (CDN Riot).
- [2026-09-26] Étude CDN : faisable (manifest local Game.ok/Game.manifest + HTTP Range + libzstd.dll). Replanification directe sans prototype, choix utilisateur : T3 = brique CDN (L), pose/restauration en T4, renumérotation T5–T9.

- [2026-09-26] Option A retenue : étude de faisabilité du téléchargement des seuls fichiers texte (Global/UI.<locale>.wad.client) depuis le CDN Riot — une relance FR par patch (option B) coûterait ~3,8 Go de voix à chaque fois. Plan en attente de l'étude.
- [2026-09-26] Consigne : installation LoL de l'utilisateur en lecture seule pendant le dev ; T2 réduit à de la lecture + essai manuel par l'utilisateur.
- [2026-09-26] Mesure ja_JP : voix Champions 3,4 Go + Maps/Shipping 374 Mo ; texte jeu Localized/Global 3,9 Mo + UI 0,1 Mo ; Plugins client ~41 Mo. Mécanisme inversé validé : locale Riot = voix, copie des 4 Mo de texte forcé. Client LoL reste dans la langue des voix.
- [2026-09-26] Setup : pas de liste « voix » ; une case « Forcer le texte en : [select] » (+ avertissement rouge) appliquée à tous les raccourcis cochés. Langue cochée = voix, select = texte.
- [2026-09-26] Constat : seuls les fichiers de la locale active sont installés (`Game/DATA/FINAL/Champions/<Champion>.<locale>.wad.client`). Aucun réglage Riot pour séparer texte et voix → copie de .wad validée par l'utilisateur.
