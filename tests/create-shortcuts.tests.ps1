<#
.SYNOPSIS
    Tests Pester 3.4 de app\create-shortcuts.ps1 (fonctions pures : icône, combinaisons, nommage).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\create-shortcuts.ps1')

Describe 'Get-FlagIconPath' {
    It 'dérive le nom du fichier drapeau de la partie pays du code, en minuscules' {
        Get-FlagIconPath 'ja_JP' | Should Match 'ico\\hex-launcher-jp\.ico$'
    }

    It 'cible le dossier ico à côté du script' {
        Get-FlagIconPath 'fr_FR' | Should Be (Join-Path $folder 'ico\hex-launcher-fr.ico')
    }
}

Describe 'Resolve-IconPath' {
    Context 'drapeau présent' {
        Mock Test-Path { $true }
        It 'rend l''icône drapeau de la langue' {
            Resolve-IconPath 'ko_KR' | Should Match 'hex-launcher-kr\.ico$'
        }
    }

    Context 'drapeau absent' {
        Mock Test-Path { $false }
        It 'replie sur l''icône de base du projet' {
            Resolve-IconPath 'xx_XX' | Should Match 'ico\\hex-launcher\.ico$'
        }
    }

    Context 'icônes livrées dans app\ico' {
        It 'trouve un drapeau pour chaque langue du catalogue' {
            $catalog = Read-LocaleCatalog (Join-Path $here '..\app\locales.json')
            $missing = @($catalog.code | Where-Object { (Resolve-IconPath $_) -notmatch 'hex-launcher-[a-z]{2}\.ico$' })
            $missing -join ',' | Should Be ''
        }
    }
}

Describe 'Get-ShortcutName' {
    It 'nomme le raccourci par le pays de la langue' {
        Get-ShortcutName 'ja_JP' $null | Should Be 'League of Legends JP'
    }

    It 'ajoute l''appli compagnon au libellé' {
        Get-ShortcutName 'ja_JP' ([pscustomobject]@{ name = 'Blitz' }) | Should Be 'League of Legends JP - Blitz'
    }
}

Describe 'Get-ShortcutCombinations' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }
    $opgg  = [pscustomobject]@{ id = 'opgg'; name = 'OP.GG' }

    It 'produit un raccourci par langue sans compagnon' {
        (Get-ShortcutCombinations @('ja_JP', 'fr_FR') @() | ForEach-Object { $_.Name }) -join '|' | Should Be 'League of Legends JP|League of Legends FR'
    }

    It 'croise langues et compagnons' {
        (Get-ShortcutCombinations @('ja_JP') @($blitz, $opgg) | ForEach-Object { $_.Name }) -join '|' | Should Be 'League of Legends JP - Blitz|League of Legends JP - OP.GG'
    }

    It 'rend un tableau vide sans langue' {
        @(Get-ShortcutCombinations @() @($blitz)).Count | Should Be 0
    }
}
