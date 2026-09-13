<#
.SYNOPSIS
    Fonctions partagées de gestion des applications compagnon : catalogue, détection, désinstallation, signature.

.DESCRIPTION
    Chargé par dot-sourcing depuis detect-config.ps1 et manage-companion-app.ps1 :
        . (Join-Path $PSScriptRoot 'lib\companion-app.lib.ps1')

    Le catalogue companion-apps.json décrit chaque application (lancement, détection, installation,
    désinstallation, éditeur signataire). Le registre Windows n'est jamais écrit : seules les clés Uninstall
    sont lues pour reconnaître une application installée et retrouver sa commande de désinstallation.
#>

. (Join-Path $PSScriptRoot 'launch-config.lib.ps1')

$CompanionInstallStrategies = @('winget', 'download', 'browser')
$CompanionUninstallModes    = @('silent', 'interactive')

$UninstallRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# ---------------------------------------------------------------- Catalogue

# %LOCALAPPDATA%\… → C:\Users\…\AppData\Local\… ; les chemins du catalogue restent portables
function Expand-CompanionPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Test-CompanionHttpsUrl([string]$Url) {
    return $Url -match '^https://'
}

function Test-CompanionRegexPattern([string]$Pattern) {
    try { [void][regex]::new($Pattern); return $true } catch { return $false }
}

# Champs exigés selon la stratégie d'installation ; le repli suit les mêmes règles
function Test-CompanionInstallEntry($Install, [string]$Strategy) {
    switch ($Strategy) {
        'winget'   { return -not [string]::IsNullOrWhiteSpace($Install.wingetId) }
        'download' { return (Test-CompanionHttpsUrl $Install.url) -and -not [string]::IsNullOrWhiteSpace($Install.arguments) }
        'browser'  { return Test-CompanionHttpsUrl $Install.browserUrl }
    }
    return $false
}

function Test-CompanionCatalogEntry($Entry) {
    $required = @($Entry.id, $Entry.name, $Entry.launch.path, $Entry.detect.registryDisplayNamePattern,
                  $Entry.install.strategy, $Entry.uninstall.mode, $Entry.signer.organization, $Entry.signer.country)
    # foreach et non le pipeline : celui-ci avale les $null, qui sont justement le cas à détecter
    foreach ($value in $required) { if ([string]::IsNullOrWhiteSpace($value)) { return $false } }
    if ($Entry.install.strategy -notin $CompanionInstallStrategies) { return $false }
    if ($Entry.uninstall.mode -notin $CompanionUninstallModes) { return $false }
    if (-not (Test-CompanionRegexPattern $Entry.detect.registryDisplayNamePattern)) { return $false }
    if (-not ([int]$Entry.install.timeoutSeconds -gt 0)) { return $false }
    if (-not (Test-CompanionInstallEntry $Entry.install $Entry.install.strategy)) { return $false }
    if ($Entry.install.fallback -and -not (Test-CompanionInstallEntry $Entry.install $Entry.install.fallback)) { return $false }
    return $true
}

function Read-CompanionCatalog([string]$Path) {
    if (-not (Test-Path $Path)) { throw "companion-apps.json introuvable : $Path" }
    $entries = Read-JsonCatalog $Path
    $invalid = @($entries | Where-Object { -not (Test-CompanionCatalogEntry $_) })
    if ($invalid.Count -gt 0) {
        throw "companion-apps.json : entrée(s) invalide(s) : $(($invalid | ForEach-Object { $_.id }) -join ', ')"
    }
    return $entries
}

function Find-CompanionCatalogEntry([object[]]$Catalog, [string]$Id) {
    return $Catalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

# ---------------------------------------------------------------- Registre (lecture seule)

# Seule fonction qui touche au registre : lecture des clés Uninstall des trois ruches
function Get-UninstallRegistryEntries {
    return @(Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
        Select-Object DisplayName, DisplayVersion, UninstallString, QuietUninstallString)
}

# Motif regex : le DisplayName d'OP.GG embarque la version ("OP.GG 2.5.5")
function Find-CompanionRegistryEntry($App, [object[]]$RegistryEntries) {
    return $RegistryEntries | Where-Object { $_.DisplayName -match $App.detect.registryDisplayNamePattern } | Select-Object -First 1
}

function Test-CompanionPathPresent($App) {
    $path = Expand-CompanionPath $App.detect.path
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    return Test-Path $path
}

# Installée si sa clé Uninstall existe ou si son chemin de détection est présent
function Test-CompanionInstalled($App, [object[]]$RegistryEntries) {
    if ($null -eq $RegistryEntries) { $RegistryEntries = Get-UninstallRegistryEntries }
    if (Find-CompanionRegistryEntry $App $RegistryEntries) { return $true }
    return Test-CompanionPathPresent $App
}

function New-InstalledCompanionApp($App, $RegistryEntry) {
    return [pscustomobject]@{ App = $App; Registry = $RegistryEntry }
}

# Applis du catalogue présentes sur la machine, dans l'ordre du catalogue (= priorité).
# Un foreach sans résultat vaut $null : le Where-Object l'élimine pour que l'appelant, qui enveloppe
# toujours l'appel dans @(), obtienne un tableau vide et non un élément $null.
function Get-InstalledCompanionApps([object[]]$Catalog) {
    $entries   = Get-UninstallRegistryEntries
    $installed = foreach ($app in $Catalog) {
        if (Test-CompanionInstalled $app $entries) { New-InstalledCompanionApp $app (Find-CompanionRegistryEntry $app $entries) }
    }
    return @($installed | Where-Object { $null -ne $_ })
}

# ---------------------------------------------------------------- Désinstallation

# silent      : QuietUninstallString si l'installeur en fournit une, sinon UninstallString + /S (convention NSIS)
# interactive : UninstallString telle quelle — l'outil de l'éditeur affiche son propre dialogue (menu Overwolf)
function Resolve-CompanionUninstallCommand($App, $RegistryEntry) {
    if ($null -eq $RegistryEntry -or [string]::IsNullOrWhiteSpace($RegistryEntry.UninstallString)) { return $null }
    if ($App.uninstall.mode -eq 'interactive') { return $RegistryEntry.UninstallString }
    if (-not [string]::IsNullOrWhiteSpace($RegistryEntry.QuietUninstallString)) { return $RegistryEntry.QuietUninstallString }
    return "$($RegistryEntry.UninstallString) /S"
}

# Une UninstallString est une ligne complète : "C:\…\Uninstall X.exe" /S — ou, sans guillemets,
# C:\Program Files (x86)\Overwolf\OWUninstaller.exe --uninstall-app=… (Windows la lance via CreateProcess,
# qui tolère les espaces). On sépare exécutable et arguments pour Start-Process : le premier ".exe"
# suivi d'un blanc ou de la fin de ligne termine le chemin.
function Split-CompanionCommandLine([string]$CommandLine) {
    $line = $CommandLine.Trim()
    if ($line.StartsWith('"')) {
        $end = $line.IndexOf('"', 1)
        if ($end -lt 0) { return @{ Path = $line.Trim('"'); Arguments = '' } }
        return @{ Path = $line.Substring(1, $end - 1); Arguments = $line.Substring($end + 1).Trim() }
    }
    if ($line -match '^(?<path>.*?\.exe)(?:\s+(?<args>.*))?$') {
        return @{ Path = $Matches['path']; Arguments = [string]$Matches['args'] }
    }
    return @{ Path = $line; Arguments = '' }
}

# Les codes de sortie ne sont pas fiables (désinstalleur NSIS asynchrone, installeur Overwolf → 1223) :
# on sonde l'état réel jusqu'à ce qu'il corresponde à l'attendu, ou jusqu'au délai.
# $OnTick : attente d'une seconde fournie par l'appelant (ex. Wait-WithAnimation pour un splash) ; sinon Start-Sleep
function Wait-CompanionState($App, [bool]$Installed, [int]$TimeoutSeconds, [scriptblock]$OnTick) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-CompanionInstalled $App) -eq $Installed) { return $true }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }
    return ((Test-CompanionInstalled $App) -eq $Installed)
}

# ---------------------------------------------------------------- Signature Authenticode

# Le Subject est découpé en RDN (une ligne par composant, via SubjectName.Format) : un "O=" glissé dans
# un CN ou un OU ne compte pas. Comparaison sensible à la casse sur l'organisation ET le pays.
# Jamais de thumbprint épinglé : les certificats se renouvellent.
function Test-CompanionCertificateSubject([string]$SubjectLines, [string]$Organization, [string]$Country) {
    $components = @{}
    foreach ($line in ($SubjectLines -split "`r?`n")) {
        if ($line -match '^\s*(?<key>[A-Za-z0-9.]+)=(?<value>.*)$') { $components[$Matches['key']] = $Matches['value'].Trim().Trim('"') }
    }
    return ($components['O'] -ceq $Organization) -and ($components['C'] -ceq $Country)
}

function Get-CompanionSignatureSubject([string]$FilePath) {
    $signature = Get-AuthenticodeSignature -FilePath $FilePath
    if ($signature.Status -ne 'Valid') { return $null }
    return $signature.SignerCertificate.SubjectName.Format($true)
}

# BUSINESS_RULE : jamais d'exécution d'un binaire (installeur téléchargé ou désinstalleur lu dans le
# registre) sans signature Authenticode valide émise pour l'éditeur attendu par le catalogue.
function Test-CompanionBinaryTrusted([string]$FilePath, $Signer) {
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not [IO.Path]::IsPathRooted($FilePath)) { return $false }
    if ([IO.Path]::GetExtension($FilePath) -ne '.exe') { return $false }
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) { return $false }
    $subject = Get-CompanionSignatureSubject $FilePath
    if ($null -eq $subject) { return $false }
    return Test-CompanionCertificateSubject $subject $Signer.organization $Signer.country
}

# ---------------------------------------------------------------- Entrée companionApps de config.json

# Entrée de la liste companionApps de config.json — lue par launch-lol.ps1 (-Companion <id>) et create-shortcuts.ps1.
# processNames sert au lanceur à fermer les autres applis compagnon avant la partie.
function ConvertTo-LaunchCompanionEntry($App) {
    return [ordered]@{
        id           = $App.id
        name         = $App.name
        path         = Expand-CompanionPath $App.launch.path
        arguments    = [string]$App.launch.arguments
        processNames = @($App.processNames | Where-Object { $_ })
    }
}
