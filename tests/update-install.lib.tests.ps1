<#
.SYNOPSIS
    Tests Pester 3.4 de lib\update-install.lib.ps1 : pièce jointe, empreinte, remplacement de la copie portable,
    orchestration. Aucun appel réseau : le téléchargement lit une URL file:// locale.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\i18n.lib.ps1')
. (Join-Path $here '..\app\lib\update-install.lib.ps1')
Initialize-Translation 'fr' | Out-Null

$NoWait = { Start-Sleep -Milliseconds 10 }

function New-TestRelease([object[]]$Assets) {
    return [pscustomobject]@{ Version = '0.4.0'; PageUrl = 'https://example/v0.4.0'; Assets = $Assets }
}

function New-TestAsset([string]$Name, [string]$Path) {
    $hash = if (Test-Path $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    return [pscustomobject]@{ Name = $Name; Url = ([Uri]$Path).AbsoluteUri; Sha256 = $hash }
}

# Copie portable : setup.bat, app\ (marqueur, un script, un script retiré plus tard), data\config.json
function New-TestPortableCopy {
    $root = Join-Path $TestDrive ('portable-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'app\lib'), (Join-Path $root 'data') -Force | Out-Null
    Set-Content (Join-Path $root 'setup.bat') 'ancien'
    Set-Content (Join-Path $root 'app\portable.json') '{ "portable": true }'
    Set-Content (Join-Path $root 'app\version.txt') '0.3.2'
    Set-Content (Join-Path $root 'app\lib\retire.lib.ps1') 'périmé'
    Set-Content (Join-Path $root 'data\config.json') 'réglages'
    return $root
}

# Zip de release portable : un dossier hex-launcher-0.4.0\ avec la nouvelle version
function New-TestPortableZip {
    $staging = Join-Path $TestDrive ('staging-' + [guid]::NewGuid().ToString('N'))
    $folder  = Join-Path $staging 'hex-launcher-0.4.0'
    New-Item -ItemType Directory -Path (Join-Path $folder 'app\lib') -Force | Out-Null
    Set-Content (Join-Path $folder 'setup.bat') 'nouveau'
    Set-Content (Join-Path $folder 'app\portable.json') '{ "portable": true }'
    Set-Content (Join-Path $folder 'app\version.txt') '0.4.0'
    Set-Content (Join-Path $folder 'app\lib\nouveau.lib.ps1') 'ajouté'
    $zip = Join-Path $TestDrive ('hex-launcher-portable-' + [guid]::NewGuid().ToString('N') + '.zip')
    Compress-Archive -Path $folder -DestinationPath $zip
    return $zip
}

Describe 'Find-UpdateAsset' {
    $release = New-TestRelease @(
        [pscustomobject]@{ Name = 'hex-launcher-setup-0.4.0.exe' },
        [pscustomobject]@{ Name = 'hex-launcher-portable-0.4.0.zip' })

    It 'prend l''installeur pour une copie installée et le zip portable pour une copie portable' {
        (Find-UpdateAsset $release 'installed').Name | Should Be 'hex-launcher-setup-0.4.0.exe'
        (Find-UpdateAsset $release 'portable').Name | Should Be 'hex-launcher-portable-0.4.0.zip'
    }

    It 'échoue quand la release ne contient pas le fichier attendu' {
        { Find-UpdateAsset (New-TestRelease @()) 'installed' } | Should Throw 'hex-launcher-setup-0.4.0.exe absent'
    }
}

Describe 'Test-DownloadIntegrity' {
    $file = Join-Path $TestDrive 'fichier.bin'
    Set-Content $file 'contenu'
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()

    It 'accepte le fichier dont l''empreinte correspond au digest publié' {
        Test-DownloadIntegrity $file $hash | Should Be $true
    }

    It 'refuse un fichier altéré ou sans digest à comparer' {
        Test-DownloadIntegrity $file ('0' * 64) | Should Be $false
        Test-DownloadIntegrity $file '' | Should Be $false
    }
}

Describe 'Receive-UpdateFile' {
    It 'télécharge dans le dossier temporaire et rend le fichier vérifié' {
        $source = Join-Path $TestDrive 'source-setup.exe'
        Set-Content $source 'installeur'
        $path = Receive-UpdateFile (New-TestAsset 'hex-launcher-setup-test.exe' $source) $NoWait
        try { Get-Content $path | Should Be 'installeur' } finally { Remove-Item $path -Force }
    }

    It 'aboutit même avec une fenêtre WinForms ouverte, sans pomper sa file de messages' {
        Add-Type -AssemblyName System.Windows.Forms
        $previous = [Threading.SynchronizationContext]::Current
        [Threading.SynchronizationContext]::SetSynchronizationContext((New-Object System.Windows.Forms.WindowsFormsSynchronizationContext))
        try {
            $source = Join-Path $TestDrive 'source-winforms.exe'
            Set-Content $source 'installeur'
            $path = Receive-UpdateFile (New-TestAsset 'hex-launcher-setup-winforms.exe' $source) $NoWait
            Remove-Item $path -Force
        } finally {
            [Threading.SynchronizationContext]::SetSynchronizationContext($previous)
        }
    }

    It 'efface le fichier et échoue quand l''empreinte ne correspond pas' {
        $source = Join-Path $TestDrive 'source-altere.exe'
        Set-Content $source 'installeur'
        $asset = New-TestAsset 'hex-launcher-setup-altere.exe' $source
        $asset.Sha256 = '0' * 64
        { Receive-UpdateFile $asset $NoWait } | Should Throw 'fichier téléchargé altéré'
        Test-Path (Join-Path $env:TEMP 'hex-launcher-setup-altere.exe') | Should Be $false
    }

    It 'échoue quand le téléchargement échoue' {
        $asset = New-TestAsset 'hex-launcher-setup-absent.exe' (Join-Path $TestDrive 'absent.exe')
        { Receive-UpdateFile $asset $NoWait } | Should Throw
    }
}

Describe 'Wait-UpdateTask' {
    It 'abandonne au-delà du délai' {
        $pending = (New-Object 'System.Threading.Tasks.TaskCompletionSource[string]').Task
        { Wait-UpdateTask $pending $NoWait 0 } | Should Throw 'délai'
    }
}

Describe 'Test-FolderWritable' {
    It 'rend vrai pour un dossier modifiable, sans y laisser de trace' {
        $folder = Join-Path $TestDrive 'modifiable'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Test-FolderWritable $folder | Should Be $true
        @(Get-ChildItem $folder -Force).Count | Should Be 0
    }

    It 'rend faux quand l''écriture est impossible' {
        Test-FolderWritable (Join-Path $TestDrive 'absent\dossier') | Should Be $false
    }
}

Describe 'Install-PortableUpdate' {
    It 'remplace la copie portable et garde data\ intact' {
        $root = New-TestPortableCopy
        Install-PortableUpdate (New-TestPortableZip) $root
        Get-Content (Join-Path $root 'setup.bat') | Should Be 'nouveau'
        Get-Content (Join-Path $root 'app\version.txt') | Should Be '0.4.0'
        Test-Path (Join-Path $root 'app\lib\nouveau.lib.ps1') | Should Be $true
        Get-Content (Join-Path $root 'data\config.json') | Should Be 'réglages'
    }

    It 'efface les fichiers de app\ que la nouvelle version a retirés' {
        $root = New-TestPortableCopy
        Install-PortableUpdate (New-TestPortableZip) $root
        Test-Path (Join-Path $root 'app\lib\retire.lib.ps1') | Should Be $false
    }

    It 'refuse une archive qui ne contient pas un unique dossier de version' {
        $folder = Join-Path $TestDrive 'plat'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content (Join-Path $folder 'setup.bat') 'x'
        $zip = Join-Path $TestDrive 'plat.zip'
        Compress-Archive -Path (Join-Path $folder '*') -DestinationPath $zip
        { Install-PortableUpdate $zip (New-TestPortableCopy) } | Should Throw 'archive inattendue'
    }
}

Describe 'Install-Update' {
    $release = New-TestRelease @([pscustomobject]@{ Name = 'hex-launcher-setup-0.4.0.exe'; Url = 'x'; Sha256 = 'y' })
    $update  = @{ Release = $release; Wait = $NoWait; OnStatus = { param([string]$Text) } }
    Mock Exit-CodeFolder {}

    It 'refuse une copie source, qui ne sait pas se mettre à jour' {
        Mock Get-DistributionKind { 'source' }
        { Install-Update ($update + @{ AppRoot = 'C:\depot\app' }) } | Should Throw 'copie non installée'
    }

    It 'rend read_only pour une copie portable dans un dossier non modifiable, sans rien télécharger' {
        Mock Get-DistributionKind { 'portable' }
        Mock Test-FolderWritable { $false }
        Mock Receive-UpdateFile { throw 'ne doit pas être appelé' }
        Install-Update ($update + @{ AppRoot = 'C:\cle\app' }) | Should Be 'read_only'
    }

    It 'lance l''installeur téléchargé pour une copie installée, puis efface le fichier' {
        Mock Get-DistributionKind { 'installed' }
        Mock Receive-UpdateFile { Join-Path $TestDrive 'setup.exe' }
        Mock Install-InstallerUpdate {}
        Mock Remove-Item {}
        Install-Update ($update + @{ AppRoot = 'C:\Programs\hex-launcher\app' }) | Should Be 'installed'
        Assert-MockCalled Install-InstallerUpdate -Scope It -Exactly 1
        Assert-MockCalled Exit-CodeFolder -Scope It -Exactly 1
        Assert-MockCalled Remove-Item -Scope It -Exactly 1
    }

    It 'annonce le téléchargement puis l''installation' {
        Mock Get-DistributionKind { 'installed' }
        Mock Receive-UpdateFile { Join-Path $TestDrive 'setup.exe' }
        Mock Install-InstallerUpdate {}
        $script:statuses = @()
        $spy = @{ Release = $release; Wait = $NoWait; AppRoot = 'C:\Programs\hex-launcher\app'; OnStatus = { param([string]$Text) $script:statuses += $Text } }
        Install-Update $spy | Out-Null
        $script:statuses -join '|' | Should Be 'Téléchargement de la mise à jour 0.4.0…|Installation de la mise à jour 0.4.0…'
    }
}

Describe 'Invoke-SplashUpdate' {
    $release = New-TestRelease @()
    Mock Update-SplashStatus {}
    Mock Wait-WithAnimation {}
    $script:logged = @()
    $onLog = { param([string]$Text) $script:logged += $Text }

    It 'rend failed sans exception, affiche la raison et la journalise' {
        Mock Install-Update { throw 'installeur : code 5' }
        Invoke-SplashUpdate @{ Release = $release; AppRoot = 'C:\x\app'; Splash = 'splash'; OnLog = $onLog } | Should Be 'failed'
        Assert-MockCalled Update-SplashStatus -Scope It -ParameterFilter { $Text -eq 'Mise à jour impossible (installeur : code 5) — lancement avec la version actuelle' }
        $script:logged[-1] | Should Be 'échec : installeur : code 5'
    }

    It 'annonce la mise à jour installée' {
        Mock Install-Update { 'installed' }
        Invoke-SplashUpdate @{ Release = $release; AppRoot = 'C:\x\app'; Splash = 'splash'; OnLog = $onLog } | Should Be 'installed'
        Assert-MockCalled Update-SplashStatus -Scope It -ParameterFilter { $Text -eq 'Mise à jour installée — lancement du jeu' }
    }

    It 'montre le lien de téléchargement pour une copie portable non modifiable' {
        Mock Install-Update { 'read_only' }
        Mock Show-UpdateReadOnly {}
        Invoke-SplashUpdate @{ Release = $release; AppRoot = 'C:\x\app'; Splash = 'splash'; OnLog = $onLog } | Should Be 'read_only'
        Assert-MockCalled Show-UpdateReadOnly -Scope It -Exactly 1
    }
}
