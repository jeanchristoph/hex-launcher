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

Describe 'Read-CompanionBadges' {
    It 'indexe par identifiant les pastilles du catalogue du projet' {
        $badges = Read-CompanionBadges (Join-Path $here '..\app\companion-apps.json')
        ($badges.Keys | Sort-Object) -join ',' | Should Be 'blitz,mobalytics,opgg,porofessor'
        $badges['blitz'].glyph | Should Be 'B'
    }

    It 'rend un dictionnaire vide avec avertissement si le catalogue est illisible' {
        Mock Write-Warning {}
        $badges = Read-CompanionBadges (Join-Path $TestDrive 'absent.json')
        $badges.Count | Should Be 0
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }
}

Describe 'Get-CompanionIconPath' {
    It 'nomme l''icône composée par le pays, l''identifiant du compagnon et l''empreinte de la pastille, dans ico\companion' {
        $badge = [pscustomobject]@{ glyph = 'B'; color = '#E4103F' }
        Get-CompanionIconPath 'ja_JP' ([pscustomobject]@{ id = 'blitz' }) $badge | Should Be (Join-Path $folder "ico\companion\hex-launcher-jp-blitz-$(Get-BadgeSignature $badge).ico")
    }

    It 'change de chemin quand la pastille change, pour contourner le cache d''icônes de Windows' {
        $blitz = [pscustomobject]@{ id = 'blitz' }
        (Get-CompanionIconPath 'ja_JP' $blitz ([pscustomobject]@{ glyph = 'B'; color = '#E4103F' })) | Should Not Be (Get-CompanionIconPath 'ja_JP' $blitz ([pscustomobject]@{ glyph = 'B'; color = '#7A3FC9' }))
    }
}

Describe 'Remove-StaleCompanionIcons' {
    $companionIconFolder = Join-Path $TestDrive 'stale'
    New-Item -ItemType Directory -Path $companionIconFolder -Force | Out-Null
    $blitz = [pscustomobject]@{ id = 'blitz' }
    $keep = Join-Path $companionIconFolder 'hex-launcher-jp-blitz-e4103f.ico'
    foreach ($name in 'hex-launcher-jp-blitz-e4103f.ico', 'hex-launcher-jp-blitz-7a3fc9.ico', 'hex-launcher-jp-opgg-5383e8.ico', 'hex-launcher-fr-blitz-7a3fc9.ico') {
        Set-Content (Join-Path $companionIconFolder $name) 'x'
    }
    Remove-StaleCompanionIcons 'ja_JP' $blitz $keep

    It 'supprime les anciennes couleurs de la même combinaison langue × compagnon' {
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-blitz-7a3fc9.ico') | Should Be $false
    }

    It 'garde la variante courante et les autres combinaisons' {
        Test-Path $keep | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-opgg-5383e8.ico') | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-fr-blitz-7a3fc9.ico') | Should Be $true
    }
}

Describe 'Resolve-ShortcutIconPath' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }
    $badge = [pscustomobject]@{ glyph = 'B'; color = '#E0432B' }

    Context 'sans compagnon' {
        It 'rend l''icône drapeau seule' {
            Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null) | Should Be (Get-FlagIconPath 'ja_JP')
        }
    }

    Context 'compagnon avec pastille' {
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-CompanionBadge { param($SourceIco, $Badge, $DestinationIco) $DestinationIco }

        It 'compose drapeau + pastille dans ico\companion' {
            Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be (Get-CompanionIconPath 'ja_JP' $blitz $badge)
            Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 1 -ParameterFilter { $SourceIco -eq (Get-FlagIconPath 'ja_JP') -and $Badge.glyph -eq 'B' }
        }
    }

    Context 'compagnon sans pastille' {
        $script:CompanionBadges = @{}
        Mock Add-CompanionBadge { throw 'ne doit pas être appelé' }

        It 'garde l''icône drapeau seule sans composer' {
            Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be (Get-FlagIconPath 'ja_JP')
            Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 0
        }
    }

    Context 'échec de composition' {
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-CompanionBadge { throw 'GDI+ indisponible' }
        Mock Write-Warning {}

        It 'replie sur l''icône drapeau avec un avertissement, sans interrompre l''installation' {
            Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be (Get-FlagIconPath 'ja_JP')
            Assert-MockCalled Write-Warning -Scope It -Exactly 1
        }
    }
}

Describe 'New-LaunchShortcut avec compagnon' {
    $companionIconFolder = Join-Path $TestDrive 'companion'
    $script:CompanionBadges = Read-CompanionBadges (Join-Path $here '..\app\companion-apps.json')
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }

    It 'écrit un .lnk dont l''icône est le drapeau composé avec la pastille, en six tailles' {
        $lnk = New-LaunchShortcut (New-ShortcutCombination 'fr_FR' $blitz) $TestDrive
        $lnk | Should Exist
        $icon = $shell.CreateShortcut($lnk).IconLocation
        $icon | Should Be "$(Join-Path $companionIconFolder "hex-launcher-fr-blitz-$(Get-BadgeSignature $script:CompanionBadges['blitz']).ico"),0"
        $entries = Read-IcoEntries ($icon -replace ',0$')
        @($entries).Count | Should Be 6
        $entries | ForEach-Object { $_.Bitmap.Dispose() }
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
