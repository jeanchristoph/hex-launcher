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
        (Get-ChildItem $staging -Name | Sort-Object { $_.ToLowerInvariant() }) -join ',' | Should Be 'app,LICENSE,LISEZMOI.txt,README.fr.md,README.ja.md,README.md,setup.bat'
        Test-Path (Join-Path $staging 'app\setup.ps1') | Should Be $true
        Test-Path (Join-Path $staging 'app\lib\theme.lib.ps1') | Should Be $true
        Test-Path (Join-Path $staging 'app\config.json') | Should Be $false
        Test-Path (Join-Path $staging 'tests') | Should Be $false
    }

    It 'ne contient pas le marqueur portable avant la compilation de l''installeur' {
        Test-Path (Join-Path $staging 'app\portable.json') | Should Be $false
    }

    It 'pose le marqueur portable, JSON lisible, avant de construire le zip' {
        $marker = Add-PortableMarker $staging
        $marker | Should Be (Join-Path $staging 'app\portable.json')
        (Get-Content $marker -Raw | ConvertFrom-Json).portable | Should Be $true
    }

    It 'produit la version portable, nommée par la version' {
        $zip = New-ReleaseArchive $staging '0.0.1' (Join-Path $parent 'dist')
        (Split-Path $zip -Leaf) | Should Be 'hex-launcher-portable-0.0.1.zip'
        (Get-Item $zip).Length | Should BeGreaterThan 100000
    }

    It 'publie l''empreinte SHA-256 du zip dans les notes de release, avec la commande pour la vérifier' {
        $zip   = Join-Path $parent 'dist\hex-launcher-portable-0.0.1.zip'
        $hash  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        Get-ReleaseChecksum $zip | Should Be $hash
        $notes = Format-ReleaseNotes 'Première version' $zip
        $notes | Should Match '^Première version'
        $notes | Should Match "hex-launcher-portable-0\.0\.1\.zip.*$hash"
        $notes | Should Match 'Get-FileHash'
    }

    It 'publie une empreinte par fichier livré, installeur et zip' {
        $zip = Join-Path $parent 'dist\hex-launcher-portable-0.0.1.zip'
        $exe = Join-Path $parent 'dist\hex-launcher-setup-0.0.1.exe'
        Set-Content $exe 'installeur'
        $notes = Format-ReleaseNotes '' @($exe, $zip)
        $notes | Should Match "hex-launcher-setup-0\.0\.1\.exe``: ``$(Get-ReleaseChecksum $exe)"
        $notes | Should Match "hex-launcher-portable-0\.0\.1\.zip``: ``$(Get-ReleaseChecksum $zip)"
    }

    It 'rend des notes réduites à l''empreinte quand aucun texte n''est fourni' {
        $zip = Join-Path $parent 'dist\hex-launcher-portable-0.0.1.zip'
        (Format-ReleaseNotes '' $zip) | Should Match '^SHA-256'
    }

    It 'écrit les notes dans un fichier à côté du zip, guillemets et retours à la ligne intacts, sans BOM' {
        $zip   = Join-Path $parent 'dist\hex-launcher-portable-0.0.1.zip'
        $notes = "## Title`n`nA `"quoted`" word, then a line break.`n- item"
        $path  = Write-ReleaseNotesFile $notes $zip '0.0.1'
        (Split-Path $path -Leaf) | Should Be 'release-notes-v0.0.1.md'
        $bytes = [IO.File]::ReadAllBytes($path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should Be $false
        $written = [IO.File]::ReadAllText($path)
        $written | Should Match '^## Title'
        $written | Should Match 'A "quoted" word, then a line break\.'
        $written | Should Match "SHA-256 of ``hex-launcher-portable-0\.0\.1\.zip``"
    }

    It 'lit les notes depuis le fichier quand -NotesFile est donné, sinon prend le texte' {
        $file = Join-Path $parent 'notes.md'
        [IO.File]::WriteAllText($file, "Depuis le fichier `"avec guillemets`"", (New-Object Text.UTF8Encoding($false)))
        Read-ReleaseNotes 'texte' $file | Should Match '^Depuis le fichier "avec guillemets"'
        Read-ReleaseNotes 'texte' ''    | Should Be 'texte'
        { Read-ReleaseNotes 'texte' (Join-Path $parent 'absent.md') } | Should Throw
    }

    It 'remet les notes à gh par --notes-file, jamais en argument' {
        $zip = Join-Path $parent 'dist\hex-launcher-portable-0.0.1.zip'
        $script:ghArgs = @()
        function gh { $script:ghArgs = $args; $global:LASTEXITCODE = 0 }
        Publish-Release '0.0.1' $zip 'notes' | Should Be 'v0.0.1'
        ($script:ghArgs -join ' ') | Should Match '--notes-file '
        ($script:ghArgs -join ' ') | Should Not Match '--notes '
        ($script:ghArgs -contains 'release') | Should Be $true
    }

    Remove-Item $parent -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'New-ReleaseInstaller' {
    It 'passe la version, le dossier préparé et la sortie en définitions au script Inno Setup' {
        $arguments = Get-InstallerCompilerArguments 'C:\staging' '0.4.0' 'C:\dist'
        $arguments -contains '/DAppVersion=0.4.0' | Should Be $true
        $arguments -contains '/DSourceDir=C:\staging' | Should Be $true
        $arguments -contains '/DOutputDir=C:\dist' | Should Be $true
        $arguments[-1] | Should Match 'installer\\hex-launcher\.iss$'
        Test-Path $arguments[-1] | Should Be $true
    }

    It 'refuse de construire sans Inno Setup, en indiquant comment l''installer' {
        Mock Find-InnoSetupCompiler { $null }
        { New-ReleaseInstaller 'C:\staging' '0.4.0' (Join-Path $TestDrive 'dist') } | Should Throw 'JRSoftware.InnoSetup'
    }

    It 'signale l''échec de la compilation' {
        Mock Find-InnoSetupCompiler { 'cmd.exe' }
        function cmd.exe { $global:LASTEXITCODE = 2 }
        { New-ReleaseInstaller 'C:\staging' '0.4.0' (Join-Path $TestDrive 'dist') } | Should Throw 'code 2'
    }
}

Describe 'hex-launcher.iss' {
    $iss = Get-Content (Join-Path $ProjectRoot 'tools\installer\hex-launcher.iss') -Raw -Encoding UTF8

    It 'installe par utilisateur, sans droits administrateur, dans %LOCALAPPDATA%\Programs' {
        $iss | Should Match '(?m)^PrivilegesRequired=lowest'
        $iss | Should Match '(?m)^DefaultDirName=\{localappdata\}\\Programs\\hex-launcher'
    }

    It 'garde un AppId fixe, qui fait d''une nouvelle version une mise à jour' {
        $iss | Should Match '(?m)^AppId=\{\{C11135E5-D99E-446B-BD28-78A06332E927\}'
    }

    It 'retire les raccourcis du Bureau et du menu Démarrer à la désinstallation, par un script livré' {
        $iss | Should Match 'remove-shortcuts\.ps1'
        Test-Path (Join-Path $ProjectRoot 'app\remove-shortcuts.ps1') | Should Be $true
    }

    It 'prend le logo HL nu pour l''installeur et les images de son assistant, versionnés à côté du .iss' {
        $iss | Should Match '(?m)^SetupIconFile=installer-logo\.ico'
        $iss | Should Match '(?m)^WizardSmallImageFile=wizard-corner\.png'
        $iss | Should Match '(?m)^WizardImageFile=wizard-side\.png'
        foreach ($image in $InstallerImages) { Test-Path (Join-Path $ProjectRoot "tools\installer\$image") | Should Be $true }
    }

    It 'montre le logo HL dans « Applications installées » (celui du désinstalleur), l''engrenage restant à la configuration' {
        $iss | Should Match '(?m)^UninstallDisplayIcon=\{uninstallexe\}'
    }

    It 'pose « Hex Launcher » dans le dossier du menu Démarrer des raccourcis de jeu et retire celui de la racine (0.4.x)' {
        $iss | Should Match '(?m)^Name: "\{userprograms\}\\Hex Launcher\\Hex Launcher"; Filename: "\{app\}\\setup\.bat"'
        $iss | Should Match '(?m)^Type: files; Name: "\{userprograms\}\\Hex Launcher\.lnk"'
    }
}
