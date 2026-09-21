# Post LinkedIn — Hex Launcher (récit technique)
**Date :** 2026-09-21 · **Angle :** méthode et leçons, pas publicité (plan de diffusion, section 3.6) · **Lien :** en premier commentaire, jamais dans le corps

## Post

J'ai passé deux jours à automatiser un clic.

Le clic « Jouer » du Riot Client, pour lancer League of Legends dans la langue de son choix depuis un raccourci sur le Bureau. Un projet perso, minuscule en apparence. Voilà ce qu'il m'a appris.

**1. Le transport avant la fonctionnalité.** Le client expose une API locale, non documentée, en HTTPS auto-signé. `Invoke-WebRequest` refuse la renégociation TLS : il a fallu descendre à WinHTTP. Premier soir passé sur la couche réseau, pas sur le produit.

**2. Sans journal, on ne sait rien.** Un `launch.log` horodaté a révélé 57 secondes de refus « 424 » qu'aucun essai à la main n'avait montrées : le client patchait en silence. La fonctionnalité la plus utile n'est pas celle qu'on voit.

**3. Retirer est une décision d'ingénierie.** J'avais ajouté une « mémoire de lancement » qui apprenait des échecs. Trop maligne, imprévisible pour l'utilisateur. Supprimée deux tâches plus tard, avec ses tests. Le meilleur code est parfois celui qu'on n'a pas gardé.

**4. PowerShell 5.1 et WinForms se testent.** 700 tests Pester, une machine à états testée sans ouvrir une seule fenêtre, des mocks sur les seules I/O. Le langage n'est jamais l'excuse.

**5. Un agent IA sans cadre est un stagiaire brillant qui n'écrit pas de tests.** Tout le projet a été mené avec Claude Code sous un processus que j'ai écrit, claude_forge : brief validé, plan validé, aucune ligne de code sans accord, tests en parallèle, journal des décisions. Le critère de réussite : un code qu'un humain relit sans moi.

Open source, Windows, non affilié à Riot Games. Le lien est en premier commentaire.

#PowerShell #SoftwareCraftsmanship

## Premier commentaire (à poster immédiatement après)

Le dépôt : https://github.com/jeanchristoph/hex-launcher — README en FR, EN et JA, section Confiance pour ceux qui se demandent ce que fait un .bat inconnu.

## Notes de publication

- LinkedIn n'interprète pas le Markdown : les `**gras**` sont à retirer ou à remplacer par du texte en majuscules courtes / des emojis numérotés, au choix ; les backticks disparaissent.
- Créneau : mardi à jeudi, 8 h–9 h Paris.
- Répondre à chaque commentaire dans les 24 h ; les questions techniques récurrentes nourrissent la FAQ (T2).
- Pas de version anglaise prévue : le réseau visé est francophone.
