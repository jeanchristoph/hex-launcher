# Hex Launcher — plan de diffusion
**Date :** 2026-09-21 · **Objectif :** faire connaître le projet et aider le plus d'utilisateurs possible, sans budget, sans spam, sans exposer le projet ni son auteur inutilement.

---

## 0. Le constat qui commande tout le plan

Hex Launcher résout un besoin **précis, ancien et très recherché** : jouer à League of Legends avec les voix et textes d'une autre langue (japonais, coréen…) sur son serveur habituel. Les recherches « lol japanese voice », « league changer langue client », « voix japonaises lol 2026 » reviennent chaque saison, les tutoriels vidéo comptent des millions de vues, et chaque évolution du Riot Client casse la méthode manuelle (édition du `.yaml`, ancien `--locale`).

Conséquence : **le canal principal n'est pas le réseau social, c'est la recherche.** Un joueur qui a le problème le tape dans Google ou YouTube ; il faut être la réponse qu'il trouve. Les réseaux servent à amorcer (premiers utilisateurs, premiers retours, premières étoiles), pas à durer.

Second constat : le premier frein n'est pas la notoriété, c'est **la confiance**. Un `.bat` non signé, un lanceur qui touche au client Riot, Vanguard en toile de fond : chaque utilisateur potentiel se demande « est-ce que je vais me faire bannir / infecter ». La section *Confiance* du README est un bon début ; elle doit devenir visible avant même le téléchargement.

---

## 1. Avant toute diffusion — mettre la maison en ordre (semaine 1)

Rien ne sert de faire venir des gens sur une page qui ne convainc pas en 20 secondes.

| # | Action | Pourquoi |
|---|---|---|
| 1.1 | **GIF ou vidéo de 20 s en tête du README** : double-clic sur le raccourci → splash → jeu en japonais. | Montre le résultat avant l'explication. C'est ce que tout le monde regarde en premier. |
| 1.2 | **Une phrase d'accroche en H1/H2** orientée besoin : « Jouez à LoL en japonais (ou 26 autres langues) depuis un raccourci — sans toucher aux fichiers du jeu ». | Le README actuel commence par ce que fait l'outil ; il doit commencer par le problème du joueur. |
| 1.3 | **FAQ courte et honnête** (README + page dédiée) : *Vanguard ?* (l'outil ne touche pas au jeu ; VAN 216 possible si on relance > 3× en 5 min, l'outil prévient) · *Riot autorise ?* (non affilié, API locale du client, aucun avantage en jeu) · *SmartScreen ?* (scripts en clair, non signés, SHA-256 publié) · *Mac ?* (non). | Ce sont les quatre questions que poseront tous les fils Reddit. Y répondre d'avance évite les débats et fait gagner la confiance. |
| 1.4 | **Lien VirusTotal du zip** dans chaque release, à côté du SHA-256 (peut s'automatiser dans `make-release`). | Argument concret contre « c'est un virus ». |
| 1.5 | **Dépôt GitHub soigné** : description en une ligne, *topics* (`league-of-legends`, `riot-client`, `japanese-voice`, `locale`, `launcher`, `powershell`, `windows`), image *social preview*, Discussions activées, *issue templates* (bug avec `app\launch.log` à joindre, demande de langue/compagnon). | Les topics font remonter le dépôt dans la recherche GitHub ; les templates rendent le support tenable. |
| 1.6 | **Décider la posture de support** : Issues GitHub = canal unique. Pas de Discord dédié tant qu'il n'y a pas 100 utilisateurs actifs. | Un Discord vide fait plus de mal qu'un dépôt calme. |

Point d'attention — trois langues du README (FR/EN/JA) : le public qui a *besoin* de l'outil est occidental (voix JP/KR sur EUW/NA/BR/LAN). Le README japonais sert peu à la diffusion ; ne pas y investir davantage. L'espagnol et le portugais brésilien, en revanche, correspondent à deux très grosses communautés LoL demandeuses de voix JP — à traduire quand le texte EN sera stabilisé.

---

## 2. Où sont les utilisateurs — canaux par ordre de rendement

### A. Recherche (évergreen — le canal qui porte sur la durée)

1. **Page d'atterrissage GitHub Pages**, une page, trois langues, dont le titre est la question exacte du joueur (« How to play League of Legends with Japanese voices on any server »). Un dépôt GitHub seul se référence mal ; une page dédiée avec le bon titre se place en quelques semaines sur une requête aussi ciblée.
2. **Vidéo YouTube de 60–90 s** (sans voix, sous-titres FR/EN) : le problème, le double-clic, le résultat. Titre = la requête. Description = lien release + SHA-256. C'est là que sont les millions de vues des tutoriels manuels ; un tutoriel qui tient en un raccourci se partage.
3. **Répondre dans les fils existants** (Reddit, forums, commentaires YouTube des tutos manuels périmés) quand quelqu'un demande comment changer de langue : réponse utile d'abord, lien ensuite. Une réponse par fil, jamais de copier-coller — ces fils sont ceux que Google renvoie, y figurer c'est être trouvé.

### B. Reddit (amorçage — semaines 2 à 4)

- **r/leagueoflegends** : un seul post « I made a free open-source tool… », avec le GIF, la FAQ Vanguard dans le corps du post, en respectant la règle d'auto-promotion du sub (poster comme membre, répondre à tout le monde pendant 24 h). Meilleur créneau : début de semaine, matin US.
- **r/LearnJapanese** et communautés d'apprenants (WaniKani, Discord d'immersion) : angle différent — « jouer en japonais pour progresser ». Public motivé, peu adressé, très partageur.
- Sous-communautés par langue : sub FR de LoL, r/LeagueOfLegendsBR, r/LoLEspañol quand les traductions existent.

### C. Discord et créateurs (levier gratuit, effet de réseau)

- **Streamers qui jouent déjà avec les voix japonaises** (nombreux en FR et EN) : un message direct court, sans rien demander d'autre que d'essayer. Un seul qui le mentionne en stream vaut cent posts.
- Discords communautaires LoL FR (les gros serveurs ont un salon outils/astuces) : demander la permission à un modérateur avant de poster.

### D. LinkedIn (image, pas acquisition)

Un post technique unique : la méthode (700 tests Pester sur PowerShell 5.1, machine à états testée sans UI, WinHTTP, journal qui a révélé les 424, développement avec `claude_forge`), lien GitHub en commentaire, phrase de non-affiliation. Pas d'appel au téléchargement. Voir échange du 2026-09-21.

### E. À éviter

Publicité payante · publication du même texte sur dix subs · Product Hunt (mauvais public) · toute formulation laissant croire à un soutien de Riot · icône officielle (règle du projet) · Discord dédié prématuré.

---

## 3. Mode opératoire — comment faire la promotion, concrètement

Principe : **une action à la fois, chacune avec son texte prêt, son créneau et son suivi.** Rien n'est posté sans son kit.

### 3.1 Le kit de base (à préparer une fois, dans OUTPUT — FR validé, puis EN)

| Pièce | Contenu | Usage |
|---|---|---|
| Pitch 1 phrase | « Un raccourci sur le Bureau, LoL démarre en japonais — ou dans 26 autres langues. Rien à éditer, le jeu n'est pas modifié. » | Titre de post, message direct, bio |
| Pitch 3 phrases | Le problème (voix JP impossibles sur EUW sans bidouille qui casse à chaque patch) · la solution (assistant + raccourcis) · la garantie (open source, jamais admin, aucune donnée) | Corps de post, description vidéo |
| Bloc confiance | 4 lignes à coller sous **chaque** post : non affilié à Riot · le jeu n'est pas modifié (API locale du Riot Client) · code PowerShell en clair, SHA-256 + VirusTotal · Windows seulement | Coupe court aux « c'est un virus / un cheat » |
| 4 réponses prêtes | Vanguard · Riot autorise ? · SmartScreen · Mac | À coller en commentaire, sans réécrire à chaque fois |
| Visuels | GIF 20 s (T1), capture de l'assistant, capture du splash, capture du client en japonais | Tout post sans image est ignoré |
| Liens | Release latest · README (section Confiance) · page d'atterrissage (T5) | Toujours les trois mêmes |

### 3.2 Reddit — pas à pas

1. **Compte** : le tien, avec historique. Jamais un compte neuf — les filtres anti-spam le bloquent.
2. **48 h avant** : lire les règles du sub (auto-promotion, flairs), puis modmail : « I built a free open-source tool for X, is a post with flair Y acceptable? ». Une réponse positive protège le post.
3. **Titre** = résultat pour le joueur, jamais le nom de l'outil :
   « I made a free open-source tool to play League with Japanese (or any) voices on any server — one desktop shortcut, nothing modified ».
4. **Corps** : GIF en premier · pitch 3 phrases · « Windows only » · bloc confiance · lien GitHub · « feedback and language requests welcome ».
5. **Créneau** : mardi à jeudi, 14 h–16 h Paris (matin côte Est US).
6. **Les 24 h suivantes** : répondre à *tous* les commentaires. Sceptique → réponse prête + lien Confiance, ton calme, jamais plus de deux échanges. Chaque question posée deux fois entre dans la FAQ.
7. **Cadence** : un sub par semaine, dans l'ordre : r/leagueoflegends (EN) → sub FR de LoL → r/LearnJapanese (angle immersion, vérifier que les outils y sont acceptés) → subs BR / ES quand les README existent (T6).
8. **En parallèle, chaque semaine** : chercher sur Reddit les fils des 12 derniers mois « japanese voice league », « lol voix japonaises » ; répondre dans 2 ou 3 fils avec les étapes manuelles *et* le lien — réponse utile d'abord. C'est ce qui remonte dans Google.

### 3.3 YouTube — la vidéo de 60–90 s

- **Outil** : OBS (gratuit), 1080p, sous-titres incrustés, pas de voix nécessaire.
- **Script** : 0–5 s le problème en texte (« Voix japonaises sur EUW ? ») · 5–15 s télécharger, dézipper, `setup.bat` · 15–40 s l'assistant, trois étapes · 40–55 s double-clic sur le raccourci, splash, client en japonais · 55–70 s trois lignes de confiance · carte de fin : lien.
- **Titre** = la requête : « How to play League of Legends with Japanese voices on any server (2026 — one shortcut) » ; version FR séparée.
- **Description** : étapes en texte, lien release, SHA-256, VirusTotal, non-affiliation, horodatages.
- **Miniature** : client en japonais + gros texte « JP voices, 1 click ».
- **Short 30 s** dérivé de la même prise.
- Commenter sous les tutoriels manuels périmés : un seul commentaire poli, seulement si le tuto ne marche plus.

### 3.4 Streamers et créateurs

1. **Trouver** 5 streamers FR ou EN qui jouent déjà avec les voix japonaises (clips Twitch, recherche « voix japonaises » sur X/Twitter).
2. **Message direct, 4 lignes** : qui tu es · ce que fait l'outil (pitch 1 phrase) · pourquoi pour eux (ils ont déjà les voix JP ; retour au FR en un autre raccourci ; leurs viewers demandent souvent comment faire) · lien. Aucune demande, aucune relance au-delà d'une.
3. Si l'un d'eux le montre : le remercier publiquement, ajouter son extrait à la page d'atterrissage avec son accord.

### 3.5 Discord

- **Serveurs communautaires LoL FR** (annuaires Disboard / discord.me, « league of legends fr ») : rejoindre, lire les règles, demander en privé à un modérateur si un salon outils/astuces accepte le post. Poster une fois : 3 lignes + GIF + lien. Rester pour répondre.
- **Serveurs d'apprenants en japonais** (immersion) : même méthode, angle apprentissage.

### 3.6 LinkedIn — un seul post, semaine 3

Le récit technique (méthode, tests, WinHTTP, journal, `claude_forge`), lien GitHub en premier commentaire, phrase de non-affiliation, deux hashtags maximum. Pas de « téléchargez ».

### 3.7 La routine hebdomadaire (30 min, même jour chaque semaine)

1. *Insights → Traffic* du dépôt : sources, pages vues, clones.
2. Issues et Discussions : répondre, étiqueter, noter les questions récurrentes → FAQ.
3. Deux ou trois réponses dans des fils existants (3.2 étape 8).
4. Après chaque patch Riot : tester un lancement, publier « tested with patch X » en Discussion et sous la dernière release.

### 3.8 Quand ça ne prend pas

Trois posts sans retour (aucune issue, moins de 20 téléchargements) → **revoir le message, pas le canal** : le problème est le pitch ou la confiance. Relire les commentaires reçus, ils disent lequel.

### 3.9 Livrables à produire quand tu le décides (OUTPUT, FR validé → EN)

- Post Reddit (titre + corps + bloc confiance + 4 réponses).
- Script de la vidéo, plan par plan.
- Message aux streamers.
- Post LinkedIn.
- Message Discord.

---

## 4. Le message — une phrase par public

| Public | Phrase |
|---|---|
| Joueur qui veut les voix JP | « Un raccourci sur le Bureau, LoL démarre en japonais. Rien à éditer, rien à réinstaller, le jeu n'est pas modifié. » |
| Apprenant en japonais | « Transformez vos parties en immersion : textes et voix en japonais, retour au français en un autre raccourci. » |
| Utilisateur d'appli compagnon | « Chaque raccourci lance aussi Blitz, Porofessor, OP.GG ou Mobalytics — et ferme les autres pour éviter les conflits d'overlay. » |
| Sceptique sécurité | « Open source, PowerShell en clair, jamais administrateur, aucune donnée collectée, SHA-256 et VirusTotal publiés. » |
| Réseau pro | « Ce que j'ai appris en automatisant un client desktop verrouillé, avec un agent IA cadré par un processus. » |

Règle d'écriture : **le problème avant l'outil, le vocabulaire du joueur avant le vocabulaire technique** (leçon T29 : « proposer court, une phrase, vocabulaire du joueur »).

---

## 5. Aider les utilisateurs — ce qui fait qu'ils restent et recommandent

- **Le premier lancement doit réussir seul.** Chaque cause d'échec relevée dans les Issues devient soit une correction, soit une ligne de FAQ, soit un message plus clair dans le splash.
- **`launch.log` comme réflexe de support** : le template d'issue le demande, la FAQ explique où il est. C'est déjà l'outil qui a révélé les 424 invisibles ; il servira autant pour les utilisateurs.
- **Demandes de langues / compagnons** : catalogue JSON, facile à étendre — accepter les demandes, répondre vite, remercier publiquement.
- **Changelog lisible** à chaque release (déjà en place avec `--notes-file`) : les utilisateurs suivent un projet qui montre qu'il vit.
- **Compat Riot** : à chaque mise à jour du Riot Client, tester et publier un court message « testé avec la version du JJ/MM ». C'est la question numéro un après chaque patch, et c'est là que les tutoriels manuels meurent.

---

## 6. Mesurer (sans télémétrie — règle du projet)

- Téléchargements par release : API GitHub (`/repos/…/releases`, champ `download_count`).
- Étoiles, forks, trafic et *referrers* : onglet *Insights → Traffic* du dépôt (14 jours glissants, à relever chaque semaine).
- Issues ouvertes / fermées, délai de réponse.
- Position Google sur 3 requêtes cibles (FR, EN, ES), relevée à la main une fois par mois.

Objectifs raisonnables à 3 mois : 500 téléchargements, 50 étoiles, une vidéo à 5 000 vues, la page d'atterrissage en première page sur la requête FR.

---

## 7. Calendrier

| Semaine | Quoi |
|---|---|
| 1 | Section 1 entière (GIF, accroche, FAQ, VirusTotal, dépôt, templates). |
| 2 | Vidéo YouTube · post r/leagueoflegends · message à 3–5 streamers FR. |
| 3 | Post LinkedIn technique · Discords FR · r/LearnJapanese. |
| 4 | Page d'atterrissage GitHub Pages FR/EN. |
| Mois 2 | Traductions ES / PT-BR (README + page) · posts communautés correspondantes · réponses dans les fils existants (routine hebdomadaire, 30 min). |
| Chaque patch Riot | Test + message de compatibilité. |

---

## 8. Risques et parades

| Risque | Parade |
|---|---|
| Fil Reddit qui tourne au « c'est un cheat / un virus » | FAQ dans le corps du post, code en clair, VirusTotal, ton calme ; ne jamais débattre plus de deux réponses. |
| Attention de Riot | Non-affiliation partout, aucune fonction touchant le jeu, aucun avantage compétitif, marques respectées. Retirer sans discuter tout ce qui serait demandé. |
| VAN 216 chez un utilisateur | Déjà documenté et prévenu par le splash ; le dire d'avance dans la FAQ. |
| Riot Client mis à jour, lancement cassé | Journal + issue template + réactivité ; un message de compat par patch. |
| Charge de support | Issues uniquement, templates, FAQ alimentée par les issues. |
| Windows seulement | L'annoncer dès la première ligne ; ne pas promettre Mac. |

---

## 9. Ce qui deviendrait des tâches du plan `outreach`

Repris dans `.forge/branch/outreach/plan.md` (T1 → T6) :

- **T1** — GIF de démonstration + accroche orientée besoin en tête des README ×3 (S).
- **T2** — FAQ *Confiance / Vanguard / Riot / SmartScreen* dans les README ×3 (S).
- **T3** — `make-release` : lien VirusTotal dans les notes de release, à côté du SHA-256 (S).
- **T4** — Templates d'issues GitHub (bug avec `launch.log`, demande de langue/compagnon) + Discussions (S).
- **T5** — Page d'atterrissage GitHub Pages, une page FR/EN (M).
- **T6** — README ES et PT-BR (M, après stabilisation du texte EN).

Les contenus de diffusion (post Reddit, script vidéo, post LinkedIn, message aux streamers) sont des livrables d'OUTPUT, produits à la demande (section 3.9).
