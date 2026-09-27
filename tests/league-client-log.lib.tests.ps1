<#
.SYNOPSIS
    Tests Pester 3.4 de lib\league-client-log.lib.ps1 — vérification d'installation du client LoL lue dans son journal.

.DESCRIPTION
    Journaux factices sous TestDrive, extraits des lignes réelles du client (21 → 27/09/2026).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')
. (Join-Path $here '..\app\lib\riot-client-api.lib.ps1')
. (Join-Path $here '..\app\lib\league-client-log.lib.ps1')

$LoginLine    = '000009.306| ALWAYS|           rcp-be-lol-login| Login complete.'
$UpToDateLine = '000012.311|   OKAY|           rcp-be-lol-patch| Patcher Install is up to date'
$RepairedLine = '000015.307|   OKAY|           rcp-be-lol-patch| Patcher Game update successful'
$VerifyLine   = '000011.038|   OKAY|           rcp-be-lol-patch| Patcher Performing install verification'
$FailedLine   = '000014.058|  ERROR|           rcp-be-lol-login| LCE-7FD7BA4B - UNSPECIFIED_ERROR - ID_TOKEN_INVALID_FORMAT'

# Dossier de jeu factice avec un journal de session créé à l'heure donnée
function New-TestLeagueWithLog([datetime]$Created, [string[]]$Lines, [string]$Name = '2026-09-27T13-18-14_5004_LeagueClient.log') {
    $league = Join-Path $TestDrive ('League ' + [Guid]::NewGuid().ToString('N'))
    $logs = New-Item -ItemType Directory -Path (Join-Path $league 'Logs\LeagueClient Logs') -Force
    $path = Join-Path $logs.FullName $Name
    Set-Content -Path $path -Value $Lines -Encoding UTF8
    (Get-Item $path).CreationTime = $Created
    return $league
}

Describe 'Test-LeagueClientVerified' {
    It 'reconnaît une session vérifiée et connectée (installation conforme)' {
        Test-LeagueClientVerified (@($LoginLine, $VerifyLine, $UpToDateLine) -join "`n") | Should Be $true
    }

    It 'reconnaît une session vérifiée après réparation' {
        Test-LeagueClientVerified (@($LoginLine, $VerifyLine, $RepairedLine) -join "`n") | Should Be $true
    }

    It 'attend tant que la vérification est seulement commencée' {
        Test-LeagueClientVerified (@($LoginLine, $VerifyLine) -join "`n") | Should Be $false
    }

    It 'refuse une session dont la connexion a échoué, même réparée (essai du 2026-09-27)' {
        Test-LeagueClientVerified (@($VerifyLine, $FailedLine, $RepairedLine) -join "`n") | Should Be $false
    }

    It 'refuse un journal vide ou absent' {
        Test-LeagueClientVerified '' | Should Be $false
        Test-LeagueClientVerified $null | Should Be $false
    }
}

Describe 'Find-LeagueClientSessionLog' {
    It 'rend le journal de la session ouverte depuis la demande de lancement' {
        $since  = Get-Date '2026-09-27 13:18:00'
        $league = New-TestLeagueWithLog $since.AddSeconds(14) @($LoginLine)
        Find-LeagueClientSessionLog $league $since | Should Match '_LeagueClient\.log$'
    }

    It 'ignore le journal d''une session antérieure' {
        $since  = Get-Date '2026-09-27 13:18:00'
        $league = New-TestLeagueWithLog $since.AddMinutes(-5) @($LoginLine, $UpToDateLine)
        Find-LeagueClientSessionLog $league $since | Should BeNullOrEmpty
    }

    It 'rend null sans dossier de journaux' {
        Find-LeagueClientSessionLog (Join-Path $TestDrive 'absent') (Get-Date) | Should BeNullOrEmpty
    }
}

Describe 'Test-LeagueClientSessionVerified' {
    It 'lit le journal de la session courante' {
        $since  = Get-Date '2026-09-27 13:18:00'
        Test-LeagueClientSessionVerified (New-TestLeagueWithLog $since.AddSeconds(14) @($LoginLine, $VerifyLine, $UpToDateLine)) $since | Should Be $true
        Test-LeagueClientSessionVerified (New-TestLeagueWithLog $since.AddSeconds(14) @($LoginLine, $VerifyLine)) $since | Should Be $false
    }

    It 'ne se fie pas à la vérification d''une session antérieure' {
        $since = Get-Date '2026-09-27 13:18:00'
        Test-LeagueClientSessionVerified (New-TestLeagueWithLog $since.AddMinutes(-5) @($LoginLine, $UpToDateLine)) $since | Should Be $false
    }
}

Describe 'Wait-LeagueClientVerification' {
    Mock Write-LaunchLogLine { $true }

    Context 'vérification constatée au troisième tour' {
        It 'rend vrai dès que le journal la montre' {
            $script:polls = 0
            Mock Test-LeagueClientSessionVerified { $script:polls++; $script:polls -ge 3 }
            Wait-LeagueClientVerification ([pscustomobject]@{ LeagueFolder = 'C:\LoL'; Since = (Get-Date); OnTick = { }; ShouldStop = $null }) | Should Be $true
            $script:polls | Should Be 3
        }
    }

    Context 'vérification jamais constatée' {
        It 'rend faux à l''échéance' {
            $LeagueClientVerificationTimeoutSeconds = 0
            Mock Test-LeagueClientSessionVerified { $false }
            Wait-LeagueClientVerification ([pscustomobject]@{ LeagueFolder = 'C:\LoL'; Since = (Get-Date); OnTick = { }; ShouldStop = $null }) | Should Be $false
        }
    }

    Context 'croix du splash' {
        It 'rend faux sur demande d''arrêt' {
            Mock Test-LeagueClientSessionVerified { $false }
            Wait-LeagueClientVerification ([pscustomobject]@{ LeagueFolder = 'C:\LoL'; Since = (Get-Date); OnTick = { }; ShouldStop = { $true } }) | Should Be $false
        }
    }
}
