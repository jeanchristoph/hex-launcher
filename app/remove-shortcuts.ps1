<#
.SYNOPSIS
    Retire du Bureau les raccourcis de ce lanceur : raccourcis de jeu et « Hex Launcher ». Appelé par le désinstalleur.

.DESCRIPTION
    Seuls les raccourcis qui pointent vers CE dossier sont retirés : ceux d'une autre copie de hex-launcher
    (version portable à côté d'une version installée) restent en place. Les données
    (%LOCALAPPDATA%\hex-launcher\) ne sont pas touchées.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File remove-shortcuts.ps1
#>
param(
    # Dossier où chercher les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop')
)

. (Join-Path $PSScriptRoot 'create-shortcuts.ps1') -Destination $Destination

# « Hex Launcher.lnk » de la destination, s'il ouvre le setup.bat de ce dossier ; $null sinon
function Get-OwnSetupShortcut([string]$Directory) {
    $path = [IO.Path]::Combine($Directory, "$SetupShortcutName.lnk")
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    if ($shell.CreateShortcut($path).TargetPath -ne $setupBatch) { return $null }
    return $path
}

# Chemins de tous les raccourcis de ce lanceur dans la destination
function Get-OwnShortcutPaths([string]$Directory) {
    $paths = @(Get-ExistingLaunchShortcuts $Directory | ForEach-Object { $_.Path })
    $setup = Get-OwnSetupShortcut $Directory
    if ($setup) { $paths += $setup }
    return $paths
}

# Un raccourci verrouillé ne bloque jamais la désinstallation : il est signalé et laissé. Rend les chemins retirés.
function Remove-OwnShortcuts([string]$Directory) {
    $removed = foreach ($path in Get-OwnShortcutPaths $Directory) {
        try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop; $path }
        catch { Write-Warning "Raccourci non retiré : $path ($($_.Exception.Message))" }
    }
    return @($removed)
}

if ($MyInvocation.InvocationName -ne '.') {
    Remove-OwnShortcuts $Destination | ForEach-Object { "Retiré : $_" }
}
