<#
.SYNOPSIS
    Tests Pester 3.4 de lib\app-data.lib.ps1 : dossier des données, mode portable et reprise d'une version antérieure.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\app-data.lib.ps1')

function New-TestAppRoot([switch]$Portable) {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $app  = Join-Path $root 'app'
    New-Item -ItemType Directory -Path $app -Force | Out-Null
    if ($Portable) { Set-Content (Join-Path $app $PortableMarkerFileName) '{}' }
    return $app
}

Describe 'Get-AppDataFolder' {
    It 'range les données dans %LOCALAPPDATA%\hex-launcher pour une version installée' {
        $app = New-TestAppRoot
        Get-AppDataFolder $app | Should Be (Join-Path $env:LOCALAPPDATA 'hex-launcher')
    }

    It 'range les données dans data\ à côté de setup.bat pour une version portable' {
        $app = New-TestAppRoot -Portable
        Get-AppDataFolder $app | Should Be (Join-Path (Split-Path $app -Parent) 'data')
    }
}

Describe 'Get-DistributionKind' {
    It 'reconnaît la version portable à son marqueur' {
        Get-DistributionKind (New-TestAppRoot -Portable) | Should Be 'portable'
    }

    It 'reconnaît la version installée au désinstalleur d''Inno Setup' {
        $app = New-TestAppRoot
        Set-Content (Join-Path (Split-Path $app -Parent) 'unins000.exe') 'x'
        Get-DistributionKind $app | Should Be 'installed'
    }

    It 'traite tout le reste comme une copie source (dépôt, zip d''avant la 0.4.0)' {
        Get-DistributionKind (New-TestAppRoot) | Should Be 'source'
    }
}

Describe 'Get-AppDataFilePath / Get-CompanionIconFolder' {
    It 'place config.json dans le dossier des données, jamais dans app\' {
        $app = New-TestAppRoot -Portable
        Get-AppDataFilePath $app 'config.json' | Should Be (Join-Path (Split-Path $app -Parent) 'data\config.json')
    }

    It 'sépare les icônes composées par jeu d''icônes' {
        $app = New-TestAppRoot -Portable
        Get-CompanionIconFolder $app 'flat' | Should Be (Join-Path (Split-Path $app -Parent) 'data\icons\flat\companion')
    }
}

Describe 'Initialize-AppDataFolder' {
    It 'crée le dossier des données et le rend' {
        $app = New-TestAppRoot -Portable
        $folder = Initialize-AppDataFolder $app
        Test-Path $folder | Should Be $true
    }

    It 'reprend config.json et launch.log laissés dans app\ par une version antérieure' {
        $app = New-TestAppRoot -Portable
        Set-Content (Join-Path $app 'config.json') 'ancien'
        Set-Content (Join-Path $app 'launch.log') 'trace'
        $folder = Initialize-AppDataFolder $app
        Get-Content (Join-Path $folder 'config.json') | Should Be 'ancien'
        Test-Path (Join-Path $folder 'launch.log') | Should Be $true
        Test-Path (Join-Path $app 'config.json') | Should Be $false
    }

    It 'n''écrase jamais un config.json déjà présent dans le dossier des données' {
        $app = New-TestAppRoot -Portable
        $folder = Initialize-AppDataFolder $app
        Set-Content (Join-Path $folder 'config.json') 'actuel'
        Set-Content (Join-Path $app 'config.json') 'ancien'
        Initialize-AppDataFolder $app | Out-Null
        Get-Content (Join-Path $folder 'config.json') | Should Be 'actuel'
    }

    It 'ne fait rien sans fichier d''une version antérieure' {
        $app = New-TestAppRoot -Portable
        $folder = Initialize-AppDataFolder $app
        @(Get-ChildItem $folder).Count | Should Be 0
    }
}

Describe 'Move-LegacyAppDataFile' {
    It 'copie quand le déplacement échoue (dossier du code en lecture seule)' {
        $app = New-TestAppRoot -Portable
        $source = Join-Path $app 'config.json'
        $destination = Join-Path $TestDrive 'copie-config.json'
        Set-Content $source 'ancien'
        Mock Move-Item { throw 'accès refusé' }
        Move-LegacyAppDataFile $source $destination | Should Be $true
        Get-Content $destination | Should Be 'ancien'
    }

    It 'avertit sans échouer quand ni le déplacement ni la copie ne passent' {
        $app = New-TestAppRoot -Portable
        $source = Join-Path $app 'config.json'
        Set-Content $source 'ancien'
        Mock Move-Item { throw 'accès refusé' }
        Mock Copy-Item { throw 'disque plein' }
        Mock Write-Warning {}
        Move-LegacyAppDataFile $source (Join-Path $TestDrive 'x.json') | Should Be $false
        Assert-MockCalled Write-Warning -Exactly 1 -Scope It
    }
}
