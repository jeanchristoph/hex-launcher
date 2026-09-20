<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-install.lib.ps1 — Riot Client et LeagueClient.exe lus dans RiotClientInstalls.json.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\riot-install.lib.ps1')

# Un RiotClientInstalls.json de test, tel que Riot l'écrit (chemins en barres obliques)
function New-TestInstalls([string]$Content) {
    $path = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N') + '.json')
    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

Describe 'Find-RiotClientPath' {
    It 'rend rc_live en chemin Windows quand il existe' {
        $RiotInstallsPath = New-TestInstalls '{ "rc_live": "C:/Riot Games/Riot Client/RiotClientServices.exe", "rc_default": "D:/autre/RiotClientServices.exe" }'
        Mock Test-Path { $Path -eq $RiotInstallsPath -or $Path -like 'C:/Riot Games/*' }
        Find-RiotClientPath | Should Be 'C:\Riot Games\Riot Client\RiotClientServices.exe'
    }

    It 'replie sur rc_default quand rc_live manque sur le disque' {
        $RiotInstallsPath = New-TestInstalls '{ "rc_live": "C:/absent/RiotClientServices.exe", "rc_default": "D:/autre/RiotClientServices.exe" }'
        Mock Test-Path { $Path -eq $RiotInstallsPath -or $Path -like 'D:/autre/*' }
        Find-RiotClientPath | Should Be 'D:\autre\RiotClientServices.exe'
    }

    It 'rend le chemin par défaut sans fichier ni candidat valide' {
        $RiotInstallsPath = Join-Path $TestDrive 'absent.json'
        Find-RiotClientPath | Should Be $RiotClientDefault
        $RiotInstallsPath = New-TestInstalls '{ "rc_live": "C:/absent/RiotClientServices.exe" }'
        Find-RiotClientPath | Should Be $RiotClientDefault
    }

    It 'rend le chemin par défaut sur un fichier illisible' {
        $RiotInstallsPath = New-TestInstalls '{ pas du json'
        Find-RiotClientPath | Should Be $RiotClientDefault
    }
}

Describe 'Find-LeagueClientPath' {
    It 'trouve LeagueClient.exe dans le dossier de jeu déclaré par associated_client' {
        $game = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'League of Legends') -Force
        Set-Content -Path (Join-Path $game.FullName 'LeagueClient.exe') -Value 'x'
        $declared = $game.FullName -replace '\\', '/'
        $RiotInstallsPath = New-TestInstalls "{ `"associated_client`": { `"$declared/`": `"C:/Riot Games/Riot Client/RiotClientServices.exe`" } }"
        Find-LeagueClientPath | Should Be (Join-Path $game.FullName 'LeagueClient.exe')
    }

    It 'ignore un dossier déclaré qui ne contient plus le binaire' {
        $RiotInstallsPath = New-TestInstalls "{ `"associated_client`": { `"$(($TestDrive -replace '\\', '/'))/disparu/`": `"x`" } }"
        Find-LeagueClientPath | Should BeNullOrEmpty
    }

    It 'rend null sans fichier, sans associated_client ou sans dossier' {
        $RiotInstallsPath = Join-Path $TestDrive 'absent.json'
        Find-LeagueClientPath | Should BeNullOrEmpty
        $RiotInstallsPath = New-TestInstalls '{ "rc_live": "C:/Riot Games/Riot Client/RiotClientServices.exe" }'
        Find-LeagueClientPath | Should BeNullOrEmpty
        $RiotInstallsPath = New-TestInstalls '{ "associated_client": { } }'
        Find-LeagueClientPath | Should BeNullOrEmpty
    }
}
