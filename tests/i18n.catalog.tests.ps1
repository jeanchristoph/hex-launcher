<#
.SYNOPSIS
    Tests Pester 3.4 des dictionnaires app\i18n\*.json : un fichier par langue supportée, mêmes clés partout,
    mêmes placeholders {n} par clé, aucune valeur vide. Une traduction oubliée casse la suite avant la release.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\i18n.lib.ps1')

$TranslationFolder = Join-Path $here '..\app\i18n'

function Get-TranslationPlaceholders([string]$Text) {
    return @([regex]::Matches($Text, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
}

# Description lisible d'un écart : "clé (fr, ja)"
function Format-KeyDifferences([hashtable]$Differences) {
    return (@($Differences.Keys | Sort-Object | ForEach-Object { "$_ ($($Differences[$_] -join ', '))" }) -join ' ; ')
}

$Catalogs = @{}
foreach ($language in $SupportedUiLanguages) { $Catalogs[$language] = Read-TranslationCatalog $TranslationFolder $language }
$ReferenceKeys = @($Catalogs[$DefaultUiLanguage].Keys | Sort-Object)

Describe 'Dictionnaires de traduction' {
    It 'fournit un fichier JSON valide pour chaque langue supportée' {
        foreach ($language in $SupportedUiLanguages) {
            Test-Path (Join-Path $TranslationFolder "$language.json") | Should Be $true
            $Catalogs[$language].Count | Should BeGreaterThan 0
        }
    }

    It 'déclare exactement les mêmes clés dans chaque langue' {
        $differences = @{}
        foreach ($language in $SupportedUiLanguages) {
            $keys = @($Catalogs[$language].Keys)
            foreach ($key in $ReferenceKeys) { if ($keys -notcontains $key) { $differences[$key] = @($differences[$key]) + "missing in $language" } }
            foreach ($key in $keys) { if ($ReferenceKeys -notcontains $key) { $differences[$key] = @($differences[$key]) + "extra in $language" } }
        }
        Format-KeyDifferences $differences | Should BeNullOrEmpty
    }

    It 'ne laisse aucune valeur vide' {
        $empty = @()
        foreach ($language in $SupportedUiLanguages) {
            foreach ($key in $Catalogs[$language].Keys) {
                if ([string]::IsNullOrWhiteSpace($Catalogs[$language][$key])) { $empty += "$key ($language)" }
            }
        }
        ($empty -join ' ; ') | Should BeNullOrEmpty
    }

    It 'utilise les mêmes placeholders {n} pour une clé dans chaque langue' {
        $differences = @{}
        foreach ($key in $ReferenceKeys) {
            $expected = (Get-TranslationPlaceholders $Catalogs[$DefaultUiLanguage][$key]) -join ','
            foreach ($language in $SupportedUiLanguages) {
                if (-not $Catalogs[$language].ContainsKey($key)) { continue }
                $actual = (Get-TranslationPlaceholders $Catalogs[$language][$key]) -join ','
                if ($actual -ne $expected) { $differences[$key] = @($differences[$key]) + $language }
            }
        }
        Format-KeyDifferences $differences | Should BeNullOrEmpty
    }

    It 'nomme chaque clé section.nom en camelCase, sans espace ni majuscule initiale' {
        $invalid = @($ReferenceKeys | Where-Object { $_ -notmatch '^[a-z]+(\.[a-z][A-Za-z0-9]*)+$' })
        ($invalid -join ' ; ') | Should BeNullOrEmpty
    }

    It 'se charge dans la lib pour chaque langue et rend un texte différent de la clé' {
        foreach ($language in $SupportedUiLanguages) {
            Initialize-Translation $language $TranslationFolder | Should Be $language
            Get-Text 'setup.button.next' | Should Not Be 'setup.button.next'
        }
    }
}
