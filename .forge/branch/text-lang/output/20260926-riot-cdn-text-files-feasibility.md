# Étude de faisabilité — fichiers texte d'une autre locale depuis le CDN Riot

**Date :** 2026-09-26 · **Branche :** `text-lang` · **Nature :** recherche seule (lecture de code open source, pages web, lecture seule de l'installation locale). Aucune requête vers les serveurs Riot, rien d'installé, rien d'écrit sous `C:\Riot Games` ni `C:\ProgramData\Riot Games`.

**Objectif étudié :** locale Riot = A (voix), obtenir `Game/DATA/FINAL/Localized/Global.<B>.wad.client` (~4 Mo) et `Game/DATA/FINAL/UI.<B>.wad.client` (~0,1 Mo) **pour la version installée exacte**, sans changer la locale Riot, puis les poser à la place des fichiers de A.

---

## 0. Constat décisif fait en lecture seule sur l'installation locale

| Fichier (lecture seule) | Contenu observé | Intérêt |
|---|---|---|
| `C:\Riot Games\League of Legends\Game.ok` (103 o) | `https://lol.secure.dyn.riotcdn.net/channels/public/releases/5F25926EF18E78E7.manifest` / `ja_JP` / `windows` | **URL du manifest de la version installée**, locale active, plateforme |
| `C:\Riot Games\League of Legends\Game.manifest` (16,7 Mo) | En-tête `52 4D 41 4E 02 01 00 02 1C 00 00 00 …` = `RMAN` v2.1, flags `0x0200`, corps à l'offset 28, id `0x5F25926EF18E78E7`, corps zstd (`28 B5 2F FD`) de 16,7 Mo → 26,2 Mo décompressé | **Copie locale du manifest RMAN** de la version installée — même id que dans `Game.ok` |
| `Game/content-metadata.json` | `"version": "16.19.8217343+branch.releases-16-19.content.release"` | Version du jeu lisible sans réseau |
| `ProgramData/.../league_of_legends.live.product_settings.yaml` | `settings.locale: "ja_JP"`, `available_locales` (27 locales) | Une seule locale, pas de réglage texte/voix séparé |
| `Game/DATA/FINAL/Localized/` | seulement `Global.ja_JP.wad.client` (4 079 085 o) ; `UI.ja_JP.wad.client` (139 718 o) | Riot **ne conserve pas** les fichiers texte des autres locales |

**Conséquence :** le manifest RMAN de la version exacte est **déjà sur le disque** (`Game.manifest`), et il décrit les fichiers de **toutes** les locales (chaque fichier porte un masque de langues). Il n'est donc **pas nécessaire** d'interroger `clientconfig` ni `sieve` : il suffit de lire ce manifest localement, puis de télécharger quelques chunks sur `…/channels/public/bundles/`. La version téléchargée est par construction identique à la version installée.

---

## 1. Distribution de LoL par le patcher Riot

### 1.1 Chaîne de découverte (pour mémoire — inutile ici grâce à `Game.manifest`)

| Étape | Endpoint | Usage (d'après CDTB `patcher.py`) |
|---|---|---|
| Patchlines client | `https://clientconfig.rpg.riotgames.com/api/v1/config/public?namespace=keystone.products.league_of_legends.patchlines` | Config publique, sans authentification ; entrée par région (`EUW`, `PBE`…) → `patch_url` |
| Version-sets jeu | `https://sieve.services.riotcdn.net/api/v1/products/lol/version-sets/{EUW1\|PBE1}?q[platform]=windows&q[published]=true` | `releases[-1].download.url` = URL du `.manifest` du jeu |
| Manifest | `https://lol.dyn.riotcdn.net/channels/public/releases/{ID:016X}.manifest` (ou `lol.secure.dyn.riotcdn.net`, cf. `Game.ok`) | Fichier RMAN |
| Bundles | `https://lol.dyn.riotcdn.net/channels/public/bundles/{ID:016X}.bundle` | Concaténation de chunks zstd |

- `clientconfig` / `sieve` donnent la version **live** de la région, qui peut différer de la version **installée** (joueur non patché, patch en cours) : raison de plus pour s'en tenir au manifest local.
- Aucune authentification pour les manifests et bundles publics (CDTB et ManifestDownloader les téléchargent en HTTPS simple).

### 1.2 Connaître la version installée

- `Game.ok` → URL (donc id) du manifest installé : **source la plus précise** (identifie un build exact, pas seulement « 16.19 »).
- `Game.manifest` → même id dans l'en-tête (octets 16–23) ; vérification croisée possible.
- `Game/content-metadata.json` → `version` (CDTB : `get_content_metadata_version`, regex `^(\d+\.\d+)\.`).
- `LeagueClient/system.yaml` → `branch:`/`game-branch:` (CDTB : `get_system_yaml_version`) — version du client, moins utile.
- Version de `League of Legends.exe` (métadonnées PE, CDTB : `get_exe_version`).

---

## 2. Format RMAN

### 2.1 En-tête (little-endian, 28 octets pour v2.1 — vérifié sur le fichier local)

| Offset | Taille | Champ |
|---|---|---|
| 0 | 4 | magic `RMAN` |
| 4 | 1+1 | version major / minor (2.0 ou 2.1 acceptées par CDTB) |
| 6 | 2 | flags (bit 9 attendu par CDTB — `0x0200` local) |
| 8 | 4 | offset du corps (28) |
| 12 | 4 | longueur compressée du corps |
| 16 | 8 | manifest id |
| 24 | 4 | longueur décompressée du corps |
| 28 | … | corps **zstd** (une trame) |

### 2.2 Corps : FlatBuffers (sans schéma publié — lu « à la main »)

Table racine (moonshadow565 `rmanifest.cpp`, CDTB `parse_body`) :

| Index | Table | Champs utiles |
|---|---|---|
| 0 | bundles | `bundle_id` (u64), vecteur de chunks `{chunk_id u64, compressed_size u32, uncompressed_size u32}` |
| 1 | langues | `{id u8, name "fr_FR"}` → bit `id-1` du masque des fichiers |
| 2 | fichiers | [0] file_id, [1] dir_id, [2] size, [3] name, [4] **masque de locales (u64)**, [7] **chunk_ids**, [9] link, [11] index params, [12] permissions |
| 3 | répertoires | `{id, parent_id, name}` → reconstruction du chemin complet |
| 4 | clés | (non utilisées) |
| 5 | params | [1] **hash_type** (1 SHA-512, 2 SHA-256, 3 RITO_HKDF, 4 BLAKE3), [4] taille max d'un chunk |

- Lecteur FlatBuffers générique : offset `u32` relatif → table ; `vtable` = `u16 vtable_size`, `u16 object_size`, puis `u16` par champ (0 = absent). ~60 lignes suffisent (cf. CDTB).
- **Offset d'un chunk dans son bundle** = somme des `compressed_size` des chunks qui le précèdent dans ce bundle (moonshadow565).

### 2.3 Reconstruire un fichier précis

1. Décompresser le corps, indexer répertoires + fichiers, trouver `DATA/FINAL/Localized/Global.fr_FR.wad.client` (le nom porte déjà la locale ; le masque confirme).
2. Parcourir **tous** les bundles pour construire `chunk_id → (bundle_id, offset, compressed_size, uncompressed_size)` (centaines de milliers d'entrées → à faire en C#, pas en boucle PowerShell).
3. Pour chaque chunk du fichier, télécharger `bundles/{bundle_id}.bundle` avec **`Range: bytes=offset-(offset+compressed_size-1)`**, en fusionnant les plages contiguës d'un même bundle. ManifestDownloader procède par `download_ranges()` ; CDTB, lui, télécharge les bundles entiers (plus simple, plus lourd).
4. Décompresser chaque chunk (**zstd**), contrôler la taille décompressée, facultativement le hash (`chunk_id` = 8 premiers octets du hash selon `hash_type`), concaténer dans l'ordre → fichier de `size` octets.

Volume réseau attendu : de l'ordre de 4–5 Mo (le contenu d'un `.wad` est déjà compressé en interne).

---

## 3. Outils open source de référence

| Outil | Langage | Licence | Ce qu'on en retient | Invocable ? |
|---|---|---|---|---|
| [Morilli/ManifestDownloader](https://github.com/Morilli/ManifestDownloader) | C | MIT | Téléchargement par plages (`download_ranges`), filtres `-f/--filter` (regex), `-l/--langs`, `--no-langs`, `-b` (URL bundles), vérif. hash (SHA/BLAKE3) | Binaire Windows publié — **mais ajouter un .exe tiers exclu** par la philosophie du projet et la consigne |
| [CommunityDragon/CDTB](https://github.com/CommunityDragon/CDTB) (`cdtb/patcher.py`, `storage.py`) | Python | voir dépôt (licence libre) | **Référence la plus lisible** : en-tête, FlatBuffers, URLs, versions locales | Non (Python + deps) — s'en inspirer |
| [moonshadow565/rman](https://github.com/moonshadow565/rman) | C++ | MIT | Index exact des champs, calcul des offsets, types de hash (`rchunk.cpp`) | `rman-dl` binaire — même objection |
| [meszmate/rman](https://pkg.go.dev/github.com/meszmate/rman) · [Virace/RiotManifest](https://github.com/Virace/RiotManifest) | Go · Python | voir dépôts | Implémentations alternatives, utiles pour recouper | Non |

**Recommandation :** réimplémentation minimale inspirée de CDTB + rman (MIT/libre, algorithmes non protégés), en C# inline compilé par `Add-Type`. Pas d'invocation d'un exécutable tiers.

---

## 4. Faisabilité PowerShell 5.1 / .NET Framework 4.x

### 4.1 zstd (seul vrai manque de .NET Framework)

| Option | Avantages | Inconvénients | Verdict |
|---|---|---|---|
| **libzstd.dll native officielle** (release facebook/zstd, BSD) + `Add-Type` avec `[DllImport] ZSTD_decompress / ZSTD_getFrameContentSize` | 2 fonctions, ~20 lignes, rapide, aucun conflit d'assembly | Binaire natif à versionner (x64 ; PowerShell 32 bits → autre DLL) ; SmartScreen/antivirus possibles ; hash à épingler | **Préférée** |
| [ZstdSharp.Port](https://www.nuget.org/packages/ZstdSharp.Port) 0.8.8 (MIT, managé, net462/netstandard2.0) | Pur .NET, pas de natif | Tire `System.Memory`, `System.Runtime.CompilerServices.Unsafe`, `System.Threading.Tasks.Extensions` → **conflits de binding** classiques en PS 5.1 (pas de binding redirect possible) ; ~1,5 Mo de DLL | Plan B |
| `zstd.exe` en ligne de commande | Trivial | Exécutable tiers, fichiers temporaires | Écartée |
| Décodeur zstd réécrit en C# | Zéro dépendance | ~1 500+ lignes, FSE/Huffman : XL, risqué | Écartée |

Le projet n'a aujourd'hui **aucune dépendance binaire** : c'est le principal coût « image » (README « Confiance », antivirus).

### 4.2 FlatBuffers à la main
Faisable : lecteur générique ~60–80 lignes C# + extraction des 4 tables utiles ~120 lignes. Le parcours de tous les chunks doit être en C# (`Add-Type` compile via le `csc` du .NET Framework, hors ligne).

### 4.3 HTTP Range
`HttpWebRequest.AddRange(long, long)` disponible en .NET 4 ; forcer TLS 1.2 **dans le process** (`[Net.ServicePointManager]::SecurityProtocol`, pas un réglage système). `Invoke-WebRequest -Headers @{Range=…}` refuse l'en-tête `Range` en 5.1 → passer par `HttpWebRequest`/`WebClient`. Timeout, 2–3 essais, repli « bundle entier » si le serveur renvoie 200 au lieu de 206.

### 4.4 Intégrité
- Contrôle minimal : taille décompressée de chaque chunk + taille totale du fichier + magic WAD `RW`.
- Hash de chunk : SHA-256 / SHA-512 / HKDF faisables avec `System.Security.Cryptography` ; **BLAKE3 absent** de .NET → nécessiterait un port (~300 lignes) ou une DLL. Le `hash_type` réellement utilisé par LoL est **à lire dans le manifest local** (non vérifié ici : pas de zstd disponible sans installation).

### 4.5 Volumétrie et effort

| Unité | Lignes estimées |
|---|---|
| C# `RmanReader` (en-tête, zstd, FlatBuffers, index fichiers/chunks) | 250–350 |
| C# `ChunkDownloader` (plages fusionnées, retry, 206/200) | 100–150 |
| PS `riot-text-files.lib.ps1` (lire `Game.ok`/`Game.manifest`, cache `%LOCALAPPDATA%\hex-launcher\text\<version>\<locale>\`, orchestration, logs) | 150–200 |
| Tests Pester (manifest RMAN synthétique fabriqué en test, serveur HTTP mocké, cas d'erreur) | 250–350 |
| **Total** | **≈ 750–1 050 lignes** |

**Effort : L** (≈ 3–5 j) en plus du plan actuel ; T3 (cache par « lancer une fois la langue B ») est remplacé par cette brique.

---

## 5. Robustesse et risques

| Sujet | Constat | Niveau |
|---|---|---|
| Stabilité du format | RMAN v2 depuis le nouveau patcher (2019) ; v2.1 et BLAKE3 ajoutés depuis ; CDTB n'accepte que 2.0/2.1 → un v2.2/v3 casserait le lecteur | Moyen — échec **propre** (garde sur version) |
| Stabilité des URLs | `channels/public/{releases,bundles}` inchangées depuis 2019 ; hôte lu dans `Game.ok` (pas codé en dur) | Faible |
| Authentification | Aucune pour manifests/bundles publics | Faible |
| Intégrité côté Riot | Les `.wad` portent une **signature ECDSA de la table des entrées + checksum** (cf. ltk_wad, Kurayami) : un fichier **téléchargé à l'identique** reste signé par Riot → pas de fichier « moddé » | Faible pour la signature |
| Chemins internes | Les stringtables sont sous `data/menu/en_us/…` **dans toutes les langues** (« the language is in the name of the game's wad, not in the path inside it ») → renommer `Global.fr_FR` en `Global.ja_JP` est cohérent | Faible (à confirmer en jeu) |
| Polices | Texte CJK avec voix latine (ou inverse) : polices probablement dans le `Global.<locale>` — à tester | Moyen |
| Patcher Riot | `Game.db` suit l'état des fichiers ; au prochain patch ou à une réparation, le fichier remplacé est restauré (écrasé) → il faut **reposer à chaque lancement** (déjà prévu) ; `Game.ok` est réécrit à chaque vérification (25/09 17:29) → risque que le Riot Client re-vérifie et restaure **avant** le lancement du jeu : moment de la copie à valider par l'utilisateur | Moyen |
| Vanguard | Pas de modification mémoire ni d'injection ; fichier signé Riot. Mais Riot n'a jamais validé l'échange de `.wad` ; Vanguard s'est durci fin 2025 contre les outils de mods | Moyen, **non quantifiable** |
| ToS Riot | §7.1 (11) interdit les « unauthorized third party programs, including mods … that interact with the Riot Services » ; §3.1 interdit la copie/redistribution → télécharger pour soi un fichier Riot depuis le CDN Riot est une zone grise, **poser** ce fichier dans le jeu relève du « mod » au sens large | Moyen — avertissement rouge + clause README indispensables |
| Réseau | Première dépendance réseau du lanceur (hors API locale Riot) : hors ligne ou CDN indisponible → lancement normal en langue A | Faible si garde |

---

## 6. Alternatives

| Alternative | Verdict |
|---|---|
| Riot conserve les fichiers d'une locale inactive ? | **Non** : seul `*.ja_JP.wad.client` présent localement ; un changement de locale remplace les fichiers |
| Réglage officiel texte/voix séparés | **Non** pour LoL : `product_settings.yaml` n'a qu'une `locale` ; l'option ajoutée en 2023 change la langue entière, Riot a dit ne pas pouvoir séparer la VO (taille des fichiers) |
| `--locale` du Riot Client / `-Locale` du jeu séparé pour la voix | Non documenté/connu ; le jeu charge `<Champion>.<locale>.wad.client` et `Global.<locale>` avec la même locale → pas d'option voix distincte |
| Cache « lancer une fois en langue B » (plan T3 actuel) | Fonctionne mais coûte **~3,8 Go à chaque patch** (≈ toutes les 2 semaines) et oblige un aller-retour de locale : mauvais UX |
| CommunityDragon | Héberge des fichiers **extraits/convertis** par locale (`raw.communitydragon.org/latest/game/<locale>/…`, `.bin`/`.json`), **pas les `.wad`** ; reconstruire un `.wad` = fichier non signé → vrai mod (cslol), risque accru → **non** |
| Inverse (locale Riot = texte B, copier les voix de A) | Riot télécharge les voix de B (3,8 Go) et copie de 3,8 Go à chaque lancement → **non** |
| Exécutable tiers (ManifestDownloader / rman-dl) | Fonctionnel mais contraire à « aucun .exe tiers », à la confiance README → **non** |

---

## 7. Conclusion et recommandation

**Faisable — recommandation : FAIRE, en variante « manifest local + plages CDN ».**

- **Pourquoi :** `Game.ok` + `Game.manifest` donnent hors ligne la version **exacte** installée et la liste de tous les fichiers de toutes les locales ; seuls ~4–5 Mo de chunks sont à télécharger, sans authentification, sans toucher `clientconfig`/`sieve`, sans changer la locale Riot. Le fichier obtenu est l'original signé par Riot, identique octet pour octet à celui qu'un joueur en locale B possède.
- **Conception :** brique isolée `riot-text-files` (port « source de fichiers texte ») : `Get-InstalledGameRelease` (lit `Game.ok`/`Game.manifest`) → `Find-LocalizedTextFiles` (RMAN) → `Get-ChunksFromCdn` (Range) → cache `%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\`. Le reste du plan (pose/restauration T3, T4–T8) est inchangé ; le cache devient **alimenté par le CDN** au lieu d'exiger un lancement en langue B. Lecture de l'installation strictement en lecture seule ; écriture uniquement au moment de la pose, déjà cadrée.
- **Effort :** **L** (≈ 3–5 j, 750–1 050 lignes dont tests) en remplacement du cache « lancer une fois » de T3.
- **Dépendances à ajouter :** `libzstd.dll` x64 officielle (facebook/zstd, BSD, hash SHA-256 épinglé, source documentée dans `tools/` + README) ; plan B ZstdSharp.Port (MIT) si le natif pose problème. Rien d'autre (FlatBuffers, HTTP, SHA en .NET Framework).
- **Gardes indispensables :** version RMAN ≠ 2.x → abandon propre ; id de `Game.manifest` ≠ id de `Game.ok` → abandon ; taille/`RW`/hash en échec → abandon ; toute erreur → lancement normal en langue A + ligne dans `launch.log`.
- **Risques résiduels :** ToS/Vanguard (non quantifiable → avertissement rouge + clause README), restauration du fichier par le Riot Client avant le démarrage du jeu, polices CJK, `hash_type` BLAKE3 éventuel (vérification réduite à la taille si pas de port). **Préalable court (S, ~½ j) conseillé** : prototype hors lanceur qui lit `Game.manifest` en lecture seule, affiche `hash_type`, les chunks et bundles de `Global.fr_FR` — puis essai réel de la pose **par l'utilisateur**.

### Tableau récapitulatif

| Question | Réponse courte |
|---|---|
| 1. Distribution / version | `Game.ok` = URL du manifest installé ; `Game.manifest` = copie locale ; `content-metadata.json` = version ; clientconfig/sieve inutiles |
| 2. RMAN | En-tête 28 o, corps zstd, FlatBuffers (bundles, langues, fichiers, répertoires, params) ; chunk = plage dans un bundle ; zstd par chunk |
| 3. Outils | CDTB (Python), rman (C++, MIT), ManifestDownloader (C, MIT) : s'en inspirer, ne pas les embarquer |
| 4. PS 5.1 | Faisable avec C# `Add-Type` + libzstd.dll ; Range via `HttpWebRequest` ; effort **L** |
| 5. Robustesse | Format/URLs stables depuis 2019, pas d'auth, fichier signé Riot ; risques ToS/Vanguard, restauration patcher |
| 6. Alternatives | Aucune officielle ; cache « lancer en B » = 3,8 Go/patch ; CDragon sans `.wad` |
| 7. Verdict | **Faire**, variante manifest local + Range, avec prototype lecture seule d'abord |

---

## Sources

- CDTB — `patcher.py` (en-tête RMAN, FlatBuffers, URLs clientconfig/sieve/bundles) : https://github.com/CommunityDragon/CDTB/blob/master/cdtb/patcher.py
- CDTB — `storage.py` (versions : system.yaml, content-metadata.json, exe) : https://github.com/CommunityDragon/CDTB/blob/master/cdtb/storage.py
- moonshadow565/rman (MIT) : https://github.com/moonshadow565/rman — `lib/rlib/rmanifest.cpp` (champs, offsets), `lib/rlib/rchunk.cpp` (types de hash)
- Morilli/ManifestDownloader (MIT, C) : https://github.com/Morilli/ManifestDownloader — `main.c` (options), `download.c` (`download_ranges`)
- Morilli/league-patcher-jsons : https://github.com/Morilli/league-patcher-jsons/blob/master/Riot%20Client%20stuff.txt
- meszmate/rman (Go) : https://pkg.go.dev/github.com/meszmate/rman · Virace/RiotManifest : https://github.com/Virace/RiotManifest
- ZstdSharp.Port (NuGet) : https://www.nuget.org/packages/ZstdSharp.Port
- Chemin interne des stringtables (`data/menu/en_US/…` dans toutes les langues) : https://github.com/Alban1911/Rose/pull/265
- Signature ECDSA / checksum des WAD : https://lib.rs/crates/ltk_wad · https://github.com/MedSalimGh/Kurayami-Launcher/releases/tag/v1.0.0 · https://github.com/LeagueToolkit/wadtools
- CommunityDragon raw (fichiers extraits par locale, pas de .wad) : https://raw.communitydragon.org/latest/game/
- Riot Terms of Service (§3.1, §7.1) : https://www.riotgames.com/en/terms-of-service
- Vanguard / mods : https://wiki.leagueoflegends.com/en-us/Riot_Vanguard · https://github.com/LeagueToolkit/cslol-manager/issues/323 · https://agatasmurf.com/lol-skin-mod/
- Langue LoL (texte seul, VO non séparable) : https://www.oneesports.gg/league-of-legends/select-language-lol-client/
- Lecture seule locale : `C:\Riot Games\League of Legends\Game.ok`, `Game.manifest` (en-tête), `Game\content-metadata.json`, `C:\ProgramData\Riot Games\Metadata\league_of_legends.live\league_of_legends.live.product_settings.yaml`
