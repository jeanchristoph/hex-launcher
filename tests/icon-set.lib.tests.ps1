<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon-set.lib.ps1 — découverte des jeux d'icônes par dossier.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon-set.lib.ps1')

# Racine ico\ de test : un dossier par nom, avec ou sans hex-launcher.ico
function New-TestIcoRoot([string[]]$SetsWithBase, [string[]]$FoldersWithoutBase = @()) {
    $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
    foreach ($name in $SetsWithBase) {
        $dir = New-Item -ItemType Directory -Path (Join-Path $root $name) -Force
        Set-Content -Path (Join-Path $dir.FullName 'hex-launcher.ico') -Value 'x'
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

    It 'ignore un dossier sans hex-launcher.ico (ico\companion par exemple)' {
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

    It 'voile les pastilles du jeu flat livré, pas celles de classic (fichiers livrés, toutes clés explicites)' {
        $sets = @(Get-IconSets (Join-Path $here '..\app\ico'))
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'flat')).NightVeil | Should Be $true
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'flat')).ReducedPalette | Should Be $false
        (Get-IconSetBadgeStyle (Find-IconSet $sets 'classic')).NightVeil | Should Be $false
    }
}

Describe 'Get-IconSetFilePath' {
    It 'compose le chemin d''une icône dans le dossier du jeu' {
        $set = @{ Name = 'flat'; Path = 'C:\x\ico\flat' }
        Get-IconSetFilePath $set 'hex-launcher-jp.ico' | Should Be 'C:\x\ico\flat\hex-launcher-jp.ico'
    }
}

Describe 'jeux livrés dans app\ico' {
    It 'propose flat (défaut) et classic, chacun avec les 27 drapeaux du catalogue' {
        . (Join-Path $here '..\app\lib\launch-config.lib.ps1')
        $root  = Join-Path $here '..\app\ico'
        $sets  = @(Get-IconSets $root)
        ($sets | ForEach-Object { $_.Name }) -join ',' | Should Be 'classic,flat'
        (Get-DefaultIconSet $sets).Name | Should Be 'flat'
        $codes = @(Read-JsonCatalog (Join-Path $here '..\app\locales.json') | ForEach-Object { $_.code })
        foreach ($set in $sets) {
            $missing = @($codes | Where-Object { -not (Test-Path (Get-IconSetFilePath $set "hex-launcher-$($_.Split('_')[1].ToLower()).ico")) })
            "$($set.Name): $($missing -join ',')" | Should Be "$($set.Name): "
        }
    }
}
