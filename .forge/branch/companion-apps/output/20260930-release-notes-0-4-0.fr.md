## Hex Launcher 0.4.0 — installeur, version portable et mises à jour automatiques

- **Deux téléchargements au choix** :
  - `hex-launcher-setup-0.4.0.exe` (recommandé) : installe dans `%LOCALAPPDATA%\Programs\hex-launcher`, sans droits administrateur, avec Hex Launcher dans le menu Démarrer et une entrée dans *Applications installées*. L'installeur n'est pas signé : SmartScreen peut afficher « Windows a protégé votre ordinateur » (*Informations complémentaires* → *Exécuter quand même*, après avoir vérifié l'empreinte ci-dessous).
  - `hex-launcher-portable-0.4.0.zip` : à décompresser où l'on veut ; les réglages restent dans `data\`, à côté de `setup.bat`.
- **Mises à jour automatiques** : au lancement, une nouvelle version publiée sur GitHub est proposée (*Installer* / *Plus tard*, case « Ne plus me demander jusqu'à la prochaine version »). Téléchargement vérifié par SHA-256, puis le lancement reprend dans la nouvelle version. Une seule requête à api.github.com, sans aucune donnée envoyée ; désactivable sur la page *Bienvenue* de l'assistant.
- **Réglages hors du dossier du programme** : `config.json`, le journal et les icônes composées vont dans `%LOCALAPPDATA%\hex-launcher\` (ou `data\` en portable).
- **Désinstallation** (version installée) : retire les raccourcis du Bureau et garde les réglages.
- README (EN / FR / JA) mis à jour : sections *Mises à jour* et *Désinstaller*.
- 1020 tests Pester.

**Mise à niveau depuis 0.3.x** (la mise à jour automatique n'existe qu'à partir de 0.4.0) : décompressez le zip portable par-dessus l'ancien dossier, et vos réglages sont repris dans `data\`. Ou bien passez à l'installeur, puis relancez l'assistant : les raccourcis du Bureau sont recréés, et vous pouvez ensuite supprimer l'ancien dossier.
