# Les worktrees git — explication pédagogique

Date : 2026-09-20 · Projet : hex-launcher

## 1. Ce qu'est un worktree

Un worktree est un **second dossier de travail** branché sur le **même `.git`** que le dépôt principal.
Les deux dossiers partagent tout ce qui vit dans `.git` : historique, branches, tags, remotes, stash, config.
Seuls les fichiers extraits (le « working tree ») et l'index diffèrent d'un dossier à l'autre.

Différence avec un clone :

| | Clone | Worktree |
|---|---|---|
| Nombre de dépôts (`.git`) | deux | un seul |
| Commit fait d'un côté | invisible de l'autre tant qu'on ne push/fetch pas | visible immédiatement |
| Remote à synchroniser entre les deux | oui | non |
| Espace disque | historique dupliqué | historique partagé |

Le dossier principal (`D:\www\perso\hex-launcher`) est lui-même un worktree : le « worktree principal ».
Les autres sont des « worktrees liés » (linked worktrees).

## 2. Les commandes

```powershell
git worktree add D:\www\perso\hex-launcher-icons icons        # extrait la branche icons dans un nouveau dossier
git worktree add -b feature-x D:\www\perso\hex-launcher-x master  # crée la branche feature-x depuis master, puis l'extrait
git worktree list                                              # liste tous les worktrees, leur HEAD et leur branche
git worktree remove D:\www\perso\hex-launcher-icons            # supprime le dossier et les métadonnées (refuse si modifs non commitées)
git worktree prune                                             # nettoie les métadonnées des worktrees dont le dossier a disparu
```

Où git range les choses :

- `D:\www\perso\hex-launcher\.git\worktrees\hex-launcher-icons\` : HEAD, index et métadonnées propres au worktree lié.
- `D:\www\perso\hex-launcher-icons\.git` : un **fichier**, pas un dossier. Il contient une seule ligne,
  `gitdir: D:/www/perso/hex-launcher/.git/worktrees/hex-launcher-icons`, qui renvoie vers le dépôt principal.

Chaque worktree peut avoir sa propre branche extraite, ou un HEAD détaché (`git worktree add --detach <chemin> <commit>`).

## 3. La règle qui bloque

**Une branche ne peut être extraite que dans un seul worktree à la fois.**

Pourquoi : une branche est un pointeur (`.git/refs/heads/icons`) partagé par tous les worktrees.
Si deux dossiers l'avaient extraite, un commit dans l'un déplacerait le pointeur sans mettre à jour les fichiers de l'autre.
Le second dossier se retrouverait avec un working tree qui ne correspond plus à son HEAD. Git l'interdit plutôt que de laisser cet état incohérent apparaître.

Message typique :

```text
fatal: 'icons' is already used by worktree at 'D:/www/perso/hex-launcher-icons'
```

Trois issues :

1. **Travailler dans l'autre dossier** : la branche est déjà disponible là-bas, il suffit d'y aller.
2. **Retirer le worktree** : `git worktree remove <chemin>` libère la branche (à condition que le worktree soit propre).
3. **Extraire autre chose** : une autre branche, ou un HEAD détaché sur le même commit (`git checkout --detach icons`) pour lire sans écrire.

## 4. Le cas hex-launcher, étape par étape

**Le matin.** La branche `launcher` avance dans le dossier principal. Pour qu'un agent travaille en parallèle sur `icons` sans gêner, on lui donne son propre dossier :

```powershell
git worktree add D:\www\perso\hex-launcher-icons icons
```

**L'après-midi.** Demande : « passer sur icons » dans le dossier principal.

Premier refus, sans rapport avec les worktrees :

```text
error: Your local changes to the following files would be overwritten by checkout:
        .forge/branch/launcher/log.md
```

Règle : **working tree propre avant checkout** quand un fichier modifié diffère entre les deux branches.
Deux issues : commiter (`git add .forge/branch/launcher/log.md && git commit`) ou mettre de côté (`git stash`, puis `git stash pop` après).

Second refus, celui du worktree :

```text
fatal: 'icons' is already used by worktree at 'D:/www/perso/hex-launcher-icons'
```

Avant de retirer le worktree, vérification que rien n'y serait perdu :

```powershell
cd D:\www\perso\hex-launcher-icons
git status --short                 # vide : aucune modification non commitée, aucun fichier non suivi
git rev-parse icons origin/icons   # deux hashes identiques : tout est poussé
```

Le worktree est propre et à jour du remote. On le retire, puis on enchaîne :

```powershell
cd D:\www\perso\hex-launcher
git worktree remove D:\www\perso\hex-launcher-icons
git checkout icons
git merge master
```

Rien n'est perdu parce que `remove` ne supprime que le dossier et ses métadonnées. La branche `icons`, ses commits et son suivi de `origin/icons` vivent dans `.git`, qui n'a pas bougé.

## 5. Quand s'en servir

Oui, dès que **deux branches doivent être ouvertes en même temps** :

- deux sessions d'agent qui travaillent chacune sur leur branche ;
- construire une release depuis `master` pendant qu'on code sur `dev` ;
- relire une PR dans un dossier à part sans quitter son travail en cours ni stasher.

Non, pour un simple changement de branche : `git checkout` suffit, un worktree n'apporte rien.

## 6. Pièges

- **Worktree oublié.** Des semaines plus tard, `git checkout icons` répond « already used by worktree ». Réflexe : `git worktree list`.
- **Dossier supprimé à la main.** Sans `git worktree remove`, les métadonnées restent dans `.git/worktrees/` et la branche reste marquée « extraite ». Réflexe : `git worktree prune`.
- **Fichiers ignorés ou non versionnés.** `config.json`, `launch.log`, `node_modules`… n'existent que dans le dossier où ils ont été créés. Un nouveau worktree part sans eux ; il faut les régénérer ou les copier.
- **`.forge/` versionné.** Il est présent dans chaque worktree, mais à la version de la branche extraite. Deux worktrees peuvent donc montrer deux `project.md` différents ; c'est normal, et cela se règle au merge.
- **Suppression de branche.** `git branch -d icons` échoue tant que la branche est extraite quelque part, worktree lié compris.
