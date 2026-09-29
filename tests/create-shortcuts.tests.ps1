<#
.SYNOPSIS
    Tests Pester 3.4 de app\create-shortcuts.ps1 (fonctions pures : icône, combinaisons, nommage).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\create-shortcuts.ps1')

# Les textes attendus sont français quelle que soit la langue de Windows sur la machine de test
Initialize-Translation 'fr' | Out-Null

Describe 'Get-FlagIconPath' {
    It 'dérive le nom du fichier drapeau de la partie pays du code, en minuscules' {
        Get-FlagIconPath 'ja_JP' | Should Match 'hex-launcher-jp\.ico$'
    }

    It 'cible le jeu d''icônes par défaut (ico\flat) à côté du script' {
        Get-FlagIconPath 'fr_FR' | Should Be (Join-Path $folder 'ico\flat\hex-launcher-fr.ico')
    }

    It 'suit le jeu courant après Set-ActiveIconSet' {
        Set-ActiveIconSet 'classic' | Out-Null
        try { Get-FlagIconPath 'fr_FR' | Should Be (Join-Path $folder 'ico\classic\hex-launcher-fr.ico') }
        finally { Set-ActiveIconSet '' | Out-Null }
    }
}

Describe 'Find-LocaleCodeForLanguage' {
    $catalog = @(
        [pscustomobject]@{ code = 'ja_JP' }, [pscustomobject]@{ code = 'fr_FR' },
        [pscustomobject]@{ code = 'en_US' }, [pscustomobject]@{ code = 'en_GB' }, [pscustomobject]@{ code = 'pt_BR' })

    It 'retient la première variante du catalogue pour une langue du launcher' {
        Find-LocaleCodeForLanguage $catalog 'en' | Should Be 'en_US'
        Find-LocaleCodeForLanguage $catalog 'ja' | Should Be 'ja_JP'
    }

    It 'retient la variante exacte quand la langue précise le pays' {
        Find-LocaleCodeForLanguage $catalog 'en-GB' | Should Be 'en_GB'
    }

    It 'retient la même langue d''un autre pays quand la variante exacte manque' {
        Find-LocaleCodeForLanguage $catalog 'pt-PT' | Should Be 'pt_BR'
    }

    It 'propose le français quand la langue n''a pas de voix LoL' {
        Find-LocaleCodeForLanguage $catalog 'nl' | Should Be 'fr_FR'
    }

    It 'propose le français quand la langue est vide' {
        Find-LocaleCodeForLanguage $catalog '' | Should Be 'fr_FR'
    }
}

Describe 'Get-PreselectedCodes' {
    $catalog = @(
        [pscustomobject]@{ code = 'ja_JP'; default = $true }, [pscustomobject]@{ code = 'fr_FR' },
        [pscustomobject]@{ code = 'en_US' })

    It 'pré-coche les langues marquées default et celle du launcher à la première installation' {
        Get-PreselectedCodes $catalog @() 'en' | Should Be @('ja_JP', 'en_US')
    }

    It 'pré-coche le français quand la langue du launcher est absente du catalogue' {
        Get-PreselectedCodes $catalog @() 'nl' | Should Be @('ja_JP', 'fr_FR')
    }

    It 'ne double pas une langue du launcher déjà marquée default' {
        Get-PreselectedCodes $catalog @() 'ja' | Should Be @('ja_JP')
    }

    It 'reprend les langues des raccourcis déjà posés sans ajouter celle du launcher' {
        $existing = @([pscustomobject]@{ Code = 'fr_FR' })
        Get-PreselectedCodes $catalog $existing 'en' | Should Be @('fr_FR')
    }
}

Describe 'Set-ActiveIconSet' {
    It 'replie sur le jeu par défaut avec avertissement pour un nom inconnu' {
        Mock Write-Warning {}
        (Set-ActiveIconSet 'inconnu').Name | Should Be 'flat'
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }
}

Describe 'Resolve-IconPath' {
    Context 'drapeau présent' {
        Mock Test-Path { $true }
        It 'rend l''icône drapeau de la langue' {
            Resolve-IconPath 'ko_KR' | Should Match 'hex-launcher-kr\.ico$'
        }
    }

    Context 'drapeau absent du jeu courant' {
        Mock Test-Path { $Path -match 'flat\\hex-launcher\.ico$' }
        It 'replie sur l''icône de base du jeu' {
            Resolve-IconPath 'xx_XX' | Should Match 'ico\\flat\\hex-launcher\.ico$'
        }
    }

    Context 'jeu courant incomplet' {
        Set-ActiveIconSet 'classic' | Out-Null
        Mock Test-Path { $Path -match 'flat\\hex-launcher-kr\.ico$' }
        It 'replie sur le drapeau du jeu par défaut' {
            try { Resolve-IconPath 'ko_KR' | Should Match 'ico\\flat\\hex-launcher-kr\.ico$' }
            finally { Set-ActiveIconSet '' | Out-Null }
        }
    }

    Context 'aucune icône nulle part' {
        Mock Test-Path { $false }
        It 'rend quand même le chemin de base du jeu par défaut, sans interrompre l''installation' {
            Resolve-IconPath 'xx_XX' | Should Match 'ico\\flat\\hex-launcher\.ico$'
        }
    }

    Context 'icônes livrées dans app\ico\flat' {
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
        ($badges.Keys | Sort-Object) -join ',' | Should Be 'blitz,dpm,mobalytics,opgg,porofessor'
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
    It 'nomme l''icône composée par le pays, l''identifiant du compagnon et l''empreinte de la pastille, dans ico\<jeu>\companion' {
        $badge = [pscustomobject]@{ glyph = 'B'; color = '#E4103F' }
        Get-CompanionIconPath 'ja_JP' ([pscustomobject]@{ id = 'blitz' }) $badge | Should Be (Join-Path $folder "ico\flat\companion\hex-launcher-jp-blitz-$(Get-BadgeSignature $badge).ico")
    }

    It 'suit le dossier du jeu courant' {
        $badge = [pscustomobject]@{ glyph = 'B'; color = '#E4103F' }
        Set-ActiveIconSet 'classic' | Out-Null
        try { Get-CompanionIconPath 'ja_JP' ([pscustomobject]@{ id = 'blitz' }) $badge | Should Match 'ico\\classic\\companion\\hex-launcher-jp-blitz' }
        finally { Set-ActiveIconSet '' | Out-Null }
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
    $keep = Join-Path $companionIconFolder 'hex-launcher-jp-blitz-e4103f00.ico'
    foreach ($name in 'hex-launcher-jp-blitz-e4103f00.ico', 'hex-launcher-jp-blitz-7a3fc900.ico', 'hex-launcher-jp-opgg-5383e800.ico', 'hex-launcher-fr-blitz-7a3fc900.ico') {
        Set-Content (Join-Path $companionIconFolder $name) 'x'
    }
    Remove-StaleCompanionIcons 'ja_JP' $blitz $keep

    It 'supprime les anciennes couleurs de la même combinaison langue × compagnon' {
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-blitz-7a3fc900.ico') | Should Be $false
    }

    It 'garde la variante courante et les autres combinaisons' {
        Test-Path $keep | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-opgg-5383e800.ico') | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-fr-blitz-7a3fc900.ico') | Should Be $true
    }
}

Describe 'Remove-StaleIconVariants' {
    $companionIconFolder = Join-Path $TestDrive 'stale-stacked'
    New-Item -ItemType Directory -Path $companionIconFolder -Force | Out-Null
    $keep = Join-Path $companionIconFolder 'hex-launcher-jp-0123abcd.ico'
    foreach ($name in 'hex-launcher-jp-0123abcd.ico', 'hex-launcher-jp-89ab4567.ico', 'hex-launcher-jp-blitz-89ab4567.ico', 'hex-launcher-jp-notes.ico') {
        Set-Content (Join-Path $companionIconFolder $name) 'x'
    }
    Remove-StaleIconVariants 'hex-launcher-jp' $keep

    It 'supprime les autres empreintes de la même tige' {
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-89ab4567.ico') | Should Be $false
    }

    It 'garde la variante courante, les tiges plus longues (compagnon) et les fichiers étrangers au motif' {
        Test-Path $keep | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-blitz-89ab4567.ico') | Should Be $true
        Test-Path (Join-Path $companionIconFolder 'hex-launcher-jp-notes.ico') | Should Be $true
    }
}

Describe 'Get-CombinationIconStem' {
    It 'nomme par le pays, puis l''identifiant du compagnon s''il y en a un' {
        Get-CombinationIconStem (New-ShortcutCombination 'ja_JP' $null) | Should Be 'hex-launcher-jp'
        Get-CombinationIconStem (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ id = 'blitz'; name = 'Blitz' })) | Should Be 'hex-launcher-jp-blitz'
    }

    It 'insère le pays du texte forcé entre celui des voix et le compagnon' {
        Get-CombinationIconStem (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Should Be 'hex-launcher-jp-fr'
        Get-CombinationIconStem (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ id = 'blitz'; name = 'Blitz' }) 'fr_FR') | Should Be 'hex-launcher-jp-fr-blitz'
    }
}

Describe 'Resolve-ShortcutIconPath sur un jeu externe' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }
    $badge = [pscustomobject]@{ glyph = 'B'; color = '#E0432B' }
    $exe   = 'C:\Riot Games\League of Legends\LeagueClient.exe'

    Context 'original : icône nue référencée depuis le binaire' {
        Set-ActiveIconSet 'original' | Out-Null
        $script:LeagueClientPath = $exe
        $script:CompanionBadges = @{ blitz = $badge }
        Mock Add-StackedBadgesToExecutableIcon { throw 'ne doit pas être appelé' }
        Mock Add-CompanionBadge { throw 'ne doit pas être appelé' }

        It 'rend le binaire lui-même, avec ou sans compagnon, sans rien composer' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null) | Should Be $exe
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be $exe
                Assert-MockCalled Add-StackedBadgesToExecutableIcon -Scope It -Exactly 0
                Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 0
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }

    Context 'original-badges : pastilles composées sur l''icône du binaire' {
        Set-ActiveIconSet 'original-badges' | Out-Null
        $script:LeagueClientPath = $exe
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-StackedBadgesToExecutableIcon { param($ExecutablePath, $Codes, $Badge, $DestinationIco, $Style) $DestinationIco }

        It 'compose pays + compagnon dans ico\original-badges\companion' {
            try {
                $combination = New-ShortcutCombination 'ja_JP' $blitz
                Resolve-ShortcutIconPath $combination | Should Be (Get-StackedIconPath $combination $badge)
                Get-StackedIconPath $combination $badge | Should Match 'ico\\original-badges\\companion\\hex-launcher-jp-blitz-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-StackedBadgesToExecutableIcon -Scope It -Exactly 1 -ParameterFilter { $ExecutablePath -eq $exe -and ($Codes -join ',') -eq 'ja_JP' -and $Badge.glyph -eq 'B' }
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }

        It 'compose le pays seul sans compagnon' {
            Set-ActiveIconSet 'original-badges' | Out-Null; $script:LeagueClientPath = $exe
            try {
                $combination = New-ShortcutCombination 'fr_FR' $null
                Resolve-ShortcutIconPath $combination | Should Match 'ico\\original-badges\\companion\\hex-launcher-fr-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-StackedBadgesToExecutableIcon -Scope It -Exactly 1 -ParameterFilter { ($Codes -join ',') -eq 'fr_FR' -and $null -eq $Badge }
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }

    Context 'échec de composition' {
        Set-ActiveIconSet 'original-badges' | Out-Null
        $script:LeagueClientPath = $exe
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-StackedBadgesToExecutableIcon { throw 'GDI+ indisponible' }
        Mock Write-Warning {}

        It 'replie sur l''icône officielle nue avec un avertissement, sans interrompre l''installation' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be $exe
                Assert-MockCalled Write-Warning -Scope It -Exactly 1
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }

    Context 'binaire introuvable' {
        Set-ActiveIconSet 'original' | Out-Null
        $script:LeagueClientPath = $null
        $script:CompanionBadges = @{}
        Mock Find-LeagueClientPath { $null }
        Mock Write-Warning {}

        It 'replie sur les icônes du jeu par défaut, avec un seul avertissement pour toute l''exécution' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null) | Should Match 'ico\\flat\\hex-launcher-jp\.ico$'
                Resolve-ShortcutIconPath (New-ShortcutCombination 'fr_FR' $null) | Should Match 'ico\\flat\\hex-launcher-fr\.ico$'
                Assert-MockCalled Write-Warning -Scope It -Exactly 1
                Assert-MockCalled Find-LeagueClientPath -Scope It -Exactly 1
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }
}

Describe 'Resolve-ShortcutIconPath, texte forcé' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }
    $badge = [pscustomobject]@{ glyph = 'B'; color = '#E0432B' }
    $exe   = 'C:\Riot Games\League of Legends\LeagueClient.exe'

    Context 'jeu de fichiers (flat) : deux drapeaux coupés en diagonale' {
        Set-ActiveIconSet 'flat' | Out-Null
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Remove-StaleIconVariants {}
        Mock Merge-DiagonalSplitIco { $Split.Destination }
        Mock Add-CompanionBadge { $DestinationIco }

        It 'compose drapeau des voix en haut, drapeau du texte en bas, puis la pastille compagnon' {
            try {
                $path = Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz 'fr_FR')
                $path | Should Match 'ico\\flat\\companion\\hex-launcher-jp-fr-blitz-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Merge-DiagonalSplitIco -Scope It -Exactly 1 -ParameterFilter {
                    $Split.Upper -match 'hex-launcher-jp\.ico$' -and $Split.Lower -match 'hex-launcher-fr\.ico$' -and $Split.Destination -eq $path
                }
                Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 1 -ParameterFilter { $SourceIco -eq $path -and $DestinationIco -eq $path }
            } finally { Set-ActiveIconSet '' | Out-Null }
        }

        It 'passe les deux icônes de base du jeu (fond bleu, fond vert) pour garder le logo au-dessus du trait' {
            Set-ActiveIconSet 'flat' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Out-Null
                Assert-MockCalled Merge-DiagonalSplitIco -Scope It -Exactly 1 -ParameterFilter {
                    @($Split.Foreground).Count -eq 2 -and $Split.Foreground[0] -match 'ico\\flat\\hex-launcher\.ico$' -and $Split.Foreground[1] -match 'ico\\flat\\hex-launcher-green\.ico$'
                }
            } finally { Set-ActiveIconSet '' | Out-Null }
        }

        It 'ne passe aucune icône de base quand l''icône verte manque (trait par-dessus tout)' {
            Set-ActiveIconSet 'flat' | Out-Null
            Mock Test-Path { $Path -notmatch 'hex-launcher-green\.ico$' } -ParameterFilter { $Path -match 'hex-launcher(-green)?\.ico$' }
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Out-Null
                Assert-MockCalled Merge-DiagonalSplitIco -Scope It -Exactly 1 -ParameterFilter { $null -eq $Split.Foreground }
            } finally { Set-ActiveIconSet '' | Out-Null }
        }

        It 'ne pose pas de pastille sans compagnon' {
            Set-ActiveIconSet 'flat' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Should Match 'hex-launcher-jp-fr-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 0
            } finally { Set-ActiveIconSet '' | Out-Null }
        }
    }

    Context 'échec de la composition coupée' {
        Set-ActiveIconSet 'flat' | Out-Null
        $script:CompanionBadges = @{}
        Mock New-Item {}
        Mock Remove-StaleIconVariants {}
        Mock Merge-DiagonalSplitIco { throw 'GDI+ indisponible' }
        Mock Write-Warning {}

        It 'replie sur l''icône de la langue des voix avec un avertissement' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Should Match 'ico\\flat\\hex-launcher-jp\.ico$'
                Assert-MockCalled Write-Warning -Scope It -Exactly 1
            } finally { Set-ActiveIconSet '' | Out-Null }
        }
    }

    Context 'original-badges : pastille pays coupée sur l''icône du binaire' {
        Set-ActiveIconSet 'original-badges' | Out-Null
        $script:LeagueClientPath = $exe
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-StackedBadgesToExecutableIcon { param($ExecutablePath, $Codes, $Badge, $DestinationIco, $Style) $DestinationIco }

        It 'passe les deux langues, voix d''abord, à la pastille pays' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz 'fr_FR') | Should Match 'ico\\original-badges\\companion\\hex-launcher-jp-fr-blitz-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-StackedBadgesToExecutableIcon -Scope It -Exactly 1 -ParameterFilter { ($Codes -join ',') -eq 'ja_JP,fr_FR' }
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }

    Context 'logo-badges : pastilles sur l''icône de base du jeu, sans drapeau ni binaire LoL' {
        $script:CompanionBadges = @{ blitz = $badge }
        Mock New-Item {}
        Mock Add-StackedBadgesToIco { param($SourceIco, $Codes, $Badge, $DestinationIco, $Style) $DestinationIco }
        Mock Add-StackedBadgesToExecutableIcon { throw 'ne doit pas être appelé' }
        Mock Find-LeagueClientPath { throw 'ne doit pas être appelé' }

        It 'compose la pastille pays coupée et la pastille compagnon sur hex-launcher.ico du jeu' {
            Set-ActiveIconSet 'logo-badges' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz 'fr_FR') | Should Match 'ico\\logo-badges\\companion\\hex-launcher-jp-fr-blitz-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-StackedBadgesToIco -Scope It -Exactly 1 -ParameterFilter {
                    $SourceIco -match 'ico\\logo-badges\\hex-launcher\.ico$' -and ($Codes -join ',') -eq 'ja_JP,fr_FR' -and $Badge.glyph -eq 'B'
                }
            } finally { Set-ActiveIconSet '' | Out-Null }
        }

        It 'pose la seule pastille pays sur un raccourci sans compagnon' {
            Set-ActiveIconSet 'logo-badges' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'fr_FR' $null) | Should Match 'hex-launcher-fr-[0-9a-f]{8}\.ico$'
                Assert-MockCalled Add-StackedBadgesToIco -Scope It -Exactly 1 -ParameterFilter { ($Codes -join ',') -eq 'fr_FR' -and $null -eq $Badge }
            } finally { Set-ActiveIconSet '' | Out-Null }
        }
    }

    Context 'logo-badges : composition en échec' {
        $script:CompanionBadges = @{}
        Mock New-Item {}
        Mock Add-StackedBadgesToIco { throw 'GDI+ indisponible' }
        Mock Write-Warning {}

        It 'rend l''icône de base nue avec un avertissement' {
            Set-ActiveIconSet 'logo-badges' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null) | Should Match 'ico\\logo-badges\\hex-launcher\.ico$'
                Assert-MockCalled Write-Warning -Scope It -Exactly 1
            } finally { Set-ActiveIconSet '' | Out-Null }
        }
    }

    Context 'original : icône nue' {
        Set-ActiveIconSet 'original' | Out-Null
        $script:LeagueClientPath = $exe
        Mock Merge-DiagonalSplitIco { throw 'ne doit pas être appelé' }

        It 'rend le binaire lui-même, sans rien composer' {
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Should Be $exe
            } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
        }
    }
}

Describe 'New-LaunchShortcut sur le jeu original-badges' {
    Set-ActiveIconSet 'original-badges' | Out-Null
    $companionIconFolder = Join-Path $TestDrive 'stacked'
    $script:LeagueClientPath = $powershell   # n'importe quel binaire à icône tient lieu de LeagueClient.exe
    $script:CompanionBadges = Read-CompanionBadges (Join-Path $here '..\app\companion-apps.json')
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }

    It 'écrit un .lnk dont l''icône est l''icône du binaire composée avec les deux pastilles, en six tailles' {
        try {
            $lnk = New-LaunchShortcut (New-ShortcutCombination 'ja_JP' $blitz) $TestDrive
            $icon = $shell.CreateShortcut($lnk).IconLocation
            $icon | Should Match 'stacked\\hex-launcher-jp-blitz-[0-9a-f]{8}\.ico,0$'
            $entries = Read-IcoEntries ($icon -replace ',0$')
            @($entries).Count | Should Be 6
            $entries | ForEach-Object { $_.Bitmap.Dispose() }
        } finally { Set-ActiveIconSet '' | Out-Null; $script:LeagueClientPath = $null }
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
        Mock Add-CompanionBadge { param($SourceIco, $Badge, $DestinationIco, $Style) $DestinationIco }

        It 'compose drapeau + pastille dans ico\<jeu>\companion, avec le style du jeu (flat livré sans voile)' {
            Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Should Be (Get-CompanionIconPath 'ja_JP' $blitz $badge)
            Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 1 -ParameterFilter { $SourceIco -eq (Get-FlagIconPath 'ja_JP') -and $Badge.glyph -eq 'B' -and $Style.NightVeil -eq $false }
        }

        It 'compose aux couleurs brutes du catalogue pour le jeu classic' {
            Set-ActiveIconSet 'classic' | Out-Null
            try {
                Resolve-ShortcutIconPath (New-ShortcutCombination 'ja_JP' $blitz) | Out-Null
                Assert-MockCalled Add-CompanionBadge -Scope It -Exactly 1 -ParameterFilter { $Style.NightVeil -eq $false }
            } finally { Set-ActiveIconSet '' | Out-Null }
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
        $icon | Should Be "$(Join-Path $companionIconFolder "hex-launcher-fr-blitz-$(Get-BadgeSignature $script:CompanionBadges['blitz'] (Get-ActiveBadgeStyle)).ico"),0"
        $entries = Read-IcoEntries ($icon -replace ',0$')
        @($entries).Count | Should Be 6
        $entries | ForEach-Object { $_.Bitmap.Dispose() }
    }
}

Describe 'Resolve-SetupIconPath' {
    It 'rend l''engrenage livré à la racine de ico\, commun à tous les jeux' {
        Resolve-SetupIconPath | Should Be (Join-Path $icoRoot 'hex-launcher-setup.ico')
        Resolve-SetupIconPath | Should Exist
    }

    It 'livre l''engrenage en plusieurs tailles, dont 16, 32, 48 et 256' {
        $entries = @(Read-IcoEntries (Resolve-SetupIconPath))
        try { foreach ($size in 16, 32, 48, 256) { @($entries | Where-Object { $_.Bitmap.Width -eq $size }).Count | Should Be 1 } }
        finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
    }

    Context 'engrenage absent' {
        Mock Test-Path { $Path -match 'flat\\hex-launcher\.ico$' }
        It 'replie sur l''icône de base du jeu : le raccourci a toujours une icône' {
            Resolve-SetupIconPath | Should Match 'ico\\flat\\hex-launcher\.ico$'
        }
    }
}

Describe 'New-SetupShortcut' {
    It 'écrit un .lnk vers setup.bat, dossier de travail à la racine du lanceur, fenêtre réduite' {
        $lnk = New-SetupShortcut $TestDrive
        $lnk | Should Be (Join-Path $TestDrive 'Hex Launcher.lnk')
        $lnk | Should Exist
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath | Should Be (Join-Path (Split-Path $folder -Parent) 'setup.bat')
        $shortcut.WorkingDirectory | Should Be (Split-Path $folder -Parent)
        $shortcut.WindowStyle | Should Be 7
        $shortcut.Description | Should Be 'Ouvre l''assistant de configuration de Hex Launcher'
        $shortcut.IconLocation | Should Be "$(Join-Path $icoRoot 'hex-launcher-setup.ico'),0"
    }

    It 'recrée le raccourci existant sans erreur' {
        New-SetupShortcut $TestDrive | Out-Null
        { New-SetupShortcut $TestDrive } | Should Not Throw
    }
}

Describe 'New-ShortcutWithFallback' {
    Mock Write-Warning {}

    It 'crée dans la destination quand elle accepte l''écriture' {
        $result = New-ShortcutWithFallback { param([string]$Directory) "créé dans $Directory" }
        $result | Should Be "créé dans $Destination"
        Assert-MockCalled Write-Warning -Scope It -Exactly 0
    }

    It 'replie dans le dossier du lanceur avec un avertissement quand la destination refuse' {
        $result = New-ShortcutWithFallback { param([string]$Directory) if ($Directory -eq $Destination) { throw 'accès refusé' }; "créé dans $Directory" }
        $result | Should Be "créé dans $folder"
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }
}

Describe 'Get-ShortcutName' {
    It 'nomme le raccourci par le pays de la langue' {
        (New-ShortcutCombination 'ja_JP' $null).Name | Should Be 'League of Legends JP'
    }

    It 'ajoute l''appli compagnon au libellé' {
        (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ name = 'Blitz' })).Name | Should Be 'League of Legends JP - Blitz'
    }

    It 'accole le pays du texte forcé à celui des voix par un tiret ASCII (WScript.Shell convertit les noms en ANSI)' {
        (New-ShortcutCombination 'ja_JP' $null 'fr_FR').Name | Should Be "League of Legends JP-FR"
        (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ name = 'Blitz' }) 'fr_FR').Name | Should Be "League of Legends JP-FR - Blitz"
        (New-ShortcutCombination 'ja_JP' $null 'fr_FR').Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) | Should Be -1
    }
}

Describe 'New-ShortcutCombination, texte forcé' {
    It 'ignore un texte forcé identique à la langue des voix : le raccourci reste normal' {
        $combination = New-ShortcutCombination 'fr_FR' $null 'fr_FR'
        $combination.TextCode | Should Be ''
        $combination.Name | Should Be 'League of Legends FR'
    }

    It 'garde le raccourci normal de chaque langue cochée et y ajoute le raccourci à texte forcé' {
        (Get-ShortcutCombinations @('ja_JP', 'ko_KR', 'fr_FR') @() 'fr_FR' | ForEach-Object { $_.Name }) -join '|' |
            Should Be "League of Legends JP|League of Legends JP-FR|League of Legends KR|League of Legends KR-FR|League of Legends FR"
    }

    It 'fait la paire normal + texte forcé pour chaque appli compagnon' {
        $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }
        $combinations = @(Get-ShortcutCombinations @('ja_JP') @($blitz) 'fr_FR')
        ($combinations | ForEach-Object { $_.Name }) -join '|' | Should Be 'League of Legends JP - Blitz|League of Legends JP-FR - Blitz'
        ($combinations | ForEach-Object { $_.TextCode }) -join '|' | Should Be '|fr_FR'
    }

    It 'ne crée que le raccourci normal quand la langue cochée est celle du texte' {
        @(Get-ShortcutCombinations @('fr_FR') @() 'fr_FR').Count | Should Be 1
    }
}

Describe 'Get-LauncherArguments' {
    It 'passe -TextLocale au lanceur pour un raccourci mixte' {
        Get-LauncherArguments (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ id = 'blitz'; name = 'Blitz' }) 'fr_FR') |
            Should Match '-Locale ja_JP -TextLocale fr_FR -Companion blitz$'
    }

    It 'ne passe pas -TextLocale pour un raccourci normal' {
        Get-LauncherArguments (New-ShortcutCombination 'ja_JP' $null) | Should Not Match 'TextLocale'
    }
}

Describe 'Get-ShortcutDescription' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz' }

    It 'décrit la langue des voix et celle du texte' {
        Get-ShortcutDescription (New-ShortcutCombination 'ja_JP' $null 'fr_FR') | Should Be 'Lance League of Legends en ja_JP (voix), texte en fr_FR'
    }

    It 'nomme l''appli compagnon d''un raccourci mixte' {
        Get-ShortcutDescription (New-ShortcutCombination 'ja_JP' $blitz 'fr_FR') | Should Be 'Lance League of Legends en ja_JP (voix), texte en fr_FR, avec Blitz'
    }

    It 'garde les infobulles des raccourcis normaux' {
        Get-ShortcutDescription (New-ShortcutCombination 'ja_JP' $blitz) | Should Be 'Lance League of Legends en ja_JP avec Blitz'
    }
}

Describe 'Get-ExistingLaunchShortcuts' {
    It 'relit la langue des voix, le texte forcé et le compagnon d''un raccourci posé' {
        Mock Resolve-ShortcutIconPath { Get-FlagIconPath 'ja_JP' }
        $desktop = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'bureau-mixte') -Force).FullName   # $folder appartient au script
        New-LaunchShortcut (New-ShortcutCombination 'ja_JP' ([pscustomobject]@{ id = 'blitz'; name = 'Blitz' }) 'fr_FR') $desktop | Out-Null
        New-LaunchShortcut (New-ShortcutCombination 'ko_KR' $null) $desktop | Out-Null
        $existing = @(Get-ExistingLaunchShortcuts $desktop | Sort-Object Code)
        @($existing | ForEach-Object { '{0}/{1}/{2}' -f $_.Code, $_.TextCode, $_.CompanionId }) -join ' ' | Should Be 'ja_JP/fr_FR/blitz ko_KR//'
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
