<#
.SYNOPSIS
    Tests Pester 3.4 de lib\i18n.lib.ps1 : résolution de la langue, lecture des dictionnaires, Get-Text et ses replis.
    Les dictionnaires sont écrits dans un dossier temporaire : la lib est testée indépendamment de app\i18n.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\i18n.lib.ps1')

$script:TestTranslationFolders = @()

# Dossier temporaire contenant un <langue>.json par entrée de $Catalogs (langue → JSON)
function New-TempTranslationFolder([hashtable]$Catalogs) {
    $folder = Join-Path $env:TEMP ("i18n-test-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $folder | Out-Null
    foreach ($language in $Catalogs.Keys) {
        [IO.File]::WriteAllText((Join-Path $folder "$language.json"), $Catalogs[$language], (New-Object Text.UTF8Encoding($false)))
    }
    $script:TestTranslationFolders += $folder
    return $folder
}

function Remove-TempTranslationFolders {
    foreach ($folder in $script:TestTranslationFolders) { Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue }
    $script:TestTranslationFolders = @()
}

$EnglishCatalog = '{ "common.ok": "OK", "setup.welcome": "Welcome", "shortcuts.created": "Created: {0}", "detect.missing": "{0} missing — {1}" }'
$FrenchCatalog  = '{ "common.ok": "OK", "setup.welcome": "Bienvenue", "shortcuts.created": "Créé : {0}" }'

Describe 'Resolve-UiLanguage' {
    It 'prend la langue de Windows quand elle est supportée, quelle que soit la région' {
        Resolve-UiLanguage $null 'fr-FR' | Should Be 'fr'
        Resolve-UiLanguage '' 'fr-CA' | Should Be 'fr'
        Resolve-UiLanguage $null 'ja-JP' | Should Be 'ja'
        Resolve-UiLanguage $null 'en-GB' | Should Be 'en'
    }

    It 'replie sur l''anglais pour une culture non supportée, vide ou absente' {
        Resolve-UiLanguage $null 'de-DE' | Should Be 'en'
        Resolve-UiLanguage $null '' | Should Be 'en'
        Resolve-UiLanguage $null $null | Should Be 'en'
    }

    It 'donne la priorité à la langue demandée explicitement' {
        Resolve-UiLanguage 'ja' 'fr-FR' | Should Be 'ja'
    }

    It 'ignore une langue demandée inconnue et retombe sur celle de Windows' {
        Resolve-UiLanguage 'xx' 'fr-FR' | Should Be 'fr'
    }

    It 'normalise la casse et la région de la langue demandée' {
        Resolve-UiLanguage 'FR' 'de-DE' | Should Be 'fr'
        Resolve-UiLanguage 'ja-JP' 'de-DE' | Should Be 'ja'
    }
}

Describe 'Get-UiLanguageItems' {
    It 'liste chaque langue supportée sous son nom natif, dans l''ordre du catalogue' {
        $items = @(Get-UiLanguageItems)
        ($items | ForEach-Object { $_.Key }) -join ',' | Should Be 'fr,en,ja'
        ($items | ForEach-Object { $_.Label }) -join ',' | Should Be 'Français,English,日本語'
    }
}

Describe 'Get-LocalizedValue' {
    AfterEach { Remove-TempTranslationFolders }
    $notice = [pscustomobject]@{ fr = 'Suivez les étapes'; en = 'Follow the steps' }

    It 'rend une chaîne nue telle quelle et $null pour une valeur absente' {
        Get-LocalizedValue 'texte' | Should Be 'texte'
        Get-LocalizedValue $null | Should BeNullOrEmpty
    }

    It 'choisit la langue active, sinon la langue par défaut, sinon la première déclarée' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog; fr = $FrenchCatalog }
        Initialize-Translation 'fr' $folder | Out-Null
        Get-LocalizedValue $notice | Should Be 'Suivez les étapes'
        Initialize-Translation 'en' $folder | Out-Null
        Get-LocalizedValue $notice | Should Be 'Follow the steps'
        Get-LocalizedValue ([pscustomobject]@{ ja = 'のみ' }) | Should Be 'のみ'
    }
}

Describe 'Read-TranslationCatalog' {
    AfterEach { Remove-TempTranslationFolders }

    It 'lit un dictionnaire plat en hashtable clé → texte' {
        $folder  = New-TempTranslationFolder @{ en = $EnglishCatalog }
        $strings = Read-TranslationCatalog $folder 'en'
        $strings['setup.welcome'] | Should Be 'Welcome'
        $strings.Count | Should Be 4
    }

    It 'conserve les caractères accentués et les espaces insécables' {
        $folder = New-TempTranslationFolder @{ fr = $FrenchCatalog }
        (Read-TranslationCatalog $folder 'fr')['shortcuts.created'] | Should Be 'Créé : {0}'
    }

    It 'échoue explicitement si le dictionnaire est absent' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog }
        { Read-TranslationCatalog $folder 'ja' } | Should Throw 'Dictionnaire introuvable'
    }
}

Describe 'Initialize-Translation et Get-Text' {
    AfterEach { Remove-TempTranslationFolders }

    It 'rend la clé elle-même tant qu''aucune traduction n''est chargée, sans erreur' {
        $script:Translation = $null
        Test-TranslationLoaded | Should Be $false
        Get-UiLanguage | Should BeNullOrEmpty
        Get-Text 'setup.welcome' | Should Be 'setup.welcome'
    }

    It 'charge la langue demandée et rend ses textes' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog; fr = $FrenchCatalog }
        Initialize-Translation 'fr' $folder | Should Be 'fr'
        Get-UiLanguage | Should Be 'fr'
        Get-Text 'setup.welcome' | Should Be 'Bienvenue'
    }

    It 'replie sur l''anglais pour une clé absente de la langue active' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog; fr = $FrenchCatalog }
        Initialize-Translation 'fr' $folder | Out-Null
        Get-Text 'detect.missing' 'Riot Client', 'fix config.json' | Should Be 'Riot Client missing — fix config.json'
    }

    It 'rend la clé elle-même quand elle manque partout' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog; fr = $FrenchCatalog }
        Initialize-Translation 'fr' $folder | Out-Null
        Get-Text 'setup.unknown' | Should Be 'setup.unknown'
    }

    It 'formate les placeholders {0} avec les arguments fournis' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog; fr = $FrenchCatalog }
        Initialize-Translation 'fr' $folder | Out-Null
        Get-Text 'shortcuts.created' 'C:\Bureau\LoL.lnk' | Should Be 'Créé : C:\Bureau\LoL.lnk'
    }

    It 'laisse un texte sans placeholder intact quand aucun argument n''est donné' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog }
        Initialize-Translation 'en' $folder | Out-Null
        Get-Text 'common.ok' | Should Be 'OK'
    }

    It 'replie sur l''anglais pour une langue inconnue, sans lire d''autre fichier' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog }
        Initialize-Translation 'xx' $folder | Should Be 'en'
        Get-Text 'setup.welcome' | Should Be 'Welcome'
    }

    It 'échoue explicitement si le dictionnaire de la langue demandée manque' {
        $folder = New-TempTranslationFolder @{ en = $EnglishCatalog }
        { Initialize-Translation 'ja' $folder } | Should Throw 'Dictionnaire introuvable'
    }
}
