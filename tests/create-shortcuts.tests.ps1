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
