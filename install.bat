@echo off
rem Installation du lanceur League of Legends multi-langue :
rem   1. detecte les emplacements (Riot, appli compagnon) et genere config.json s'il n'existe pas
rem   2. cree les raccourcis sur le Bureau
rem A relancer apres toute modification de config.json ou deplacement du dossier.

echo ====================================================
echo   Lanceur League of Legends - installation
echo ====================================================
echo.
echo [1/2] Detection de la configuration
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detect-config.ps1"
if errorlevel 1 goto :error

echo.
echo [2/2] Choix des langues et creation des raccourcis sur le Bureau
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-shortcuts.ps1"
if errorlevel 2 goto :cancelled
if errorlevel 1 goto :error

echo.
echo Termine. Un raccourci "League of Legends XX" par langue choisie est sur le Bureau.
echo Relancer install.bat pour ajouter ou retirer des langues.
echo.
echo Pour changer l'application compagnon ou un chemin : editer config.json
echo puis relancer install.bat. Pour tout re-detecter : supprimer config.json d'abord.
echo.
pause
exit /b 0

:cancelled
echo.
echo Installation annulee : aucun raccourci modifie.
pause
exit /b 0

:error
echo.
echo [ERREUR] L'installation a echoue. Voir les messages ci-dessus.
pause
exit /b 1
