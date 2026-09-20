<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-client-api.lib.ps1 : lockfile du Riot Client, transport WinHTTP sur la boucle
    locale, attente de session, lancement et fermeture d'un produit.
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

    It 'journalise le chemin de substitution quand le vrai chemin porte un secret' {
        Mock Send-WinHttpRequest { return 204 }
        Mock Write-LaunchLogLine { }
        Invoke-RiotClientRequest -Method DELETE -Path '/sessions/jeton-secret' -Lockfile (New-TestLockfile) -LoggedPath '/sessions/<session>' | Out-Null
        Assert-MockCalled Send-WinHttpRequest -Scope It -Exactly 1 -ParameterFilter { $Uri -like '*/sessions/jeton-secret' }
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like '*/sessions/<session>*' -and $Detail -notlike '*jeton-secret*' }
    }
}

Describe 'Read-RiotClientResource' {
    It 'rend le corps de la réponse avec son code' {
        Mock Invoke-WinHttpRequest { return [pscustomobject]@{ Status = 200; Text = '{"a":1}' } }
        $result = Read-RiotClientResource -Path '/x' -Lockfile (New-TestLockfile 4711)
        $result.Success    | Should Be $true
        $result.StatusCode | Should Be 200
        $result.Text       | Should Be '{"a":1}'
        Assert-MockCalled Invoke-WinHttpRequest -Scope It -Exactly 1 -ParameterFilter { $Uri -eq 'https://127.0.0.1:4711/x' -and $Method -eq 'GET' }
    }

    It 'rend un échec sans corps quand la connexion n''aboutit pas' {
        Mock Invoke-WinHttpRequest { throw 'connexion interrompue' }
        $result = Read-RiotClientResource -Path '/x' -Lockfile (New-TestLockfile)
        $result.Success    | Should Be $false
        $result.StatusCode | Should Be 0
        $result.Text       | Should Be ''
    }

    It 'ne journalise jamais le corps, seulement le chemin et le code' {
        Mock Invoke-WinHttpRequest { return [pscustomobject]@{ Status = 200; Text = 'remoting-auth-token=secret' } }
        Mock Write-LaunchLogLine { }
        Read-RiotClientResource -Path '/x' -Lockfile (New-TestLockfile) | Out-Null
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like 'GET /x -> 200 *' -and $Detail -notlike '*secret*' }
    }
}

Describe 'Test-RiotClientRetryableStatus' {
    It 'considère comme passagers le défaut de connexion, un conflit, la session verrouillée, sa libération et son éveil' {
        Test-RiotClientRetryableStatus 0   | Should Be $true
        Test-RiotClientRetryableStatus 409 | Should Be $true
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

Describe 'Test-RiotClientReady' {
    It 'rend vrai quand la route de lecture répond 200' {
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
        Test-RiotClientReady ([pscustomobject]@{ Port = 1; Password = 'x' }) | Should Be $true
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 1 -ParameterFilter { $Method -eq 'GET' -and $Path -eq '/riotclient/region-locale' }
    }

    It 'rend faux sur un 404 : l''API n''est pas encore rechargée' {
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $false; StatusCode = 404 } }
        Test-RiotClientReady ([pscustomobject]@{ Port = 1; Password = 'x' }) | Should Be $false
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

$SessionsCatalog = '{"jeton-du-jeu":{"productId":"league_of_legends","patchlineId":"live","phase":"None"},"host_app":{"productId":"riot_client","phase":"None"}}'

Describe 'Find-RiotProductSession' {
    It 'relève la session du produit avec son identifiant et son objet à renvoyer tel quel' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = $SessionsCatalog } }
        $session = Find-RiotProductSession -ProductId 'league_of_legends' -Lockfile (New-TestLockfile)
        $session.Id | Should Be 'jeton-du-jeu'
        ($session.Body | ConvertFrom-Json).patchlineId | Should Be 'live'
        Assert-MockCalled Read-RiotClientResource -Scope It -Exactly 1 -ParameterFilter { $Path -eq '/product-session/v1/sessions' }
    }

    It 'rend rien quand le produit n''a pas de session — jeu fermé' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = '{"host_app":{"productId":"riot_client"}}' } }
        Find-RiotProductSession -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should BeNullOrEmpty
    }

    It 'rend rien quand l''API ne répond pas' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $false; StatusCode = 0; Text = '' } }
        Find-RiotProductSession -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should BeNullOrEmpty
    }

    It 'rend rien sans lever d''exception quand la réponse n''est pas du JSON' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = '<html>' } }
        { Find-RiotProductSession -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) } | Should Not Throw
        Find-RiotProductSession -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should BeNullOrEmpty
    }
}

Describe 'Remove-RiotProductSession' {
    $session = [pscustomobject]@{ Id = 'jeton-du-jeu'; Body = '{"productId":"league_of_legends"}' }

    It 'envoie le DELETE sur la session, son objet en corps, sans que l''identifiant aille au journal' {
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 204 } }
        (Remove-RiotProductSession -Session $session -Lockfile (New-TestLockfile)).Success | Should Be $true
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Path -eq '/product-session/v1/sessions/jeton-du-jeu' -and $Body -eq '{"productId":"league_of_legends"}' -and $LoggedPath -eq '/product-session/v1/sessions/<session>'
        }
    }
}

Describe 'Stop-RiotProduct' {
    It 'ferme le produit quand sa session existe et que le Riot Client accepte' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = $SessionsCatalog } }
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 204 } }
        Stop-RiotProduct -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should Be $true
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 1 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'rend faux sans rien envoyer quand le produit n''a pas de session' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = '{}' } }
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $true; StatusCode = 204 } }
        Stop-RiotProduct -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should Be $false
        Assert-MockCalled Invoke-RiotClientRequest -Scope It -Exactly 0
    }

    It 'rend faux quand le Riot Client refuse la fermeture' {
        Mock Read-RiotClientResource { return [pscustomobject]@{ Success = $true; StatusCode = 200; Text = $SessionsCatalog } }
        Mock Invoke-RiotClientRequest { return [pscustomobject]@{ Success = $false; StatusCode = 400 } }
        Stop-RiotProduct -ProductId 'league_of_legends' -Lockfile (New-TestLockfile) | Should Be $false
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

    It 'tient l''opération pour acquise dès que la sonde de succès le dit, sans aucune requête' {
        $path = New-TempLockfile
        $script:attempts = 0
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $false; StatusCode = 423 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } -SuccessProbe { $true }
        $result.Success | Should Be $true
        $result.Kind | Should Be 'probe'
        $script:attempts | Should Be 0
    }

    It 'arrête d''insister sur un 423 dès que la sonde voit le produit lancé (demande expirée côté client)' {
        $path = New-TempLockfile
        $script:attempts = 0
        $result = Wait-RiotClientOperation -Operation {
            param($Lockfile)
            $script:attempts++
            if ($script:attempts -eq 1) { return [pscustomobject]@{ Success = $false; StatusCode = 0 } }
            return [pscustomobject]@{ Success = $false; StatusCode = 423 }
        } -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } -SuccessProbe { $script:attempts -ge 2 }
        $result.Success | Should Be $true
        $result.Kind | Should Be 'probe'
        $result.StatusCode | Should Be 423
        $script:attempts | Should Be 2
    }

    It 'garde le comportement d''attente quand la sonde reste fausse' {
        $path = New-TempLockfile
        $script:attempts = 0
        $result = Wait-RiotClientOperation -Operation {
            param($Lockfile)
            $script:attempts++
            if ($script:attempts -ge 2) { return [pscustomobject]@{ Success = $true; StatusCode = 200 } }
            return [pscustomobject]@{ Success = $false; StatusCode = 423 }
        } -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } -SuccessProbe { $false }
        $result.Success | Should Be $true
        $result.Kind | Should Be ''
        $script:attempts | Should Be 2
    }

    It 'consulte la sonde une dernière fois quand le budget est épuisé' {
        $path = New-TempLockfile
        $script:attempts = 0
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; Start-Sleep -Milliseconds 1200; [pscustomobject]@{ Success = $false; StatusCode = 423 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 1 -OnTick { } -SuccessProbe { $script:attempts -ge 1 } 3>$null
        $result.Success | Should Be $true
        $result.Kind | Should Be 'probe'
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

    It 's''arrête sans rien tenter quand l''appelant le demande — un clic pendant l''attente prend effet tout de suite' {
        $path = New-TempLockfile
        $script:attempts = 0
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $false; StatusCode = 464 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 30 -OnTick { } -ShouldStop { $true }
        $result.Success  | Should Be $false
        $result.Kind     | Should Be 'cancelled'
        $script:attempts | Should Be 0
    }

    It 's''arrête au tour suivant quand la demande arrive pendant l''attente, en gardant le dernier code vu' {
        $path = New-TempLockfile
        $script:attempts = 0
        $script:stop = $false
        $result = Wait-RiotClientOperation -Operation { param($Lockfile) $script:attempts++; [pscustomobject]@{ Success = $false; StatusCode = 464 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 30 -OnTick { $script:stop = $true } -ShouldStop { $script:stop }
        $result.Kind       | Should Be 'cancelled'
        $result.StatusCode | Should Be 464
        $script:attempts   | Should Be 1
    }

    It 'continue comme avant sans demande d''arrêt' {
        $path = New-TempLockfile
        Wait-RiotClientOperation -Operation { param($Lockfile) [pscustomobject]@{ Success = $true; StatusCode = 200 } } `
            -FailureMessage 'essai' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } -ShouldStop { $false } | Select-Object -ExpandProperty Success | Should Be $true
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

    It 's''arrête sur demande de l''appelant' {
        $path = New-TempLockfile
        Mock Set-RiotProductLocale { return [pscustomobject]@{ Success = $false; StatusCode = 464 } }
        (Wait-RiotProductLocale -ProductId 'league_of_legends' -PatchlineId 'live' -Locale 'ja_JP' -LockfilePath $path -TimeoutSeconds 30 -OnTick { } -ShouldStop { $true }).Kind | Should Be 'cancelled'
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

    It 'transmet la sonde de succès : un produit déjà lancé n''est pas redemandé' {
        $path = New-TempLockfile
        Mock Start-RiotProduct { return [pscustomobject]@{ Success = $false; StatusCode = 423 } }
        $result = Wait-RiotProductLaunch -ProductId 'league_of_legends' -PatchlineId 'live' -LockfilePath $path -TimeoutSeconds 5 -OnTick { } -SuccessProbe { $true }
        $result.Success | Should Be $true
        $result.Kind | Should Be 'probe'
        Assert-MockCalled Start-RiotProduct -Scope It -Exactly 0
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

    It 's''arrête sur demande de l''appelant' {
        $path = New-TempLockfile
        Mock Start-RiotProduct { return [pscustomobject]@{ Success = $false; StatusCode = 464 } }
        (Wait-RiotProductLaunch -ProductId 'league_of_legends' -PatchlineId 'live' -LockfilePath $path -TimeoutSeconds 30 -OnTick { } -ShouldStop { $true }).Kind | Should Be 'cancelled'
    }
}
