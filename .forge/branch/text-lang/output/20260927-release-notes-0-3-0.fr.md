## Hex Launcher 0.3.0 — voix et texte dans deux langues

Les voix japonaises avec le texte en français, ou l'inverse : un raccourci peut désormais lancer le jeu avec les voix dans une langue et le texte en jeu dans une autre. Aucun réglage Riot ne le permet ; Hex Launcher remplace pour cela deux fichiers texte du jeu. **Riot n'autorise pas les modifications de fichiers : le compte peut être sanctionné, jusqu'au bannissement. À vos risques.**

### Texte forcé

- **Dans l'assistant** (`setup.bat`, page *Raccourcis*) : cochez « Forcer le texte en jeu en : » et choisissez la langue du texte. Chaque langue cochée reste celle des voix. Un avertissement rouge rappelle le risque dès que la case est cochée.
- **Raccourci** `League of Legends JP-FR` (voix JP, texte FR), avec ou sans appli compagnon. Son icône est coupée en diagonale : drapeau des voix en haut, drapeau du texte en bas, le logo HL restant au-dessus du trait ; avec les pastilles pays, c'est la pastille qui est coupée.
- **Fichiers originaux Riot** : les deux fichiers texte (`Global`, `UI`, ~4 Mo) de la langue choisie sont téléchargés depuis le CDN officiel de Riot, pour la version exacte installée, et gardés en cache (`%LOCALAPPDATA%\hex-launcher\text\`). Ce sont les fichiers signés par Riot, identiques à ceux d'un joueur dans cette langue.
- **Posés au bon moment** : une fois le client LoL ouvert et sa vérification des fichiers passée (une quinzaine de secondes). Posés plus tôt, ils seraient réparés par le client.
- **Remis en place** au début du lancement suivant par un raccourci, avant tout changement de langue.
- **Jamais bloquant** : hors ligne, format inconnu, contrôle d'intégrité en échec → la partie se joue dans la langue des voix, avec une ligne `TEXT` dans `launch.log`.
- **Splash** : en jaune sous le titre, « MODIFIED GAME FILES — TEXT: 日本語 » (nom de la langue du texte).
- Essais réels : JP-FR, FR-JP (texte japonais avec voix françaises), démarrage manuel, appli compagnon, changement de langue des voix entre deux lancements.

### Nouveau jeu d'icônes « Logo HL + pastilles »

- Le logo HL seul, sans cadre ni drapeau, agrandi ; chaque raccourci reçoit la pastille pays (coupée en texte forcé) et la pastille de l'appli compagnon, comme « LoL officielle + pastilles », sans dépendre de l'installation de LoL.

### Divers

- Clause « à vos risques » en tête des README et de `LISEZMOI.txt`.
- Journal : l'abandon d'une attente indique sa durée réelle.
- Assistant : la liste des jeux d'icônes affiche les cinq jeux sans défilement ; le journal d'installation n'apparaît qu'une fois qu'il a quelque chose à dire.

### Confiance

- **Nouvelle dépendance binaire** : `app\lib\native\libzstd.dll`, la bibliothèque officielle de décompression zstd (facebook/zstd 1.5.7, licence BSD), empreinte SHA-256 épinglée et vérifiée à chaque chargement.
- **Réseau** : en plus de l'installation des applis compagnon, le lanceur ne contacte que le CDN officiel de Riot, et seulement en mode texte forcé.

### Sous le capot

- Nouvelles bibliothèques sous `app/lib/` : lecture du manifest du patcher Riot, téléchargement par plages depuis le CDN, pose et restauration, lecture du journal du client LoL, icône coupée.
- Outils de développement : `make-logo-icon.ps1` (icône du nouveau jeu), `watch-launch.ps1` (essai réel : relève les écritures sur les fichiers texte).
- Suite de tests : **903 tests Pester** (716 en 0.2.0), toutes les E/S simulées.

### Limites connues

- Le client LoL (menus, boutique) reste dans la langue des voix : seul le jeu en partie change.
- LoL lancé sans raccourci Hex Launcher : le client LoL remet les fichiers d'origine à son ouverture, la partie se joue dans la langue des voix.
- VAN 216 (Vanguard, démarrages rapprochés) : inchangé, le lanceur prévient dès le troisième lancement en cinq minutes.

**Mise à jour** : décompressez par-dessus l'ancien dossier ou ailleurs, lancez `setup.bat` (ou le raccourci Hex Launcher) une fois pour recréer les raccourcis. `config.json` est conservé.
