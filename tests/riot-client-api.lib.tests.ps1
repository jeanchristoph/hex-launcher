<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-client-api.lib.ps1 : lockfile du Riot Client, transport WinHTTP sur la boucle
    locale, attente de session et lancement d'un produit.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')
. (Join-Path $here '..\app\lib\riot-client-api.lib.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

function New-TempLockfile([string]$Content = 'Riot Client:12345:54321:mot-de-passe-secret:https') {
    return New-TempFile 'lockfile-test' $Content 'txt'
}

function New-TestLockfile([int]$Port = 54321) {
    return [pscustomobject]@{ Name = 'Riot Client'; ProcessId = '12345'; Port = $Port; Password = 'mot-de-passe-secret'; Protocol = 'https' }
}

Describe 'Read-RiotClientLockfile' {
    AfterEach { Remove-TestTempFiles }

    It 'lit le nom, le pid, le port, le mot de passe et le protocole' {
        $lockfile = Read-RiotClientLockfile (New-TempLockfile)
        $lockfile.Name      | Should Be 'Riot Client'
        $lockfile.ProcessId | Should Be '12345'
        $lockfile.Port      | Should Be 54321
        $lockfile.Password  | Should Be 'mot-de-passe-secret'
        $lockfile.Protocol  | Should Be 'https'
    }

    It 'lit un lockfile que le Riot Client garde ouvert en écriture' {
        $path = New-TempLockfile
        $held = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        try { (Read-RiotClientLockfile $path).Port | Should Be 54321 }
        finally { $held.Dispose() }
    }

    It 'rend rien avec un avertissement quand le Riot Client n''est pas lancé' {
        Mock Write-Warning {}
        Read-RiotClientLockfile 'C:\introuvable\lockfile' | Should BeNullOrEmpty
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'rend rien quand le lockfile n''a pas ses cinq champs' {
        Mock Write-Warning {}
        Read-RiotClientLockfile (New-TempLockfile 'Riot Client:12345:54321') | Should BeNullOrEmpty
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'rend rien quand le port n''est pas un nombre' {
        Mock Write-Warning {}
        Read-RiotClientLockfile (New-TempLockfile 'Riot Client:12345:port:mot-de-passe:https') | Should BeNullOrEmpty
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'reste muet pendant une attente (-Quiet)' {
        Mock Write-Warning {}
        Read-RiotClientLockfile 'C:\introuvable\lockfile' -Quiet | Should BeNullOrEmpty
        Assert-MockCalled Write-Warning -Scope It -Exactly 0
    }
}

Describe 'Get-RiotClientAuthorization' {
    It 'authentifie l''appel en Basic riot:<mot de passe du lockfile>' {
        Get-RiotClientAuthorization (New-TestLockfile) | Should Be ('Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('riot:mot-de-passe-secret')))
    }
}

Describe 'Test-HttpSuccessStatus' {
    It 'accepte les codes de succès rendus par le Riot Client' {
        Test-HttpSuccessStatus 200 | Should Be $true
        Test-HttpSuccessStatus 204 | Should Be $true
    }

    It 'refuse un refus, une route absente ou une connexion perdue' {
        Test-HttpSuccessStatus 401 | Should Be $false
        Test-HttpSuccessStatus 404 | Should Be $false
        Test-HttpSuccessStatus 500 | Should Be $false
        Test-HttpSuccessStatus 0   | Should Be $false
    }
}

Describe 'Invoke-RiotClientRequest' {
    It 'appelle l''API locale sur le port du lockfile, en HTTPS sur la boucle locale' {
        Mock Send-WinHttpRequest { return 200 }
        Invoke-RiotClientRequest -Method GET -Path '/riotclient/region-locale' -Lockfile (New-TestLockfile 4711) | Out-Null
        Assert-MockCalled Send-WinHttpRequest -Scope It -Exactly 1 -ParameterFilter { $Uri -eq 'https://127.0.0.1:4711/riotclient/region-locale' -and $Method -eq 'GET' }
    }

    It 'authentifie chaque appel avec le mot de passe du lockfile' {
        Mock Send-WinHttpRequest { return 200 }
        Invoke-RiotClientRequest -Method GET -Path '/x' -Lockfile (New-TestLockfile) | Out-Null
        Assert-MockCalled Send-WinHttpRequest -Scope It -Exactly 1 -ParameterFilter { $Authorization -eq (Get-RiotClientAuthorization (New-TestLockfile)) }
    }

    It 'transmet le corps JSON quand la requête en porte un' {
        Mock Send-WinHttpRequest { return 204 }
        Invoke-RiotClientRequest -Method POST -Path '/x' -Lockfile (New-TestLockfile) -Body '{"a":1}' | Out-Null
        Assert-MockCalled Send-WinHttpRequest -Scope It -Exactly 1 -ParameterFilter { $Body -eq '{"a":1}' }
    }

    It 'rend le succès et le code de la réponse' {
        Mock Send-WinHttpRequest { return 204 }
        $result = Invoke-RiotClientRequest -Method POST -Path '/x' -Lockfile (New-TestLockfile)
        $result.Success    | Should Be $true
        $result.StatusCode | Should Be 204
    }

    It 'rend un échec avec son code quand l''API refuse la route' {
        Mock Send-WinHttpRequest { return 404 }
        $result = Invoke-RiotClientRequest -Method POST -Path '/x' -Lockfile (New-TestLockfile)
        $result.Success    | Should Be $false
        $result.StatusCode | Should Be 404
    }

    It 'rend un échec sans lever d''exception quand la connexion n''aboutit pas' {
        Mock Send-WinHttpRequest { throw 'connexion refusée' }
        $result = Invoke-RiotClientRequest -Method POST -Path '/x' -Lockfile (New-TestLockfile)
        $result.Success    | Should Be $false
        $result.StatusCode | Should Be 0
    }
}

Describe 'Test-RiotClientRetryableStatus' {
    It 'considère comme passagers le défaut de connexion, la session verrouillée, sa libération et son éveil' {
        Test-RiotClientRetryableStatus 0   | Should Be $true
        Test-RiotClientRetryableStatus 423 | Should Be $true
        Test-RiotClientRetryableStatus 424 | Should Be $true
        Test-RiotClientRetryableStatus 464 | Should Be $true
    }

    It 'considère comme définitifs une route absente ou une autorisation refusée' {
        Test-RiotClientRetryableStatus 404 | Should Be $false
        Test-RiotClientRetryableStatus 401 | Should Be $false
        Test-RiotClientRetryableStatus 403 | Should Be $false
        Test-RiotClientRetryableStatus 500 | Should Be $false
    }
}

Describe 'Set-RiotProductLocale' {
    It 'pose la langue du produit par un PUT, la locale en corps JSON' {
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 201 } }
        (Set-RiotProductLocale -ProductId 'league_of_legends' -PatchlineId 'live' -Locale 'ja_JP' -Lockfile (New-TestLockfile)).Success | Should Be $true
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 1 -ParameterFilter {
            $Method -eq 'PUT' -and
            $Path -eq '/riotclient/product-locales/products/league_of_legends/patchlines/live' -and
            $Body -eq '"ja_JP"'
        }
    }

    It 'rend le code du refus sans bruit : c''est à la boucle de décider d''attendre ou de renoncer' {
        Mock Write-Warning {}
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $false; StatusCode = 464 } }
        $result = Set-RiotProductLocale -ProductId 'league_of_legends' -PatchlineId 'live' -Locale 'ja_JP' -Lockfile (New-TestLockfile)
        $result.StatusCode | Should Be 464
        Assert-MockCalled Write-Warning -Scope It -Exactly 0
    }
}

Describe 'Start-RiotProduct' {
    It 'demande à l''API le lancement du produit sur sa patchline' {
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
        (Start-RiotProduct -ProductId 'league_of_legends' -PatchlineId 'live' -Lockfile (New-TestLockfile)).Success | Should Be $true
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 1 -ParameterFilter { $Method -eq 'POST' -and $Path -eq '/product-launcher/v1/products/league_of_legends/patchlines/live' }
    }

    It 'rend le code du refus pour que l''appelant décide d''attendre ou de renoncer' {
        Mock Write-Warning {}
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $false; StatusCode = 464 } }
        $result = Start-RiotProduct -ProductId 'league_of_legends' -PatchlineId 'live' -Lockfile (New-TestLockfile)
        $result.StatusCode | Should Be 464
        Assert-MockCalled Write-Warning -Scope It -Exactly 0
    }
}

Describe 'Wait-RiotClientOperation' {
    AfterEach { Remove-TestTempFiles }

    It 'réussit dès que l''opération est acceptée' {
        $path = New-TempLockfile
        $script:attempts = 0
        Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $true; StatusCode = 200 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $true
        $script:attempts | Should Be 1
    }

    It 'passe le lockfile relu à chaque tour à l''opération' {
        $path = New-TempLockfile
        $script:seenPort = 0
        Wait-RiotClientOperation -Operation { param($Lockfile) $script:seenPort = $Lockfile.Port; [pscustomobject]@{ Success = $true; StatusCode = 200 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Out-Null
        $script:seenPort | Should Be 54321
    }

    It 'réessaie tant que le Riot Client répond « pas encore »' {
        $path = New-TempLockfile
        $script:attempts = 0
        Wait-RiotClientOperation -Operation {
            param($Lockfile)
            $script:attempts++
            if ($script:attempts -ge 3) { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
            return [pscustomobject]@{ Success = $false; StatusCode = 464 }
        } -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $true
        $script:attempts | Should Be 3
    }

    It 'renonce sans attendre sur un refus définitif, pour rendre la main au repli' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        $script:attempts = 0
        Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $false; StatusCode = 404 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 30 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $false
        $script:attempts | Should Be 1
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'attend le lockfile d''un Riot Client qui démarre, sans rien tenter avant' {
        Mock Write-Warning {}
        $script:attempts = 0
        Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $true; StatusCode = 200 } } `
            -FailureMessage 'essai' -LockfilePath 'C:\introuvable\lockfile' -TimeoutSeconds 1 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $false
        $script:attempts | Should Be 0
    }

    It 'renonce à l''échéance avec un avertissement' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $false; StatusCode = 464 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 1 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $false
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'qualifie un refus de l''API comme définitif' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $false; StatusCode = 404 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 30 -OnTick { }
        $result.Kind       | Should Be 'route'
        $result.StatusCode | Should Be 404
    }

    It 'qualifie de lenteur un budget épuisé sans refus — ce n''est pas une API cassée' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $false; StatusCode = 464 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 1 -OnTick { }
        $result.Kind       | Should Be 'timeout'
        $result.StatusCode | Should Be 464
    }

    It 'ne qualifie rien quand l''opération réussit' {
        $path = New-TempLockfile
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $true; StatusCode = 200 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { }
        $result.Kind | Should BeNullOrEmpty
    }

    It 'ne divulgue jamais le mot de passe du lockfile dans un avertissement' {
        $path = New-TempLockfile
        $script:captured = @()
        Mock Write-Warning { $script:captured += $Message }
        Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $false; StatusCode = 404 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 1 -OnTick { } | Out-Null
        ($script:captured -join ' ') -match 'mot-de-passe-secret' | Should Be $false
    }
}

Describe 'Wait-RiotProductLocale' {
    AfterEach { Remove-TestTempFiles }

    It 'pose la langue demandée sur le produit et sa patchline' {
        $path = New-TempLockfile
        Mock Set-RiotProductLocale { return [pscustomobject]@{ Success = $true; StatusCode = 201 } }
        Wait-RiotProductLocale -ProductId 'league_of_legends' -PatchlineId 'live' -Locale 'ja_JP' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $true
        Assert-MockCalled Set-RiotProductLocale -Scope It -Exactly 1 -ParameterFilter { $Locale -eq 'ja_JP' -and $ProductId -eq 'league_of_legends' -and $PatchlineId -eq 'live' }
    }

    It 'rend faux quand la langue reste refusée' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        Mock Set-RiotProductLocale { return [pscustomobject]@{ Success = $false; StatusCode = 404 } }
        Wait-RiotProductLocale -ProductId 'league_of_legends' -PatchlineId 'live' -Locale 'ja_JP' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $false
    }
}

Describe 'Wait-RiotProductLaunch' {
    AfterEach { Remove-TestTempFiles }

    It 'lance le produit dès que l''API l''accepte' {
        $path = New-TempLockfile
        Mock Start-RiotProduct { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
        Wait-RiotProductLaunch -ProductId 'league_of_legends' -PatchlineId 'live' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $true
        Assert-MockCalled Start-RiotProduct -Scope It -Exactly 1 -ParameterFilter { $ProductId -eq 'league_of_legends' -and $PatchlineId -eq 'live' }
    }

    It 'réessaie tant que le Riot Client n''a pas pris acte de la fermeture du client de jeu' {
        $path = New-TempLockfile
        $script:attempts = 0
        Mock Start-RiotProduct {
            $script:attempts++
            if ($script:attempts -ge 2) { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
            return [pscustomobject]@{ Success = $false; StatusCode = 424 }
        }
        Wait-RiotProductLaunch -ProductId 'league_of_legends' -PatchlineId 'live' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $true
        $script:attempts | Should Be 2
    }

    It 'rend faux quand la route de lancement a disparu' {
        $path = New-TempLockfile
        Mock Write-Warning {}
        Mock Start-RiotProduct { return [pscustomobject]@{ Success = $false; StatusCode = 404 } }
        Wait-RiotProductLaunch -ProductId 'league_of_legends' -PatchlineId 'live' -LockfilePath $path -TimeoutSeconds 30 -OnTick { } | Select-Object -ExpandProperty Success | Should Be $false
    }
}
