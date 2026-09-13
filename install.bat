@echo off
rem hex-launcher : ouvre l'assistant d'installation (app\install.ps1) dans une fenetre unique, sans console.
rem   1. detecte les emplacements (Riot, applis compagnon) et genere app\config.json s'il n'existe pas
rem   2. propose les applications compagnon (Porofessor, Blitz, OP.GG, Mobalytics) : installation / desinstallation
rem   3. cree les raccourcis langue x appli compagnon sur le Bureau
rem A relancer apres toute modification de app\config.json ou deplacement du dossier.
rem Ne pas lancer en tant qu'administrateur : l'assistant refuse (installeurs per-user).

start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\install.ps1"
