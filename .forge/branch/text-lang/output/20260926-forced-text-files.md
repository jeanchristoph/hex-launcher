# Relevé — fichiers texte du mode « texte forcé »

**Date :** 2026-09-27 · **Branche :** `text-lang` · **Nature :** lecture seule de l'installation locale (listes, tailles, `Game.ok`). Rien n'a été copié, écrit, lancé ni changé de langue.
**Complète :** `20260926-riot-cdn-text-files-feasibility.md`.

**Installation relevée :** `C:\Riot Games\League of Legends\` · locale `ja_JP` · manifest `5F25926EF18E78E7` (`Game.ok`) · version `16.19.8217343`.

---

## 1. Fichiers localisés présents (locale active seulement)

Dossier racine : `Game/DATA/FINAL/`. Seuls les fichiers de la locale active sont installés.

| Chemin sous `Game/DATA/FINAL/` | Taille | Rôle | Mode texte forcé |
|---|---|---|---|
| `Localized/Global.<locale>.wad.client` | 4 079 085 o | Chaînes de texte du jeu (stringtables, polices localisées) | **Remplacé** |
| `UI.<locale>.wad.client` (**à la racine de `FINAL/`**, pas sous `Localized/`) | 139 718 o | Textures d'interface localisées | **Remplacé** |
| `Champions/<Champion>.<locale>.wad.client` × 174 | 3 567 002 893 o au total | Voix des champions | Conservé (langue des voix) |
| `Maps/Shipping/Map{11,12,22,30,453}.<locale>.wad.client` | 6,9 à 160,8 Mo chacun | Voix d'annonceur et sons des cartes | Conservé |
| `Maps/Shipping/Common.<locale>.wad.client` | 938 170 o | Ressources localisées communes aux cartes (voix, sons) | Conservé — voir § 4 |

`UI.wad.client` (444 Mo, sans locale) est commun à toutes les langues : il n'est pas concerné.

## 2. Chemins recherchés dans le manifest RMAN

Le manifest décrit les chemins relatifs à la racine `Game/` du produit :

- `DATA/FINAL/Localized/Global.<B>.wad.client`
- `DATA/FINAL/UI.<B>.wad.client`

`<B>` est la locale du texte forcé, écrite comme Riot l'écrit (`fr_FR`, `ja_JP`, `ko_KR`, `zh_TW`…, 27 locales dans `available_locales`). Le masque de langues du fichier confirme la locale. Pour une locale donnée, la recherche doit rendre exactement 2 fichiers. Sinon → abandon et lancement normal.

## 3. Mécanisme retenu

1. La locale Riot reste **A** (voix) : pose par l'API locale, comme aujourd'hui.
2. Les deux fichiers texte de **B** sont obtenus depuis le CDN Riot pour l'id de manifest installé (T3) et mis en cache dans `%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<B>\`.
3. Pose (T4) : les deux fichiers de A sont sauvegardés, puis les fichiers de B sont copiés **sous le nom de A** :
   - `Localized/Global.<B>.wad.client` → `Localized/Global.<A>.wad.client`
   - `UI.<B>.wad.client` → `UI.<A>.wad.client`
   
   Le renommage est cohérent parce que, dans toutes les langues, les chemins internes des stringtables restent `data/menu/en_us/…`. La langue est portée par le nom du `.wad`, pas par les chemins internes (source dans l'étude CDN).
4. La pose est refaite à chaque lancement mixte, car un patch ou une réparation Riot restaure les fichiers de A. Au lancement normal, la restauration s'appuie sur la sauvegarde et le marqueur `forced-text-state.json`.
5. Volume : ~4,2 Mo par locale forcée et par patch.

## 4. Points ouverts — essai réel de l'utilisateur

- **`Maps/Shipping/Common.<locale>.wad.client`** (0,9 Mo) : contenu non vérifié (fichier non ouvert). S'il contient du texte affiché en jeu (et pas seulement des voix ou des sons), il faudra l'ajouter à la liste. Critère : après un premier essai réel, repérer des textes restés dans la langue des voix.
- Polices CJK : texte japonais, coréen ou chinois avec voix latine, et l'inverse.
- Restauration éventuelle par le Riot Client entre la pose et le démarrage du jeu.
- `hash_type` du manifest : à lire en T3.2, dès que la décompression zstd est disponible.
