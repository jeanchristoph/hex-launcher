<#
.SYNOPSIS
    Retire du Bureau et du menu Démarrer les raccourcis de ce lanceur : raccourcis de jeu et « Hex Launcher ». Appelé par le désinstalleur.

.DESCRIPTION
    Seuls les raccourcis qui pointent vers CE dossier sont retirés : ceux d'une autre copie de hex-launcher
    (version portable à côté d'une version installée) restent en place. Le dossier « Hex Launcher » du menu
    Démarrer est retiré s'il ne contient plus rien. Les données (%LOCALAPPDATA%\hex-launcher\) ne sont pas touchées.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File remove-shortcuts.ps1
#>
param(
    # Bureau où chercher les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop'),

    # Dossier du menu Démarrer (défaut : Programs\Hex Launcher de l'utilisateur courant)
    [string]$StartMenuDestination = (Join-Path ([Environment]::GetFolderPath('Programs')) 'Hex Launcher')
)

. (Join-Path $PSScriptRoot 'create-shortcuts.ps1') -Destination $Destination -StartMenuDestination $StartMenuDestination

# Retire les raccourcis de ce lanceur de tous les emplacements, puis le dossier du menu Démarrer s'il est vide.
# Rend les chemins retirés.
function Remove-AllOwnShortcuts {
    $removed = @($LaunchShortcutLocations | ForEach-Object { Remove-OwnShortcuts (Get-ShortcutLocationFolder $_) })
    Remove-EmptyShortcutFolder $StartMenuDestination | Out-Null
    return $removed
}

if ($MyInvocation.InvocationName -ne '.') {
    Remove-AllOwnShortcuts | ForEach-Object { "Retiré : $_" }
}
