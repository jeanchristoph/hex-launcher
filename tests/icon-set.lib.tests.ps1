<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon-set.lib.ps1 — découverte des jeux d'icônes par dossier.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon-set.lib.ps1')

# Racine ico\ de test : un dossier par nom, avec hex-launcher.ico, avec icon-source.json (jeu externe), ou vide
function New-TestIcoRoot([string[]]$SetsWithBase, [string[]]$FoldersWithoutBase = @(), [string[]]$ExternalSets = @()) {
    $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
    foreach ($name in $SetsWithBase) {
        $dir = New-Item -ItemType Directory -Path (Join-Path $root $name) -Force
        Set-Content -Path (Join-Path $dir.FullName 'hex-launcher.ico') -Value 'x'
    }
    foreach ($name in $ExternalSets) {
        $dir = New-Item -ItemType Directory -Path (Join-Path $root $name) -Force
        Set-Content -Path (Join-Path $dir.FullName 'icon-source.json') -Value '{ "source": "league-client", "badges": true }' -Encoding UTF8
    }
    foreach ($name in $FoldersWithoutBase) { New-Item -ItemType Directory -Path (Join-Path $root $name) -Force | Out-Null }
    return $root
}

Describe 'Get-IconSets' {
    It 'liste un jeu par sous-dossier contenant hex-launcher.ico, nommé par le dossier, trié par nom' {
        $root = New-TestIcoRoot @('flat', 'classic')
        $sets = @(Get-IconSets $root)
        ($sets | ForEach-Object { $_.Name }) -join ',' | Should Be 'classic,flat'
        $sets[1].Path | Should Be (Join-Path $root 'flat')
    }

    It 'liste aussi un jeu externe, reconnu par icon-source.json sans aucun .ico' {
        $root = New-TestIcoRoot @('flat') @() @('original')
        (@(Get-IconSets $root) | ForEach-Object { $_.Name }) -join ',' | Should Be 'flat,original'
    }

    It 'ignore un dossier sans hex-launcher.ico ni icon-source.json (ico\companion par exemple)' {
        $root = New-TestIcoRoot @('flat') @('companion')
        @(Get-IconSets $root).Count | Should Be 1
    }

    It 'rend une liste vide sans racine ni jeu' {
        @(Get-IconSets (Join-Path $TestDrive 'absent')).Count | Should Be 0
        @(Get-IconSets (New-TestIcoRoot @())).Count | Should Be 0
    }
}

Describe 'Get-DefaultIconSet' {
    It 'préfère le jeu flat' {
        (Get-DefaultIconSet @(Get-IconSets (New-TestIcoRoot @('classic', 'flat', 'zz')))).Name | Should Be 'flat'
    }

    It 'replie sur le premier jeu par ordre alphabétique sans flat' {
        (Get-DefaultIconSet @(Get-IconSets (New-TestIcoRoot @('retro', 'classic')))).Name | Should Be 'classic'
    }

    It 'rend null sans aucun jeu' {
        Get-DefaultIconSet @() | Should BeNullOrEmpty
    }
}

Describe 'Resolve-IconSet' {
    It 'rend le jeu demandé quand il existe' {
        (Resolve-IconSet (New-TestIcoRoot @('flat', 'classic')) 'classic').Name | Should Be 'classic'
    }

    It 'replie sur le jeu par défaut avec avertissement quand le nom est inconnu' {
        Mock Write-Warning {}
        (Resolve-IconSet (New-TestIcoRoot @('flat', 'classic')) 'inconnu').Name | Should Be 'flat'
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'rend le jeu par défaut sans nom demandé, sans avertissement' {
        Mock Write-Warning {}
        (Resolve-IconSet (New-TestIcoRoot @('flat', 'classic')) '').Name | Should Be 'flat'
        Assert-MockCalled Write-Warning -Scope It -Exactly 0
    }
}

Describe 'Get-IconSetBadgeStyle' {
    function New-TestSet([string]$Content) {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))) -Force
        if ($null -ne $Content) { Set-Content -Path (Join-Path $dir.FullName 'badge-style.json') -Value $Content -Encoding UTF8 }
        return @{ Name = 'x'; Path = $dir.FullName }
    }

    It 'lit nightVeil et reducedPalette dans badge-style.json' {
        $style = Get-IconSetBadgeStyle (New-TestSet '{ "nightVeil": true, "reducedPalette": true }')
        $style.NightVeil | Should Be $true
        $style.ReducedPalette | Should Be $true
        (Get-IconSetBadgeStyle (New-TestSet '{ "nightVeil": false }')).NightVeil | Should Be $false
    }

    It 'rend brut sans fichier, sans jeu, ou sans les clés' {
        (Get-IconSetBadgeStyle (New-TestSet $null)).NightVeil | Should Be $false
        (Get-IconSetBadgeStyle $null).ReducedPalette | Should Be $false
        $empty = Get-IconSetBadgeStyle (New-TestSet '{ }')
        $empty.NightVeil | Should Be $false
        $empty.ReducedPalette | Should Be $false
    }

    It 'rend brut avec avertissement sur un fichier illisible' {
        Mock Write-Warning {}
        (Get-IconSetBadgeStyle (New-TestSet '{ pas du json')).NightVeil | Should Be $false
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'ne voile plus les pastilles des jeux livrés (fichiers livrés, toutes clés explicites)' {
        $sets = @(Get-IconSets (Join-Path $here '..\app\ico'))
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'flat')).NightVeil | Should Be $false
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'flat')).ReducedPalette | Should Be $false
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'classic')).NightVeil | Should Be $false
    }
}

Describe 'Get-IconSetSource' {
    # $Content non typé : un [string] transformerait $null en chaîne vide et écrirait un marqueur vide
    function New-TestSet($Content) {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))) -Force
        if ($null -ne $Content) { Set-Content -Path (Join-Path $dir.FullName 'icon-source.json') -Value $Content -Encoding UTF8 }
        return @{ Name = 'x'; Path = $dir.FullName }
    }

    It 'lit la source league-client et le choix des pastilles' {
        $source = Get-IconSetSource (New-TestSet '{ "source": "league-client", "badges": true }')
        $source.Source | Should Be 'league-client'
        $source.Badges | Should Be $true
        (Get-IconSetSource (New-TestSet '{ "source": "league-client" }')).Badges | Should Be $false
    }

    It 'rend null pour un jeu de fichiers, sans jeu, ou sans marqueur' {
        Get-IconSetSource (New-TestSet $null) | Should BeNullOrEmpty
        Get-IconSetSource $null | Should BeNullOrEmpty
        Test-IconSetExternal (New-TestSet $null) | Should Be $false
    }

    It 'rend null avec avertissement sur un marqueur illisible ou une source inconnue' {
        Mock Write-Warning {}
        Get-IconSetSource (New-TestSet '{ pas du json') | Should BeNullOrEmpty
        Get-IconSetSource (New-TestSet '{ "source": "autre-chose", "badges": true }') | Should BeNullOrEmpty
        Assert-MockCalled Write-Warning -Scope It -Exactly 2
    }

    It 'reconnaît les deux jeux externes livrés : original nu, original-badges avec pastilles' {
        $sets = @(Get-IconSets (Join-Path $here '..\app\ico'))
        (Get-IconSetSource (Find-IconSet $sets 'original')).Badges | Should Be $false
        (Get-IconSetSource (Find-IconSet $sets 'original-badges')).Badges | Should Be $true
        Test-IconSetExternal (Find-IconSet $sets 'flat') | Should Be $false
    }
}

Describe 'Get-IconSetFilePath' {
    It 'compose le chemin d''une icône dans le dossier du jeu' {
        $set = @{ Name = 'flat'; Path = 'C:\x\ico\flat' }
        Get-IconSetFilePath $set 'hex-launcher-jp.ico' | Should Be 'C:\x\ico\flat\hex-launcher-jp.ico'
    }
}

Describe 'jeux livrés dans app\ico' {
    It 'propose flat (défaut), classic, original et original-badges ; les jeux de fichiers ont les 27 drapeaux du catalogue' {
        . (Join-Path $here '..\app\lib\launch-config.lib.ps1')
        $root  = Join-Path $here '..\app\ico'
        $sets  = @(Get-IconSets $root)
        ($sets | ForEach-Object { $_.Name }) -join ',' | Should Be 'classic,flat,original,original-badges'
        (Get-DefaultIconSet $sets).Name | Should Be 'flat'
        $codes = @(Read-JsonCatalog (Join-Path $here '..\app\locales.json') | ForEach-Object { $_.code })
        foreach ($set in @($sets | Where-Object { -not (Test-IconSetExternal $_) })) {
            $missing = @($codes | Where-Object { -not (Test-Path (Get-IconSetFilePath $set "hex-launcher-$($_.Split('_')[1].ToLower()).ico")) })
            "$($set.Name): $($missing -join ',')" | Should Be "$($set.Name): "
        }
    }
}
