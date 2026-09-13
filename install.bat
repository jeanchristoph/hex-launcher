@echo off
rem Installation du lanceur League of Legends : ouvre l'assistant install.ps1 (fenetre unique, sans console).
rem   1. detecte les emplacements (Riot, applis compagnon) et genere config.json s'il n'existe pas
rem   2. propose les applications compagnon (Porofessor, Blitz, OP.GG, Mobalytics) : installation / desinstallation
rem   3. cree les raccourcis langue x appli compagnon sur le Bureau
rem A relancer apres toute modification de config.json ou deplacement du dossier.
rem Ne pas lancer en tant qu'administrateur : l'assistant refuse (installeurs per-user).

start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0install.ps1"
