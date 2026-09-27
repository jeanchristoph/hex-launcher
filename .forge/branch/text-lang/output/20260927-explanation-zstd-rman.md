# zstd, RMAN, chunks et bundles : fiche de référence

**Date :** 2026-09-27 · **Branche :** text-lang

**Public :** développeur de hex-launcher (lanceur League of Legends en PowerShell 5.1 / .NET Framework 4.x).
**Objectif :** comprendre tout ce qu'il faut pour télécharger depuis le CDN Riot **uniquement** les fichiers texte d'une autre langue :

- `DATA/FINAL/Localized/Global.<locale>.wad.client` (~4 Mo)
- `DATA/FINAL/UI.<locale>.wad.client` (~0,1 Mo)

Cette fiche complète l'étude de faisabilité `20260926-riot-cdn-text-files-feasibility.md`, dont elle reprend les conclusions.

---

## 1. zstd (Zstandard)

### 1.1 Origine

- Algorithme de compression sans perte créé par **Yann Collet** chez **Facebook (aujourd'hui Meta)**, version 1.0 publiée en **2016**.
- Implémentation de référence en C : https://github.com/facebook/zstd, sous **double licence BSD / GPLv2** (on retient la BSD, permissive).
- Format normalisé par la **RFC 8878** (« Zstandard Compression and the application/zstd Media Type », 2021).

### 1.2 Principe

zstd combine deux étages classiques :

1. **LZ77 (références arrière)** : au lieu de réécrire une suite d'octets déjà vue, le compresseur émet une *séquence* « copie `N` octets situés `D` octets plus tôt ». Les octets qui ne se répètent pas sont émis tels quels (*literals*).
   Exemple : `abcdefabcdef` → literals `abcdef` + « copie 6 octets à distance 6 ».
2. **Codage entropique** : les symboles fréquents reçoivent des codes courts.
   - les **literals** sont codés en **Huffman** ;
   - les trois flux de nombres des séquences (longueur des literals, longueur de copie, distance) sont codés en **FSE** (*Finite State Entropy*, variante des systèmes numériques asymétriques tANS), plus rapide à décoder qu'un codeur arithmétique pour une compression comparable.

Le décompresseur n'a qu'à décoder ces tables puis recopier des octets : c'est ce qui le rend très rapide.

### 1.3 Structure d'une trame (*frame*)

Un flux zstd est une suite de **trames** indépendantes. Une trame :

| Élément | Taille | Contenu |
|---|---|---|
| Magic number | 4 o | `0xFD2FB528`, soit les octets **`28 B5 2F FD`** sur le disque (little-endian) |
| En-tête de trame | 2 à 14 o | Descripteur (1 o : drapeaux) ; fenêtre (facultative) ; id de dictionnaire (facultatif) ; **taille du contenu décompressé (facultative, 0 à 8 o)** |
| Blocs | variable | Chaque bloc a un en-tête de 3 o : bit « dernier bloc », type sur 2 bits, taille sur 21 bits |
| Checksum | 0 ou 4 o | Facultatif : 32 bits bas du xxHash64 du contenu |

Les trois types de blocs utiles :

- **Raw** : octets stockés sans compression (données incompressibles) ;
- **RLE** : un seul octet répété `N` fois ;
- **Compressed** : section literals (Huffman) + section séquences (FSE).

Le quatrième type (3) est réservé : sa présence signale une donnée corrompue.

**Point pratique :** la taille décompressée est *facultative* dans l'en-tête. Riot la fournit aussi à part (en-tête RMAN, `uncompressed_size` de chaque chunk) : on s'appuie sur ces valeurs pour allouer le tampon de sortie, et on les recoupe avec `ZSTD_getFrameContentSize` quand elle est connue.

### 1.4 Pourquoi Riot l'utilise

- **Décompression très rapide** (de l'ordre du Go/s par cœur), quel que soit le niveau de compression choisi à l'encodage : le patcher peut compresser fort une fois côté serveur et décompresser vite chez des millions de joueurs.
- Bon taux de compression, proche de zlib niveau max ou mieux.
- Chaque chunk est **une trame indépendante** : on peut décompresser n'importe quel morceau isolément, ce qui rend possible le téléchargement partiel (§3).

### 1.5 Pourquoi .NET Framework 4.x ne l'a pas

- PowerShell 5.1 tourne sur **.NET Framework 4.x**, figé depuis la 4.8 (2019) : Microsoft n'y ajoute plus de fonctionnalités.
- `System.IO.Compression` n'y propose que **Deflate / GZip** (et ZIP). Brotli n'est arrivé qu'avec .NET Core 2.1, ZLib avec .NET 6 ; **aucune version de .NET Framework ne décode zstd**.

### 1.6 Solution retenue : `libzstd.dll` par P/Invoke

- **Binaire :** `libzstd.dll` **officielle x64, v1.5.7**, issue des releases GitHub de facebook/zstd (licence BSD). Source et procédure documentées dans `tools/` et le README.
- **Intégrité :** son **empreinte SHA-256 est épinglée** dans le code ; le lanceur calcule le SHA-256 du fichier et **refuse de le charger** en cas d'écart (DLL remplacée ou corrompue → abandon propre, lancement normal).
- **Architecture :** DLL x64 → PowerShell 64 bits obligatoire (une session 32 bits ne pourrait pas la charger).

#### Qu'est-ce que P/Invoke ?

*Platform Invocation* : mécanisme .NET qui permet à du code managé (C#) d'appeler une fonction exportée par une DLL native (C). On déclare la signature C en C# avec l'attribut `[DllImport]` ; au premier appel, le runtime charge la DLL (`LoadLibrary`), trouve la fonction par son nom et **convertit (« marshal »)** les arguments : tableaux `byte[]` épinglés et passés comme pointeurs, `size_t` représenté par `UIntPtr`, `const char*` renvoyé comme `IntPtr` puis converti en chaîne. En PowerShell 5.1, ce C# est compilé à la volée par `Add-Type`.

#### Les quatre fonctions utilisées

| Fonction C | Rôle |
|---|---|
| `size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t srcSize)` | Décompresse une trame complète ; renvoie le nombre d'octets écrits **ou** un code d'erreur |
| `unsigned long long ZSTD_getFrameContentSize(const void* src, size_t srcSize)` | Lit la taille décompressée dans l'en-tête ; valeurs spéciales `ZSTD_CONTENTSIZE_UNKNOWN` (2⁶⁴−1) et `ZSTD_CONTENTSIZE_ERROR` (2⁶⁴−2) |
| `unsigned ZSTD_isError(size_t code)` | Indique si une valeur de retour est un code d'erreur |
| `const char* ZSTD_getErrorName(size_t code)` | Message lisible de l'erreur, pour `launch.log` |

Esquisse de déclaration (convention d'appel `Cdecl`) :

```csharp
[DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
static extern UIntPtr ZSTD_decompress(byte[] dst, UIntPtr dstCapacity, byte[] src, UIntPtr srcSize);

[DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
static extern ulong ZSTD_getFrameContentSize(byte[] src, UIntPtr srcSize);

[DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
static extern uint ZSTD_isError(UIntPtr code);

[DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
static extern IntPtr ZSTD_getErrorName(UIntPtr code); // Marshal.PtrToStringAnsi
```

Règle : **toujours** passer le résultat de `ZSTD_decompress` à `ZSTD_isError`, puis vérifier que la taille obtenue est exactement la taille attendue.

---

## 2. RMAN : le manifest du patcher Riot

Un manifest RMAN décrit **une version exacte** du jeu : la liste de tous les fichiers de toutes les langues, et, pour chacun, les chunks qui le composent et le bundle où trouver chaque chunk.

### 2.1 En-tête (28 octets, little-endian)

| Offset | Taille | Champ | Valeur attendue |
|---|---|---|---|
| 0 | 4 | magic | `RMAN` (`52 4D 41 4E`) |
| 4 | 1 | version majeure | 2 |
| 5 | 1 | version mineure | 1 (2.0 accepté aussi par CDTB) |
| 6 | 2 | flags | `0x0200` (bit 9) |
| 8 | 4 | offset du corps | 28 |
| 12 | 4 | longueur compressée du corps | — |
| 16 | 8 | **id du manifest** (u64) | identique à l'id de l'URL dans `Game.ok` |
| 24 | 4 | longueur décompressée du corps | — |

Garde : version majeure ≠ 2 → abandon propre (format inconnu).

### 2.2 Corps

Le corps (à l'offset 28) est **une trame zstd** ; une fois décompressé, c'est un buffer **FlatBuffers**.

### 2.3 FlatBuffers en bref

FlatBuffers (Google, 2014) est un format de sérialisation binaire **lisible sans désérialisation** : on navigue directement dans le buffer avec des décalages. Riot ne publie pas le schéma : on lit le buffer « à la main » avec les index de champs établis par CDTB et moonshadow565.

Notions (toutes en little-endian) :

- **uoffset** (u32, non signé) : décalage **vers l'avant**, relatif à la position où il est lu. Le buffer commence par un uoffset qui mène à la **table racine**.
- **table** : objet à champs facultatifs. Ses 4 premiers octets sont un **soffset** (i32, signé) : la **vtable** se trouve à `position_table − soffset`.
- **vtable** : suite de u16 :
  1. taille de la vtable en octets ;
  2. taille de l'objet (partie inline de la table) ;
  3. puis **un décalage u16 par champ**, relatif au début de la table.
  Un décalage **0** (ou un index au-delà de la fin de la vtable) signifie **champ absent → valeur par défaut** (en général 0).
- Champ scalaire : lu directement à `table + décalage`.
- Champ référence (chaîne, vecteur, sous-table) : à `table + décalage` se trouve un **uoffset** vers l'objet.
- **Vecteur** : **longueur u32**, puis les éléments. Pour un vecteur de tables, chaque élément est un uoffset (relatif à sa propre position).
- **Chaîne** : longueur u32, octets UTF-8, puis un octet nul.

Lecture d'un champ, en résumé :

```text
vtable   = table - i32(table)
nbChamps = (u16(vtable) - 4) / 2
si index >= nbChamps ou u16(vtable + 4 + 2*index) == 0 → valeur par défaut
sinon position = table + u16(vtable + 4 + 2*index)
```

### 2.4 Les 6 vecteurs de la table racine

| Index | Contenu | Champs (index de vtable → sens) |
|---|---|---|
| 0 | **bundles** | 0 `bundle_id` (u64) ; 1 vecteur de chunks `{0 chunk_id u64, 1 compressed_size u32, 2 uncompressed_size u32}` |
| 1 | **langues** | 0 `id` (u8) ; 1 `name` (ex. `fr_FR`) |
| 2 | **fichiers** | 0 `file_id` ; 1 `directory_id` ; 2 `size` (u32) ; 3 `name` ; 4 **masque de locales** (u64) ; 7 **`chunk_ids`** (vecteur de u64) ; 9 `link` |
| 3 | **répertoires** | 0 `id` ; 1 `parent_id` ; 2 `name` |
| 4 | clés | non utilisées ici |
| 5 | **params** | 1 **`hash_type`** : 1 SHA-512, 2 SHA-256, 3 RITO_HKDF, 4 BLAKE3 |

Règles à retenir :

- **Masque de locales :** le bit `id − 1` du masque d'un fichier est à 1 si ce fichier appartient à la langue d'identifiant `id` (table 1). Un masque nul = fichier commun à toutes les langues. Le nom `Global.fr_FR.wad.client` porte déjà la locale ; le masque sert de confirmation.
- **Chemin complet :** remonter `directory_id → parent_id` jusqu'à la racine en concaténant les `name`.
- **Offset d'un chunk dans son bundle** = **somme des `compressed_size` des chunks qui le précèdent dans ce même bundle**. Le manifest ne stocke pas cet offset : on le calcule en parcourant le vecteur de chunks du bundle.
- **Hash :** l'id d'un chunk correspond aux 8 premiers octets du hash (selon `hash_type`) de son contenu **décompressé**. SHA-256 et SHA-512 sont disponibles en .NET Framework ; BLAKE3 ne l'est pas.

---

## 3. Chunks et bundles

### 3.1 Pourquoi ce découpage

- Un **chunk** est un morceau de fichier (quelques dizaines à centaines de Ko), identifié par un id dérivé du hash de son contenu.
- Deux fichiers, ou deux versions d'un même fichier, qui partagent un morceau identique partagent **le même chunk** : c'est la **déduplication**. D'un patch à l'autre, le patcher ne télécharge que les chunks nouveaux.
- Des milliers de petits fichiers seraient coûteux à servir : les chunks sont regroupés dans des **bundles**, simples concaténations de chunks compressés (chaque chunk = une trame zstd indépendante).

### 3.2 URLs

| Ressource | URL |
|---|---|
| Manifest | `https://lol.secure.dyn.riotcdn.net/channels/public/releases/<ID>.manifest` |
| Bundle | `https://lol.secure.dyn.riotcdn.net/channels/public/bundles/<ID16HEX>.bundle` |

- `<ID>` : id du manifest, tel qu'il figure dans `Game.ok`.
- `<ID16HEX>` : `bundle_id` écrit en **16 chiffres hexadécimaux majuscules**, complété par des zéros à gauche (format `{0:X16}`).
- Aucune authentification. L'hôte est lu dans `Game.ok`, pas codé en dur.

### 3.3 Requêtes HTTP `Range`

Plutôt que de télécharger un bundle entier, on demande seulement les octets du chunk :

```http
GET /channels/public/bundles/0123456789ABCDEF.bundle HTTP/1.1
Range: bytes=<offset>-<offset + compressed_size - 1>
```

- Réponse attendue : **`206 Partial Content`** avec exactement les octets demandés.
- Si le serveur **ignore le Range** et répond **`200 OK`** avec le bundle complet : **repli** en découpant soi-même la plage `[offset, offset + compressed_size)` dans le corps reçu.
- Les plages contiguës d'un même bundle peuvent être fusionnées en une seule requête.
- En PowerShell 5.1, `Invoke-WebRequest` refuse l'en-tête `Range` : utiliser `HttpWebRequest.AddRange(long, long)`, avec TLS 1.2 forcé **dans le process** uniquement.

---

## 4. Le pipeline appliqué à hex-launcher

```text
C:\Riot Games\League of Legends\Game.ok            (lecture seule)
   │  URL du manifest installé  → id du manifest
   │  locale installée (ex. ja_JP)
   ▼
C:\Riot Games\League of Legends\Game.manifest      (lecture seule, copie locale du manifest)
   │
   ├─ en-tête RMAN (28 o) : magic, version 2.x, id == id de Game.ok ?
   ▼
corps zstd ──► libzstd.dll (SHA-256 vérifié) ──► buffer FlatBuffers
   │
   ├─ répertoires + fichiers → chemin complet
   ├─ fichier recherché : DATA/FINAL/Localized/Global.<B>.wad.client
   │                      DATA/FINAL/UI.<B>.wad.client
   ├─ chunk_ids du fichier (ordre = ordre du fichier)
   └─ bundles → chunk_id → (bundle_id, offset, compressed_size, uncompressed_size)
   ▼
plages HTTP Range sur .../bundles/<ID16HEX>.bundle   (206, repli 200)
   ▼
zstd par chunk → contrôle taille décompressée → concaténation
   ▼
contrôles du fichier : taille totale == size, magic WAD « RW », hash des chunks si hash_type le permet
   ▼
%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\Global.<B>.wad.client
                                                      \UI.<B>.wad.client
```

- **Volume :** environ **4 Mo** téléchargés, contre **~3,8 Go** de voix si l'on faisait basculer toute la locale Riot vers B.
- **Cache par `manifestId` :** un patch change l'id → nouveau dossier ; tant que l'id ne change pas, aucun réseau n'est nécessaire.
- **Installation Riot en lecture seule :** `Game.ok` et `Game.manifest` sont seulement lus ; seul le cache sous `%LOCALAPPDATA%` est écrit par cette brique.
- **Toute erreur** (réseau, version RMAN, id divergent, taille, `RW`, hash) → abandon propre, ligne dans `launch.log`, lancement normal dans la langue installée.

### Pourquoi le fichier reste l'original signé par Riot

- On ne fabrique rien : on **réassemble dans l'ordre** les octets exacts publiés par Riot sur son CDN, pour la version exacte installée.
- Le résultat est **identique octet pour octet** au fichier que possède un joueur dont la locale est B.
- Les `.wad` portent une **signature ECDSA de leur table d'entrées** et des checksums : un fichier réassemblé à l'identique conserve la signature Riot valide, contrairement à un `.wad` reconstruit ou modifié (mod).
- Les contrôles (taille, `RW`, hash) garantissent qu'aucun octet n'a été altéré en route.

---

## 5. Glossaire

| Terme | Définition |
|---|---|
| **Chunk** | Morceau de fichier, compressé en une trame zstd, identifié par un id dérivé du hash de son contenu ; unité de déduplication |
| **Bundle** | Fichier du CDN qui concatène des chunks compressés ; on y lit un chunk par son offset et sa taille compressée |
| **Manifest** | Fichier RMAN décrivant une version : fichiers, langues, répertoires, chunks, bundles |
| **Trame** (*frame*) | Unité autonome d'un flux zstd : magic, en-tête, blocs, checksum facultatif |
| **vtable** | Table FlatBuffers de décalages u16 indiquant où se trouve chaque champ d'une table (0 = absent) |
| **uoffset** | Décalage u32 FlatBuffers, relatif à sa propre position, vers une table, un vecteur ou une chaîne |
| **P/Invoke** | Mécanisme .NET d'appel d'une fonction d'une DLL native depuis du code managé (`[DllImport]`) |
| **HTTP Range** | En-tête demandant une plage d'octets d'une ressource ; réponse `206 Partial Content` si le serveur l'honore |

---

## Sources

- zstd, implémentation de référence : https://github.com/facebook/zstd
- RFC 8878, format Zstandard : https://www.rfc-editor.org/rfc/rfc8878
- Documentation FlatBuffers (format interne) : https://flatbuffers.dev/internals/
- CDTB `cdtb/patcher.py` (en-tête RMAN, lecture FlatBuffers, URLs) : https://github.com/CommunityDragon/CDTB
- moonshadow565/rman (index des champs, offsets de chunks, types de hash) : https://github.com/moonshadow565/rman
- Étude de faisabilité du projet : `.forge/branch/text-lang/output/20260926-riot-cdn-text-files-feasibility.md`
