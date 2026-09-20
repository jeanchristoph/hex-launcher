<#
.SYNOPSIS
    Tests Pester 3.4 de lib\launch-state.lib.ps1 : mémoire de ce que le lanceur a appris de l'API locale.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-config.lib.ps1')
. (Join-Path $here '..\app\lib\launch-state.lib.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

function New-TempState([int]$FailureCount, [string]$Version) {
    $json = '{ "localApi": { "failureCount": ' + $FailureCount + ', "riotClientVersion": "' + $Version + '", "lastOutcome": "failure", "lastCheck": "2026-09-20T01:00:00" } }'
    return New-TempFile 'launch-state-test' $json
}

Describe 'Read-LaunchState' {
    AfterEach { Remove-TestTempFiles }

    It 'lit les échecs mémorisés et la version du Riot Client' {
        $state = Read-LaunchState (New-TempState 2 '139.0.5.4957')
        $state.localApi.failureCount      | Should Be 2
        $state.localApi.riotClientVersion | Should Be '139.0.5.4957'
        $state.localApi.lastOutcome       | Should Be 'failure'
    }

    It 'rend une mémoire neuve au premier lancement, sans fichier' {
        $state = Read-LaunchState 'C:\introuvable\launch-state.json'
        $state.localApi.failureCount      | Should Be 0
        $state.localApi.riotClientVersion | Should Be ''
    }

    It 'rend une mémoire neuve quand le fichier est corrompu' {
        $state = Read-LaunchState (New-TempFile 'launch-state-test' '{ pas du json')
        $state.localApi.failureCount | Should Be 0
    }

    It 'rend une mémoire neuve quand le fichier ne parle pas de l''API locale' {
        $state = Read-LaunchState (New-TempFile 'launch-state-test' '{ "autre": 1 }')
        $state.localApi.failureCount | Should Be 0
    }
}

Describe 'Write-LaunchState' {
    AfterEach { Remove-TestTempFiles }

    It 'enregistre la mémoire, relisible telle quelle' {
        $path = Join-Path $TestDrive 'launch-state.json'
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        Write-LaunchState $state $path | Should Be $true
        (Read-LaunchState $path).localApi.failureCount | Should Be 1
    }

    It 'ne fait jamais échouer un lancement quand le dossier refuse l''écriture' {
        Mock Write-Warning {}
        Mock Write-JsonFile { throw 'accès refusé' }
        Write-LaunchState (New-LaunchState) 'C:\interdit\launch-state.json' | Should Be $false
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }
}

Describe 'Get-RiotClientVersion' {
    It 'rend une chaîne vide quand le binaire est introuvable, sans lever d''exception' {
        Get-RiotClientVersion 'C:\introuvable\RiotClientServices.exe' | Should Be ''
    }

    It 'lit la version du binaire présent sur le disque' {
        $version = Get-RiotClientVersion (Join-Path $env:SystemRoot 'System32\notepad.exe')
        $version | Should Not BeNullOrEmpty
    }
}

Describe 'Test-LocalApiWorthTrying' {
    It 'tente l''API au premier lancement, sans rien en mémoire' {
        Test-LocalApiWorthTrying (New-LaunchState) '139.0.5.4957' | Should Be $true
    }

    It 'tente encore après un seul échec — le premier peut être un hasard' {
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        Test-LocalApiWorthTrying $state '139.0.5.4957' | Should Be $true
    }

    It 'renonce à l''API après deux échecs consécutifs sur la même version de Riot' {
        $state = Update-LocalApiOutcome (Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        $state.localApi.failureCount | Should Be 2
        Test-LocalApiWorthTrying $state '139.0.5.4957' | Should Be $false
    }

    It 'retente dès que le Riot Client change de version — une mise à jour peut réparer son API' {
        $state = Update-LocalApiOutcome (Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        Test-LocalApiWorthTrying $state '140.0.1.1000' | Should Be $true
    }

    It 'retente aussi quand la version du Riot Client est illisible' {
        $state = Update-LocalApiOutcome (Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        Test-LocalApiWorthTrying $state '' | Should Be $true
    }
}

Describe 'Update-LocalApiOutcome' {
    It 'efface les échecs dès que l''API refonctionne' {
        $failed = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        $healed = Update-LocalApiOutcome $failed $true '139.0.5.4957' $null
        $healed.localApi.failureCount | Should Be 0
        $healed.localApi.lastOutcome  | Should Be 'success'
    }

    It 'cumule les échecs de la même version' {
        $state = Update-LocalApiOutcome (Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        $state.localApi.failureCount | Should Be 2
    }

    It 'repart de zéro sur une nouvelle version : les échecs d''une version ne condamnent pas la suivante' {
        $old = Update-LocalApiOutcome (Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')) $false '139.0.5.4957' (New-LocalApiFailure 'silent' 200 'game-client')
        $new = Update-LocalApiOutcome $old $false '140.0.1.1000' (New-LocalApiFailure 'silent' 200 'game-client')
        $new.localApi.failureCount      | Should Be 1
        $new.localApi.riotClientVersion | Should Be '140.0.1.1000'
    }

    It 'horodate chaque verdict' {
        (Update-LocalApiOutcome (New-LaunchState) $true '139.0.5.4957' $null).localApi.lastCheck | Should Not BeNullOrEmpty
    }
}

Describe 'Get-LocalApiFailureThreshold' {
    It 'renonce dès le premier refus de l''API — insister n''y changerait rien' {
        Get-LocalApiFailureThreshold 'route' | Should Be 1
    }

    It 'laisse deux chances à un lancement resté sans effet' {
        Get-LocalApiFailureThreshold 'silent' | Should Be 2
    }

    It 'tolère cinq lenteurs : une machine lente n''est pas une API cassée' {
        Get-LocalApiFailureThreshold 'timeout' | Should Be 5
    }

    It 'retombe sur deux pour une cause inconnue' {
        Get-LocalApiFailureThreshold 'autre' | Should Be 2
        Get-LocalApiFailureThreshold ''      | Should Be 2
    }
}

Describe 'Test-LocalApiWorthTrying, seuil selon la cause' {
    It 'renonce après un seul refus de route' {
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'route' 404 'launch')
        Test-LocalApiWorthTrying $state '139.0.5.4957' | Should Be $false
    }

    It 'continue après quatre lenteurs, et renonce à la cinquième' {
        $state = New-LaunchState
        1..4 | ForEach-Object { $state = Update-LocalApiOutcome $state $false '139.0.5.4957' (New-LocalApiFailure 'timeout' 464 'launch') }
        Test-LocalApiWorthTrying $state '139.0.5.4957' | Should Be $true
        $state = Update-LocalApiOutcome $state $false '139.0.5.4957' (New-LocalApiFailure 'timeout' 464 'launch')
        Test-LocalApiWorthTrying $state '139.0.5.4957' | Should Be $false
    }

    It 'repart de zéro quand la cause change : une lenteur ne s''ajoute pas à un refus' {
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'timeout' 464 'launch')
        $state = Update-LocalApiOutcome $state $false '139.0.5.4957' (New-LocalApiFailure 'route' 404 'launch')
        $state.localApi.failureCount | Should Be 1
        $state.localApi.failureKind  | Should Be 'route'
    }

    It 'garde le code et l''étape du dernier échec pour le support' {
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'route' 401 'locale')
        $state.localApi.failureStatusCode | Should Be 401
        $state.localApi.failureStage      | Should Be 'locale'
    }

    It 'oublie la cause dès que l''API refonctionne' {
        $state = Update-LocalApiOutcome (New-LaunchState) $false '139.0.5.4957' (New-LocalApiFailure 'route' 404 'launch')
        $state = Update-LocalApiOutcome $state $true '139.0.5.4957' $null
        $state.localApi.failureKind       | Should BeNullOrEmpty
        $state.localApi.failureStatusCode | Should Be 0
    }
}
