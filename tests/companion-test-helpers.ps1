<#
.SYNOPSIS
    Fabriques partagées par les tests Pester des applis compagnon (objets catalogue, entrées de registre, fichiers temporaires).
#>

$script:TestTempFiles = @()

function New-TestCompanionApp {
    param(
        [string]$Id = 'app',
        [string]$Pattern = '^App$',
        [string]$DetectPath = '',
        [string]$Mode = 'silent',
        [string]$Strategy = 'download',
        [string]$Fallback = 'browser',
        [string]$Notice = $null,
        [string[]]$DialogProcessNames = @(),
        [string[]]$ProcessNames = @()
    )
    return [pscustomobject]@{
        id           = $Id
        name         = $Id
        signer       = [pscustomobject]@{ organization = 'Vendor'; country = 'US' }
        processNames = $ProcessNames
        launch       = [pscustomobject]@{ path = '%TEMP%\app.exe'; arguments = '--flag' }
        detect       = [pscustomobject]@{ registryDisplayNamePattern = $Pattern; path = $DetectPath }
        install      = [pscustomobject]@{
            strategy = $Strategy; wingetId = 'Vendor.App'; url = 'https://example.test/setup.exe'; arguments = '/S'
            timeoutSeconds = 30; fallback = $Fallback; browserUrl = 'https://example.test/download'
        }
        uninstall    = [pscustomobject]@{ mode = $Mode; dialogProcessNames = $DialogProcessNames; notice = $Notice }
    }
}

function New-RegistryEntry([string]$Name, [string]$Uninstall, [string]$Quiet = $null, [string]$Version = '1.0') {
    return [pscustomobject]@{ DisplayName = $Name; DisplayVersion = $Version; UninstallString = $Uninstall; QuietUninstallString = $Quiet }
}

# Objet tel que rendu par Get-InstalledCompanionApps
function New-TestInstalledApp($App, $Registry = $null) {
    if ($null -eq $Registry) { $Registry = New-RegistryEntry $App.name '"C:\Apps\u.exe"' '"C:\Apps\u.exe" /S' }
    return [pscustomobject]@{ App = $App; Registry = $Registry }
}

function New-TempFile([string]$Prefix, [string]$Content) {
    $path = Join-Path $env:TEMP ("{0}-{1}.json" -f $Prefix, [guid]::NewGuid())
    [IO.File]::WriteAllText($path, $Content, (New-Object Text.UTF8Encoding($false)))
    $script:TestTempFiles += $path
    return $path
}

function Remove-TestTempFiles {
    foreach ($path in $script:TestTempFiles) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    $script:TestTempFiles = @()
}

function New-TempCatalog([string]$Json) { return New-TempFile 'companion-apps-test' $Json }

# Ancien format : bloc companionApp unique
function New-TempLegacyConfig {
    return New-TempFile 'config-test' '{ "riotClientPath": "C:\\Riot\\RiotClientServices.exe", "productSettingsPath": "C:\\yaml", "companionApp": { "enabled": true, "name": "OP.GG", "path": "C:\\old\\OP.GG.exe", "arguments": "" } }'
}

# Nouveau format : liste companionApps
function New-TempConfig([string]$CompanionApps = '[]') {
    return New-TempFile 'config-test' ('{ "riotClientPath": "C:\\Riot\\RiotClientServices.exe", "productSettingsPath": "C:\\yaml", "companionApps": ' + $CompanionApps + ' }')
}

# Entrée catalogue valide, au format JSON, pour les tests de validation
function New-CatalogEntryJson([hashtable]$Overrides = @{}) {
    $entry = @{
        id = 'x'; name = 'X'
        signer = @{ organization = 'Vendor'; country = 'US' }
        processNames = @()
        launch = @{ path = 'x.exe'; arguments = '' }
        detect = @{ registryDisplayNamePattern = '^X'; path = '' }
        install = @{ strategy = 'winget'; wingetId = 'V.X'; timeoutSeconds = 30; fallback = 'browser'; browserUrl = 'https://example.test/' }
        uninstall = @{ mode = 'silent' }
    }
    foreach ($key in $Overrides.Keys) { $entry[$key] = $Overrides[$key] }
    return '[' + ($entry | ConvertTo-Json -Depth 5) + ']'
}
