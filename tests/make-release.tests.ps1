<#
.SYNOPSIS
    Tests Pester 3.4 de tools\make-release.ps1 — construction de l'archive dans un dossier temporaire, sans publication.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\tools\make-release.ps1')
$ProjectRoot = Split-Path $here -Parent

Describe 'Get-ReleaseVersion' {
    It 'lit la version du projet au format x.y.z' {
        Get-ReleaseVersion $ProjectRoot | Should Match '^\d+\.\d+\.\d+$'
    }

    It 'refuse une version mal formée' {
        $root = Join-Path $env:TEMP ("release-test-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'app') -Force | Out-Null
        Set-Content (Join-Path $root 'app\version.txt') 'v1'
        { Get-ReleaseVersion $root } | Should Throw
        Remove-Item $root -Recurse -Force
    }
}

Describe 'Get-ReleaseAppFiles' {
    It 'exclut config.json, propre à chaque machine' {
        $names = @(Get-ReleaseAppFiles $ProjectRoot | ForEach-Object { $_.Name })
        $names -contains 'config.json' | Should Be $false
        $names -contains 'setup.ps1' | Should Be $true
        $names -contains 'hex-launcher.ico' | Should Be $true
    }

    It 'exclut les icônes compagnon composées sur la machine (app\ico\<jeu>\companion)' {
        $root = Join-Path $env:TEMP ("release-files-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'app\ico\flat\companion') -Force | Out-Null
        Set-Content (Join-Path $root 'app\ico\flat\hex-launcher-fr.ico') 'flag'
        Set-Content (Join-Path $root 'app\ico\flat\companion\hex-launcher-fr-blitz.ico') 'composed'
        $names = @(Get-ReleaseAppFiles $root | ForEach-Object { $_.Name })
        $names -contains 'hex-launcher-fr.ico' | Should Be $true
        $names -contains 'hex-launcher-fr-blitz.ico' | Should Be $false
        Remove-Item $root -Recurse -Force
    }
}

Describe 'New-ReleaseStaging et New-ReleaseArchive' {
    $parent  = Join-Path $env:TEMP ("release-staging-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staging = New-ReleaseStaging $ProjectRoot '0.0.1' $parent

    It 'livre la racine épurée et le moteur, sans fichiers de développement' {
        (Get-ChildItem $staging -Name | Sort-Object { $_.ToLowerInvariant() }) -join ',' | Should Be 'app,Hex Launcher.lnk,LICENSE,LISEZMOI.txt,README.fr.md,README.ja.md,README.md,setup.bat'
        Test-Path (Join-Path $staging 'app\setup.ps1') | Should Be $true
        Test-Path (Join-Path $staging 'app\lib\theme.lib.ps1') | Should Be $true
        Test-Path (Join-Path $staging 'app\config.json') | Should Be $false
        Test-Path (Join-Path $staging 'tests') | Should Be $false
    }

    It 'pose un raccourci « Hex Launcher » relatif vers setup.bat, fenêtre réduite, icône engrenage relative' {
        $lnk = Join-Path $staging 'Hex Launcher.lnk'
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $shortcut.TargetPath | Should Be (Join-Path $staging 'setup.bat')
        $shortcut.IconLocation | Should Be 'app\ico\hex-launcher-setup.ico,0'
        $shortcut.WindowStyle | Should Be 7
        # MS-SHLLINK : LinkFlags à l'offset 20 — bit 3 HasRelativePath, bit 6 HasIconLocation
        $flags = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($lnk), 20)
        [bool]($flags -band 0x08) | Should Be $true
        [bool]($flags -band 0x40) | Should Be $true
    }

    It 'produit une archive zip nommée par la version' {
        $zip = New-ReleaseArchive $staging '0.0.1' (Join-Path $parent 'dist')
        (Split-Path $zip -Leaf) | Should Be 'hex-launcher-0.0.1.zip'
        (Get-Item $zip).Length | Should BeGreaterThan 100000
    }

    # La cible absolue ne doit plus exister : c'est la situation d'une archive décompressée sur un autre poste
    It 'garde un raccourci qui mène à setup.bat une fois le dossier déplacé (archive décompressée ailleurs)' {
        $moved = Join-Path $parent 'moved'
        Move-Item $staging $moved
        try {
            $link = (New-Object -ComObject Shell.Application).NameSpace($moved).ParseName('Hex Launcher.lnk').GetLink
            $link.Resolve(1)   # SLR_NO_UI
            $link.Path | Should Be (Join-Path $moved 'setup.bat')
        }
        finally { Move-Item $moved $staging }
    }

    Remove-Item $parent -Recurse -Force -ErrorAction SilentlyContinue
}
