<#
.SYNOPSIS
    Essai réel : lance le jeu par launch-lol.ps1 et relève toute écriture sur les fichiers texte (.wad.client) de
    DATA\FINAL et DATA\FINAL\Localized pendant le lancement (outil de dev, hors release).

.DESCRIPTION
    Sert à vérifier qu'un lancement normal n'écrit rien dans le dossier du jeu, et qu'un lancement après texte forcé
    n'y écrit que la restauration, au début. Lecture seule de l'installation : seul le lanceur y écrit.

    Les événements sont lus par Get-Event, jamais par une action Register-ObjectEvent : une action n'est exécutée
    que lorsque PowerShell est libre (après la fin du lanceur, pendant un Start-Sleep…), et l'heure qu'elle relèverait
    serait celle du traitement. TimeGenerated est l'heure de l'événement.

.EXAMPLE
    .\tools\watch-launch.ps1 -Locale ja_JP
    .\tools\watch-launch.ps1 -Locale ja_JP -TextLocale fr_FR
#>
param(
    [string]$Locale = 'ja_JP',
    [string]$TextLocale = '',
    [string]$LeagueFolder = 'C:\Riot Games\League of Legends',
    # La vérification du client LoL passe ~10 s après son démarrage : on surveille encore après la fin du lanceur
    [int]$SettleSeconds = 30
)

$final = Join-Path $LeagueFolder 'Game\DATA\FINAL'
$launcher = Join-Path $PSScriptRoot '..\app\launch-lol.ps1'
$textFiles = @((Join-Path $final "Localized\Global.$Locale.wad.client"), (Join-Path $final "UI.$Locale.wad.client"))

function Get-TextFileFingerprints {
    return ($textFiles | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash.Substring(0, 8) }) -join ' '
}

$watchers = foreach ($folder in (Join-Path $final 'Localized'), $final) {
    $watcher = New-Object IO.FileSystemWatcher($folder, '*.wad.client')
    $watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName, CreationTime'
    foreach ($eventName in 'Changed', 'Created', 'Renamed', 'Deleted') {
        Register-ObjectEvent $watcher $eventName -SourceIdentifier ('watch-launch.{0}.{1}' -f $folder.GetHashCode(), $eventName) | Out-Null
    }
    $watcher.EnableRaisingEvents = $true
    $watcher
}

Write-Output ('début {0:HH:mm:ss} — empreintes {1}' -f (Get-Date), (Get-TextFileFingerprints))
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher, '-Locale', $Locale)
if ($TextLocale) { $arguments += @('-TextLocale', $TextLocale) }
& powershell.exe @arguments | Out-Null
Write-Output ('lanceur terminé {0:HH:mm:ss}' -f (Get-Date))
Start-Sleep -Seconds $SettleSeconds
Write-Output ('fin {0:HH:mm:ss} — empreintes {1}' -f (Get-Date), (Get-TextFileFingerprints))

$watchers | ForEach-Object { $_.EnableRaisingEvents = $false; $_.Dispose() }
$events = @(Get-Event | Where-Object { $_.SourceIdentifier -like 'watch-launch.*' })
Write-Output ('écritures détectées : {0}' -f $events.Count)
$events | ForEach-Object { '{0:HH:mm:ss.fff} {1} {2}' -f $_.TimeGenerated, $_.SourceEventArgs.ChangeType, $_.SourceEventArgs.Name }
$events | Remove-Event
Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'watch-launch.*' } | Unregister-Event
