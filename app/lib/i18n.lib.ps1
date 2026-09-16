<#
.SYNOPSIS
    Traductions de l'interface (fenêtre et console) : résolution de la langue, dictionnaires JSON, Get-Text.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\i18n.lib.ps1')
        Initialize-Translation (Resolve-UiLanguage $Language (Get-UICulture).Name)
        Get-Text 'setup.button.next'
        Get-Text 'shortcuts.created' $path          # placeholders {0}, {1}… au format .NET

    Dictionnaires : app\i18n\<langue>.json — un objet plat { "section.cle": "texte" }, mêmes clés dans chaque langue.
    Langue par défaut : anglais — elle sert de repli pour toute clé absente de la langue active ;
    une clé absente partout rend la clé elle-même. Get-Text ne lève jamais d'exception : un libellé manquant
    ne doit pas faire échouer une installation.

    L'état ($script:Translation) vit dans la portée du script hôte : un moteur dot-sourcé par setup.ps1 hérite
    de la langue choisie dans la fenêtre.
#>

$SupportedUiLanguages = @('fr', 'en', 'ja')
$DefaultUiLanguage    = 'en'
# Nom de chaque langue dans sa propre langue : un sélecteur reste lisible quelle que soit la langue active
$UiLanguageLabels     = @{ fr = 'Français'; en = 'English'; ja = '日本語' }

$script:Translation = $null   # @{ Language ; Strings ; Fallback }

function Test-UiLanguageSupported([string]$Language) {
    return ($SupportedUiLanguages -contains $Language)
}

# Éléments Key/Label d'un sélecteur de langue, dans l'ordre des langues supportées
function Get-UiLanguageItems {
    return @($SupportedUiLanguages | ForEach-Object { [pscustomobject]@{ Key = $_; Label = $UiLanguageLabels[$_] } })
}

# « FR » → « fr », « ja-JP » → « ja » : code de langue à deux lettres, en minuscules
function ConvertTo-UiLanguageCode([string]$Value) {
    return ([string]$Value -split '-')[0].ToLowerInvariant()
}

# Langue demandée si supportée, sinon celle de Windows (« fr-CA » → « fr »), sinon la langue par défaut
function Resolve-UiLanguage([string]$Requested, [string]$WindowsCulture) {
    foreach ($candidate in @((ConvertTo-UiLanguageCode $Requested), (ConvertTo-UiLanguageCode $WindowsCulture))) {
        if (Test-UiLanguageSupported $candidate) { return $candidate }
    }
    return $DefaultUiLanguage
}

# Dossier app\i18n, frère de lib\
function Get-TranslationFolder {
    return Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
}

function Read-TranslationCatalog([string]$Folder, [string]$Language) {
    $path = Join-Path $Folder "$Language.json"
    if (-not (Test-Path $path)) { throw "Dictionnaire introuvable : $path" }
    $strings = @{}
    $catalog = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $catalog.PSObject.Properties) { $strings[$property.Name] = [string]$property.Value }
    return $strings
}

# Charge la langue active et la langue par défaut (repli) ; rend la langue effectivement chargée
function Initialize-Translation([string]$Language, [string]$Folder = (Get-TranslationFolder)) {
    $resolved = Resolve-UiLanguage $Language $null
    $fallback = Read-TranslationCatalog $Folder $DefaultUiLanguage
    $strings  = if ($resolved -eq $DefaultUiLanguage) { $fallback } else { Read-TranslationCatalog $Folder $resolved }
    $script:Translation = @{ Language = $resolved; Strings = $strings; Fallback = $fallback }
    return $resolved
}

function Test-TranslationLoaded {
    return ($null -ne $script:Translation)
}

function Get-UiLanguage {
    if (-not (Test-TranslationLoaded)) { return $null }
    return $script:Translation.Language
}

function Find-TranslationTemplate([string]$Key) {
    if (-not (Test-TranslationLoaded)) { return $Key }
    if ($script:Translation.Strings.ContainsKey($Key))  { return $script:Translation.Strings[$Key] }
    if ($script:Translation.Fallback.ContainsKey($Key)) { return $script:Translation.Fallback[$Key] }
    return $Key
}

# Valeur traduisible d'un catalogue JSON : chaîne nue rendue telle quelle ; objet { fr, en, ja } → langue active,
# sinon langue par défaut, sinon première valeur déclarée
function Get-LocalizedValue($Value) {
    if ($null -eq $Value -or $Value -is [string]) { return $Value }
    foreach ($language in @((Get-UiLanguage), $DefaultUiLanguage)) {
        if ($language -and $null -ne $Value.PSObject.Properties[$language]) { return [string]$Value.$language }
    }
    $first = @($Value.PSObject.Properties) | Select-Object -First 1
    if ($null -ne $first) { return [string]$first.Value }
    return $null
}

function Get-Text([string]$Key, [object[]]$Arguments = @()) {
    $template = Find-TranslationTemplate $Key
    if ($Arguments.Count -eq 0) { return $template }
    return ($template -f $Arguments)
}
