<#
.SYNOPSIS
    Tests Pester 3.4 de launch-lol.ps1 : fonctions pures du lanceur (libellé de langue, réécriture de la locale,
    process fermés, lancement du Riot Client et de l'appli compagnon).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\launch-lol.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

# Yaml de test au format Riot : settings.locale est la seule ligne que le lanceur doit réécrire
function New-TempProductSettings([string]$Locale = 'en_GB') {
    $yaml = @"
product_settings:
  locale_data:
    available_locales:
      - en_GB
      - ja_JP
    default_locale: en_GB
  settings:
    locale: "$Locale"
"@
    return New-TempFile 'product-settings-test' $yaml 'yaml'
}

Describe 'Dot-sourcing du lanceur' {
    It 'expose ses fonctions sans lancer le jeu' {
        Get-Command Get-LocaleLabel    -CommandType Function | Should Not BeNullOrEmpty
        Get-Command Set-LeagueLocale   -CommandType Function | Should Not BeNullOrEmpty
        Get-Command Start-LeagueClient -CommandType Function | Should Not BeNullOrEmpty
    }
}

Describe 'Get-LocaleLabel' {
    AfterEach { Remove-TestTempFiles }

    It 'rend le libellé natif de la langue du catalogue' {
        $path = New-TempFile 'locales-test' '[{ "code": "ja_JP", "label": "Japonais", "default": false }]'
        Get-LocaleLabel 'ja_JP' $path | Should Be 'Japonais'
    }

    It 'rend le code quand la langue est absente du catalogue' {
        $path = New-TempFile 'locales-test' '[{ "code": "fr_FR", "label": "Francais", "default": true }]'
        Get-LocaleLabel 'ko_KR' $path | Should Be 'ko_KR'
    }

    It 'rend le code quand le catalogue est introuvable' {
        Get-LocaleLabel 'ja_JP' 'C:\introuvable\locales.json' | Should Be 'ja_JP'
    }
}

Describe 'Set-LeagueLocale' {
    AfterEach { Remove-TestTempFiles }

    It 'applique la langue demandée à settings.locale' {
        $path = New-TempProductSettings 'en_GB'
        Set-LeagueLocale -Path $path -Value 'ja_JP'
        (Get-Content $path -Raw) -match '(?m)^\s+locale:\s*"ja_JP"$' | Should Be $true
    }

    It 'laisse default_locale intact — le repli reste géré par Riot' {
        $path = New-TempProductSettings 'en_GB'
        Set-LeagueLocale -Path $path -Value 'ja_JP'
        (Get-Content $path -Raw) -match 'default_locale: en_GB' | Should Be $true
    }

    It 'conserve le reste du fichier' {
        $path = New-TempProductSettings 'en_GB'
        Set-LeagueLocale -Path $path -Value 'ja_JP'
        $content = Get-Content $path -Raw
        $content -match 'available_locales' | Should Be $true
        $content -match 'product_settings'  | Should Be $true
    }
}

Describe 'Enter-LaunchLock' {
    $name = 'Local\HexLauncher.Launch.Test-' + [guid]::NewGuid().ToString('N')

    It 'prend le verrou quand aucun lanceur ne tourne, et le rend' {
        $lock = Enter-LaunchLock $name
        $lock | Should Not BeNullOrEmpty
        Exit-LaunchLock $lock
        $again = Enter-LaunchLock $name
        $again | Should Not BeNullOrEmpty
        Exit-LaunchLock $again
    }

    It 'refuse le verrou tenu par un autre lanceur — un autre fil, comme un autre process' {
        $holder = [powershell]::Create()
        $holder.AddScript({ param($Name) $m = New-Object Threading.Mutex($false, $Name); [void]$m.WaitOne(0); Start-Sleep -Seconds 2; $m.ReleaseMutex(); $m.Dispose() }).AddArgument($name) | Out-Null
        $handle = $holder.BeginInvoke()
        Start-Sleep -Milliseconds 300
        try {
            Enter-LaunchLock $name | Should BeNullOrEmpty
        }
        finally { $holder.EndInvoke($handle); $holder.Dispose() }
    }

    It 'reprend un verrou abandonné par un lanceur tué' {
        $holder = [powershell]::Create()
        $holder.AddScript({ param($Name) $m = New-Object Threading.Mutex($false, $Name); [void]$m.WaitOne(0) }).AddArgument($name) | Out-Null
        $holder.Invoke() | Out-Null
        $holder.Dispose()
        $lock = Enter-LaunchLock $name
        $lock | Should Not BeNullOrEmpty
        Exit-LaunchLock $lock
    }

    It 'rend la main sans erreur quand il n''y a rien à libérer' {
        { Exit-LaunchLock $null } | Should Not Throw
    }

    It 'laisse au second lanceur le temps de lire le message avant de s''effacer' {
        $LaunchRefusedSplashSeconds | Should BeGreaterThan 1
    }
}

Describe 'Test-LaunchBurst' {
    Mock Write-LaunchLogLine { }

    It 'prévient à partir du troisième lancement en cinq minutes, et le journalise' {
        Mock Get-RecentLaunchCount { return 3 }
        Test-LaunchBurst 'C:\journal\launch.log' | Should Be $true
        Assert-MockCalled Get-RecentLaunchCount -Scope It -Exactly 1 -ParameterFilter { $Path -eq 'C:\journal\launch.log' -and $Since -gt (Get-Date).AddMinutes(-6) -and $Since -lt (Get-Date).AddMinutes(-4) }
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Step -eq 'WARN' -and $Detail -like '3 lancements en 5 min*' }
    }

    It 'reste silencieux en dessous du seuil' {
        Mock Get-RecentLaunchCount { return 2 }
        Test-LaunchBurst 'C:\journal\launch.log' | Should Be $false
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 0
    }

    It 'nomme l''erreur Vanguard et le redémarrage dans le message' {
        $LaunchBurstWarningMessage | Should Match 'VAN 216'
        $LaunchBurstWarningMessage | Should Match 'redémarrage'
    }
}

Describe 'Stop-RiotProcesses' {
    Mock Wait-WithAnimation { }

    It 'ferme le client de jeu et le Riot Client en cours' {
        Mock Get-Process { return @([pscustomobject]@{ Name = 'LeagueClient' }, [pscustomobject]@{ Name = 'RiotClientServices' }) }
        Mock Stop-Process { }
        Stop-RiotProcesses
        Assert-MockCalled Stop-Process -Scope It -Exactly 2
    }

    It 'ne ferme rien quand aucun process Riot ne tourne' {
        Mock Get-Process { return $null }
        Mock Stop-Process { }
        Stop-RiotProcesses
        Assert-MockCalled Stop-Process -Scope It -Exactly 0
    }

    It 'vise le client de jeu comme le Riot Client' {
        $RiotProcessNames -contains 'LeagueClient'       | Should Be $true
        $RiotProcessNames -contains 'LeagueClientUx'     | Should Be $true
        $RiotProcessNames -contains 'RiotClientServices' | Should Be $true
    }
}

Describe 'Start-RiotClient' {
    It 'démarre le Riot Client seul, sans lui demander de produit' {
        Mock Start-Process { }
        Start-RiotClient 'C:\Riot\RiotClientServices.exe' | Should Be $true
        Assert-MockCalled Start-Process -Scope It -Exactly 1 -ParameterFilter { $FilePath -eq 'C:\Riot\RiotClientServices.exe' -and $null -eq $ArgumentList }
    }

    It 'rend faux avec un avertissement quand le chemin de config.json est périmé' {
        Mock Write-Warning {}
        Mock Start-Process { throw 'fichier introuvable' }
        Start-RiotClient 'C:\perime\RiotClientServices.exe' | Should Be $false
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }
}

Describe 'Get-RiotClientVersion' {
    It 'lit la version produit du Riot Client sur le disque' {
        Mock Get-Item { return [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = '139.0.5.4957' } } } -ParameterFilter { $Path -like 'C:\Riot\*' }
        Get-RiotClientVersion 'C:\Riot\RiotClientServices.exe' | Should Be '139.0.5.4957'
    }

    It 'rend une chaîne vide quand le chemin est périmé — jamais une exception' {
        Get-RiotClientVersion 'C:\introuvable\RiotClientServices.exe' | Should Be ''
    }
}

Describe 'New-LocalApiFailure' {
    It 'porte la cause, le code HTTP et l''étape de l''échec' {
        $failure = New-LocalApiFailure 'route' 404 'locale'
        $failure.Kind       | Should Be 'route'
        $failure.StatusCode | Should Be 404
        $failure.Stage      | Should Be 'locale'
    }
}

Describe 'Stop-GameClientProcesses' {
    Mock Wait-WithAnimation { }

    It 'ne ferme que le client de jeu, jamais la session du Riot Client' {
        $GameClientProcessNames -contains 'LeagueClient'        | Should Be $true
        $GameClientProcessNames -contains 'LeagueClientUx'      | Should Be $true
        $GameClientProcessNames -contains 'RiotClientServices'  | Should Be $false
        $GameClientProcessNames -contains 'RiotClientUx'        | Should Be $false
    }

    It 'ferme les process du client de jeu en cours' {
        Mock Get-Process { return @([pscustomobject]@{ Name = 'LeagueClient' }, [pscustomobject]@{ Name = 'LeagueClientUx' }) }
        Mock Stop-Process { }
        Stop-GameClientProcesses
        Assert-MockCalled Stop-Process -Scope It -Exactly 2
    }

    It 'ne ferme rien quand le jeu ne tourne pas' {
        Mock Get-Process { return $null }
        Mock Stop-Process { }
        Stop-GameClientProcesses
        Assert-MockCalled Stop-Process -Scope It -Exactly 0
    }
}

Describe 'Stop-GameClientByLocalApi' {
    It 'demande au Riot Client de fermer la session du jeu' {
        Mock Read-RiotClientLockfile { return [pscustomobject]@{ Port = 4711; Password = 'x' } }
        Mock Stop-RiotProduct { return $true }
        Stop-GameClientByLocalApi | Should Be $true
        Assert-MockCalled Stop-RiotProduct -Scope It -Exactly 1 -ParameterFilter { $ProductId -eq 'league_of_legends' }
    }

    It 'rend faux sans rien demander quand le lockfile est absent — Riot Client éteint' {
        Mock Read-RiotClientLockfile { return $null }
        Mock Stop-RiotProduct { return $true }
        Stop-GameClientByLocalApi | Should Be $false
        Assert-MockCalled Stop-RiotProduct -Scope It -Exactly 0
    }
}

Describe 'Wait-GameClientExit' {
    It 'confirme la fermeture dès que le client de jeu a disparu' {
        Mock Test-GameClientRunning { return $false }
        Wait-GameClientExit 5 { } | Should Be $true
    }

    It 'laisse au client de jeu le temps de disparaître' {
        $script:polls = 0
        Mock Test-GameClientRunning { $script:polls++; return ($script:polls -lt 3) }
        Wait-GameClientExit 5 { } | Should Be $true
        $script:polls | Should Be 3
    }

    It 'renonce à l''échéance quand le client de jeu reste là' {
        Mock Test-GameClientRunning { return $true }
        Wait-GameClientExit 1 { } | Should Be $false
    }
}

Describe 'Stop-GameClient' {
    Mock Write-LaunchLogLine { }

    It 'ne fait rien quand le jeu ne tourne pas' {
        Mock Test-GameClientRunning { return $false }
        Mock Stop-GameClientByLocalApi { return $true }
        Mock Stop-GameClientProcesses { }
        Stop-GameClient { }
        Assert-MockCalled Stop-GameClientByLocalApi -Scope It -Exactly 0
        Assert-MockCalled Stop-GameClientProcesses -Scope It -Exactly 0
    }

    It 'ferme le jeu par l''API et ne tue rien quand le client disparaît' {
        Mock Test-GameClientRunning { return $true }
        Mock Stop-GameClientByLocalApi { return $true }
        Mock Wait-GameClientExit { return $true }
        Mock Stop-GameClientProcesses { }
        Stop-GameClient { }
        Assert-MockCalled Stop-GameClientProcesses -Scope It -Exactly 0
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Step -eq 'GAME' -and $Detail -like 'client de jeu fermé par l''API en *' }
    }

    It 'tue le client de jeu en dernier recours quand l''API refuse la fermeture' {
        Mock Test-GameClientRunning { return $true }
        Mock Stop-GameClientByLocalApi { return $false }
        Mock Wait-GameClientExit { return $true }
        Mock Stop-GameClientProcesses { }
        Stop-GameClient { }
        Assert-MockCalled Wait-GameClientExit -Scope It -Exactly 0
        Assert-MockCalled Stop-GameClientProcesses -Scope It -Exactly 1
    }

    It 'tue le client de jeu quand il survit à une fermeture acceptée' {
        Mock Test-GameClientRunning { return $true }
        Mock Stop-GameClientByLocalApi { return $true }
        Mock Wait-GameClientExit { return $false }
        Mock Stop-GameClientProcesses { }
        Stop-GameClient { }
        Assert-MockCalled Wait-GameClientExit -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -eq $GameClientStopTimeoutSeconds }
        Assert-MockCalled Stop-GameClientProcesses -Scope It -Exactly 1
    }
}

Describe 'Wait-GameClientStart' {
    It 'confirme le lancement dès que le client de jeu est là' {
        Mock Test-GameClientRunning { return $true }
        Wait-GameClientStart 5 { } | Should Be $true
    }

    It 's''arrête tout de suite quand l''utilisateur force le démarrage, sans attendre l''échéance' {
        Mock Test-GameClientRunning { return $false }
        $chrono = [Diagnostics.Stopwatch]::StartNew()
        Wait-GameClientStart 30 { Start-Sleep -Milliseconds 50 } { $true } | Should Be $false
        $chrono.Elapsed.TotalSeconds | Should BeLessThan 5
    }

    It 'renonce à l''échéance quand le client de jeu n''apparaît jamais' {
        Mock Test-GameClientRunning { return $false }
        Wait-GameClientStart 1 { } | Should Be $false
    }

    It 'sans limite, n''abandonne que sur demande d''arrêt' {
        $script:ticks = 0
        Mock Test-GameClientRunning { return $false }
        Wait-GameClientStart $NoTimeLimitSeconds { $script:ticks++ } { $script:ticks -ge 5 } | Should Be $false
        $script:ticks | Should Be 5
    }

    It 'laisse au client de jeu le temps d''apparaître' {
        $script:polls = 0
        Mock Test-GameClientRunning { $script:polls++; return ($script:polls -ge 3) }
        Wait-GameClientStart 5 { } | Should Be $true
        $script:polls | Should Be 3
    }

    It 'mesure un écoulement, pas une heure : une horloge qui recule ne prolonge pas l''attente' {
        Mock Test-GameClientRunning { return $false }
        Mock Get-Date { return [datetime]'2000-01-01' }
        Wait-GameClientStart 1 { } | Should Be $false
    }
}

Describe 'Budgets du chemin rapide' {
    It 'n''impose aucune limite de temps au chemin rapide — un patch sur une connexion lente peut durer des heures' {
        $LocalApiBudgetSeconds | Should Be $NoTimeLimitSeconds
    }

    It 'propose « Forcer en démarrage manuel » à partir de deux minutes' {
        $ForceStartButtonDelaySeconds | Should Be 120
    }

    It 'propose le bouton « Forcer » : sans limite de temps, c''est la seule sortie d''une attente qui dure' {
        $ForceStartButtonDelaySeconds | Should BeGreaterThan 0
    }

    It 'attend le client de jeu sans limite après un lancement accepté — « Forcer » reste la sortie' {
        $GameClientStartTimeoutSeconds | Should Be $NoTimeLimitSeconds
    }
}

Describe 'Get-RemainingBudgetSeconds' {
    It 'rend ce qui reste du budget' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(20) }
        Get-RemainingBudgetSeconds $chrono 60 | Should Be 40
    }

    It 'laisse toujours une dernière seconde, même le budget épuisé' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(90) }
        Get-RemainingBudgetSeconds $chrono 60 | Should Be 1
    }

    It 'transmet un budget sans limite tel quel, quel que soit le temps écoulé' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromHours(3) }
        Get-RemainingBudgetSeconds $chrono $NoTimeLimitSeconds | Should Be $NoTimeLimitSeconds
    }
}

Describe 'Assert-RiotClientRunning' {
    It 'laisse la session en place quand le Riot Client tourne' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Assert-RiotClientRunning 'C:\Riot\RiotClientServices.exe' | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 0
    }

    It 'remet le Riot Client debout quand il s''est fermé de lui-même' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $true }
        Assert-RiotClientRunning 'C:\Riot\RiotClientServices.exe' | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 1
    }

    It 'rend faux quand il ne peut pas être redémarré' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $false }
        Assert-RiotClientRunning 'C:\perime\RiotClientServices.exe' | Should Be $false
    }
}

Describe 'Start-LeagueClientByLocalApi' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'
    # Un Riot Client avec sa fenêtre, sauf test contraire : le réveil a son propre Describe
    Mock Test-RiotClientInterfaceRunning { return $true }

    It 'pose la langue puis lance le jeu, sans jamais écrire le yaml' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Mock Set-LeagueLocale { }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $true
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 1 -ParameterFilter { $Locale -eq 'ja_JP' -and $ProductId -eq 'league_of_legends' -and $PatchlineId -eq 'live' }
        Assert-MockCalled Set-LeagueLocale -Scope It -Exactly 0
    }

    It 'donne à la demande de lancement une sonde qui reconnaît le client de jeu en marche' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = 'probe'; StatusCode = 423 } }
        Mock Wait-GameClientStart { return $true }
        Mock Test-GameClientRunning { return $true }
        Mock Close-RiotClientWindow { return $true }
        Mock Write-LaunchLogLine { }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $true
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 1 -ParameterFilter { $null -ne $SuccessProbe -and [bool](& $SuccessProbe) }
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -match 'déjà en marche pendant la demande de lancement \(dernier code 423\)' }
        Assert-MockCalled Close-RiotClientWindow -Scope It -Exactly 1
    }

    It 'réutilise la session du Riot Client quand elle tourne déjà, sans la redémarrer' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 0
    }

    It 'démarre le Riot Client quand il est éteint, puis attend son API' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 1 -ParameterFilter { $Path -eq $riotClient }
    }

    It 'renonce tout de suite quand le Riot Client ne peut pas démarrer, sans attendre son API' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $false }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $false
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 0
    }

    It 'transmet le budget sans limite à la langue comme au lancement' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null | Out-Null
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -eq $NoTimeLimitSeconds }
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -eq $NoTimeLimitSeconds }
    }

    It 'surveille la session du Riot Client à chaque tour, car il se ferme parfois en cours de route' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { param($ProductId, $PatchlineId, $Locale, $LockfilePath, $TimeoutSeconds, $OnTick) & $OnTick; return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Start-LeagueClientByLocalApi 'C:\Riot\RiotClientServices.exe' 'ja_JP' { } $null | Out-Null
        Assert-MockCalled Test-RiotClientRunning -Scope It -Times 2
    }

    It 'renonce quand la langue est refusée, sans tenter le lancement' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $false; Kind = 'route'; StatusCode = 404 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $false
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 0
    }

    It 'transmet la demande d''arrêt aux deux attentes de l''API' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null { $false } | Out-Null
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 1 -ParameterFilter { $null -ne $ShouldStop }
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 1 -ParameterFilter { $null -ne $ShouldStop }
    }

    It 'qualifie d''abandon un démarrage forcé pendant l''attente du client de jeu — pas de lancement muet' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $false }
        $attempt = Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null { $true }
        $attempt.Success       | Should Be $false
        $attempt.Failure.Kind  | Should Be 'cancelled'
        $attempt.Failure.Stage | Should Be 'game-client'
    }

    It 'remonte l''abandon décidé pendant la pose de la langue' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $false; Kind = 'cancelled'; StatusCode = 464 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        $attempt = Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null { $true }
        $attempt.Failure.Kind  | Should Be 'cancelled'
        $attempt.Failure.Stage | Should Be 'locale'
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 0
    }

    It 'renonce quand l''API n''accepte pas le lancement' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $false; Kind = 'timeout'; StatusCode = 464 } }
        Mock Wait-GameClientStart { return $true }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $false
        Assert-MockCalled Wait-GameClientStart -Scope It -Exactly 0
    }

    It 'qualifie de silencieux un lancement accepté dont le client de jeu n''apparaît pas' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $false }
        $attempt = Start-LeagueClientByLocalApi 'C:\Riot\RiotClientServices.exe' 'ja_JP' { } $null
        $attempt.Success      | Should Be $false
        $attempt.Failure.Kind | Should Be 'silent'
        $attempt.Failure.Stage | Should Be 'game-client'
    }

    It 'renonce quand le lancement est accepté mais que le client de jeu n''apparaît pas' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $false }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $false
    }
}

# Describe à part : les mocks de Pester 3 vivent jusqu'à la fin du Describe, et celui de Start-LeagueClient
# remplace le chemin historique — ici, c'est le vrai qui doit tourner
Describe 'Start-LeagueClient en démarrage manuel' {
    It 'ferme le client de jeu comme avant — par les process, sans aucun appel à l''API' {
        Mock Stop-GameClient { }
        Mock Stop-RiotProduct { return $true }
        Mock Stop-RiotProcesses { }
        Mock Set-LeagueLocale { }
        Mock Start-Process { }
        Mock Write-LaunchLogLine { }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -NoLocalApi -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'legacy'
        Assert-MockCalled Stop-RiotProcesses -Scope It -Exactly 1
        Assert-MockCalled Stop-GameClient -Scope It -Exactly 0
        Assert-MockCalled Stop-RiotProduct -Scope It -Exactly 0
    }
}

Describe 'Get-FallbackStatusMessage' {
    It 'dit « démarrage manuel forcé » quand c''est l''utilisateur qui l''a demandé' {
        Get-FallbackStatusMessage ([pscustomobject]@{ Kind = 'cancelled'; StatusCode = 464; Stage = 'launch' }) | Should Match '^Démarrage manuel forcé'
    }

    It 'dit « démarrage manuel » sur tout autre échec, et sans cause' {
        Get-FallbackStatusMessage ([pscustomobject]@{ Kind = 'route'; StatusCode = 404; Stage = 'locale' }) | Should Match '^Démarrage manuel :'
        Get-FallbackStatusMessage $null | Should Match '^Démarrage manuel :'
    }
}

Describe 'Write-LaunchStatus' {
    It 'transmet le message à qui veut l''afficher' {
        $script:vus = @()
        Write-LaunchStatus { param($Message) $script:vus += $Message } 'Application de la langue fr_FR…'
        $script:vus -join '' | Should Be 'Application de la langue fr_FR…'
    }

    It 'ne bronche pas quand personne n''écoute (mode script, tests)' {
        { Write-LaunchStatus $null 'Peu importe' } | Should Not Throw
    }
}

Describe 'Format-WaitingStatus' {
    It 'accole les secondes écoulées, pour montrer qu''une longue attente progresse' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(12.4) }
        Format-WaitingStatus 'Demande de lancement au Riot Client…' $chrono | Should Be 'Demande de lancement au Riot Client (12 s)'
    }
}

Describe 'Test-RiotClientInterfaceRunning' {
    It 'rend faux quand seul RiotClientServices tourne' {
        # Aucune sortie, comme Get-Process -ErrorAction SilentlyContinue : un $null explicite compterait pour un
        Mock Get-Process { }
        Test-RiotClientInterfaceRunning | Should Be $false
    }

    It 'reconnaît le process de l''interface, « Riot Client » avec une espace' {
        Mock Get-Process { return @([pscustomobject]@{ Name = 'Riot Client' }) } -ParameterFilter { $Name -eq 'Riot Client' }
        Test-RiotClientInterfaceRunning | Should Be $true
    }
}

Describe 'Wait-RiotClientInterface' {
    It 'rend vrai dès que l''interface est là et que l''API répond' {
        Mock Test-RiotClientInterfaceRunning { return $true }
        Mock Read-RiotClientLockfile { return [pscustomobject]@{ Port = 1; Password = 'x' } }
        Mock Test-RiotClientReady { return $true }
        Wait-RiotClientInterface 5 { } | Should Be $true
    }

    It 'continue d''attendre tant que l''interface est revenue mais pas l''API — 404 pendant le rechargement' {
        Mock Test-RiotClientInterfaceRunning { return $true }
        Mock Read-RiotClientLockfile { return [pscustomobject]@{ Port = 1; Password = 'x' } }
        $script:probes = 0
        Mock Test-RiotClientReady { $script:probes++; return ($script:probes -ge 3) }
        Wait-RiotClientInterface 5 { } | Should Be $true
        $script:probes | Should Be 3
    }

    It 'rend faux à l''échéance, sans exception, quand rien ne revient' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Wait-RiotClientInterface 1 { } | Should Be $false
    }

    It 's''arrête sur demande de l''utilisateur' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Wait-RiotClientInterface 30 { } { $true } | Should Be $false
    }
}

Describe 'Restore-RiotClientInterface' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'

    It 'ne fait rien quand la fenêtre du Riot Client est là' {
        Mock Test-RiotClientInterfaceRunning { return $true }
        Mock Start-RiotClient { return $true }
        Restore-RiotClientInterface $riotClient { } | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 0
    }

    It 'relance l''exécutable sans argument, puis attend l''interface et l''API — jamais de kill' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotClientInterface { return $true }
        Mock Stop-Process { }
        Restore-RiotClientInterface $riotClient { } | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 1 -ParameterFilter { $Path -eq $riotClient }
        Assert-MockCalled Wait-RiotClientInterface -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -eq $RiotClientInterfaceRetrySeconds }
        Assert-MockCalled Stop-Process -Scope It -Exactly 0
    }

    It 'relance toutes les 30 s après la seconde, sans jamais renoncer de lui-même' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $true }
        $script:waits = 0
        Mock Wait-RiotClientInterface { $script:waits++; return $false }
        Restore-RiotClientInterface $riotClient { } { $script:waits -ge 4 } | Should Be $false
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 4
        Assert-MockCalled Wait-RiotClientInterface -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -eq $RiotClientInterfaceRetrySeconds }
        Assert-MockCalled Wait-RiotClientInterface -Scope It -Exactly 3 -ParameterFilter { $TimeoutSeconds -eq $RiotClientRelaunchIntervalSeconds }
    }

    It 'ne rejoue pas la relance quand l''utilisateur a forcé le démarrage manuel entre-temps' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotClientInterface { return $false }
        Restore-RiotClientInterface $riotClient { } { $true } | Should Be $false
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 1
    }

    It 'rend faux quand l''exécutable est introuvable, sans attendre' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $false }
        Mock Wait-RiotClientInterface { return $true }
        Restore-RiotClientInterface 'C:\perime\RiotClientServices.exe' { } | Should Be $false
        Assert-MockCalled Wait-RiotClientInterface -Scope It -Exactly 0
    }

    It 'ne rend faux que sur demande d''arrêt, et le journalise' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Write-LaunchLogLine { }
        $script:waits = 0
        Mock Wait-RiotClientInterface { $script:waits++; return $false }
        Restore-RiotClientInterface $riotClient { } { $script:waits -ge 2 } | Should Be $false
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like 'réveil interrompu*' }
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like 'relance n° 2 *' }
    }

    # En dernier : ses mocks filtrés survivent jusqu'à la fin du Describe (Pester 3) et masqueraient les suivants
    It 'rejoue la relance quand l''interface n''est pas revenue après le premier délai — la demande a pu se perdre pendant la bascule' {
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotClientInterface { return $false } -ParameterFilter { $TimeoutSeconds -eq $RiotClientInterfaceRetrySeconds }
        Mock Wait-RiotClientInterface { return $true }  -ParameterFilter { $TimeoutSeconds -ne $RiotClientInterfaceRetrySeconds }
        Mock Write-LaunchLogLine { }
        Restore-RiotClientInterface $riotClient { } | Should Be $true
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 2
        Assert-MockCalled Wait-RiotClientInterface -Scope It -Exactly 2
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like 'relance n° 2 *' }
    }
}

Describe 'Watch-RiotClientInterface' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'
    Mock Write-LaunchLogLine { }

    It 'retient que l''interface a été vue, sans rien réveiller' {
        $script:RiotInterfaceSeen = $false
        Mock Test-RiotClientInterfaceRunning { return $true }
        Mock Restore-RiotClientInterface { return $true }
        Watch-RiotClientInterface $riotClient { } { $false }
        $script:RiotInterfaceSeen | Should Be $true
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 0
    }

    It 'ne réveille pas un Riot Client dont l''interface n''a jamais été vue — il est en train de démarrer' {
        $script:RiotInterfaceSeen = $false
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $true }
        Watch-RiotClientInterface $riotClient { } { $false }
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 0
    }

    It 'réveille le Riot Client dont la fenêtre a été refermée pendant l''attente, une seule fois' {
        $script:RiotInterfaceSeen = $true
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $false }
        Watch-RiotClientInterface $riotClient { } { $false }
        Watch-RiotClientInterface $riotClient { } { $false }
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 1 -ParameterFilter { $Path -eq $riotClient }
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -like 'interface disparue*' }
    }

    It 'réveille de nouveau si l''interface revient puis disparaît encore' {
        $script:RiotInterfaceSeen = $true
        $script:present = $false
        Mock Test-RiotClientInterfaceRunning { return $script:present }
        Mock Restore-RiotClientInterface { return $true }
        Watch-RiotClientInterface $riotClient { } { $false }   # disparue → réveil
        $script:present = $true
        Watch-RiotClientInterface $riotClient { } { $false }   # revenue
        $script:present = $false
        Watch-RiotClientInterface $riotClient { } { $false }   # disparue → second réveil
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 2
    }
}

Describe 'Start-LeagueClientByLocalApi, Riot Client replié sans interface' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'

    It 'réveille un Riot Client déjà en marche mais sans fenêtre, avant de poser la langue' {
        Mock Test-RiotClientRunning { return $true }
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        $script:etapes = @()
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } { param($Message) $script:etapes += $Message }).Success | Should Be $true
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 1
        ($script:etapes -join ' | ') | Should Match 'Réveil du Riot Client'
    }

    It 'ne relance jamais un Riot Client qu''il vient de démarrer à froid, même sans fenêtre encore' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null | Out-Null
        Assert-MockCalled Start-RiotClient -Scope It -Exactly 1
        Assert-MockCalled Restore-RiotClientInterface -Scope It -Exactly 0
    }

    It 'tente l''API quand même si le réveil n''aboutit pas dans le délai' {
        Mock Test-RiotClientRunning { return $true }
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $false }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        (Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null).Success | Should Be $true
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 1
    }

    It 'passe en démarrage manuel avec la cause « abandon » si l''utilisateur force le démarrage pendant le réveil' {
        Mock Test-RiotClientRunning { return $true }
        Mock Test-RiotClientInterfaceRunning { return $false }
        Mock Restore-RiotClientInterface { return $false }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        $attempt = Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null { $true }
        $attempt.Success       | Should Be $false
        $attempt.Failure.Kind  | Should Be 'cancelled'
        $attempt.Failure.Stage | Should Be 'riot-client'
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 0
    }
}

Describe 'Get-WaitReasonStatus' {
    It 'dit au joueur que Riot met le jeu à jour' {
        Get-WaitReasonStatus 'updating' | Should Be 'Mise à jour de League of Legends par Riot en cours…'
    }

    It 'dit au joueur que Riot libère la session précédente' {
        Get-WaitReasonStatus 'releasing' | Should Be 'Riot libère la session de jeu précédente…'
    }

    It 'ne dit rien pour un motif inconnu' {
        Get-WaitReasonStatus 'autre' | Should Be ''
        Get-WaitReasonStatus '' | Should Be ''
    }
}

Describe 'Start-LeagueClientByLocalApi, suivi des étapes' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'
    Mock Test-RiotClientInterfaceRunning { return $true }

    It 'annonce chaque étape jusqu''à l''apparition du client de jeu' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        $script:etapes = @()
        Start-LeagueClientByLocalApi $riotClient 'fr_FR' { } { param($Message) $script:etapes += $Message } | Out-Null
        ($script:etapes -join ' | ') | Should Match 'Application de la langue fr_FR'
        ($script:etapes -join ' | ') | Should Match 'Demande de lancement'
        ($script:etapes -join ' | ') | Should Match 'Le jeu se prépare'
    }

    It 'affiche pourquoi Riot fait attendre le lancement, et le journalise' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Write-LaunchLogLine { }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { & $OnWait 'updating'; return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        $script:etapes = @()
        Start-LeagueClientByLocalApi $riotClient 'fr_FR' { } { param($Message) $script:etapes += $Message } | Out-Null
        ($script:etapes -join ' | ') | Should Match 'Mise à jour de League of Legends par Riot en cours'
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Step -eq 'WAIT' -and $Detail -like '424 : Mise à jour*' }
    }

    It 'annonce le démarrage du Riot Client quand il est éteint' {
        Mock Test-RiotClientRunning { return $false }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        $script:etapes = @()
        Start-LeagueClientByLocalApi $riotClient 'fr_FR' { } { param($Message) $script:etapes += $Message } | Out-Null
        ($script:etapes -join ' | ') | Should Match 'Démarrage du Riot Client'
    }
}

Describe 'Start-LeagueClientByCommandLine' {
    It 'ferme tout Riot, écrit la langue dans le yaml et relance en ligne de commande' {
        Mock Stop-RiotProcesses { }
        Mock Set-LeagueLocale { }
        Mock Start-Process { }
        Start-LeagueClientByCommandLine 'C:\Riot\RiotClientServices.exe' 'C:\yaml\settings.yaml' 'ja_JP' | Should Be $true
        Assert-MockCalled Stop-RiotProcesses -Scope It -Exactly 1
        Assert-MockCalled Set-LeagueLocale -Scope It -Exactly 1 -ParameterFilter { $Path -eq 'C:\yaml\settings.yaml' -and $Value -eq 'ja_JP' }
        Assert-MockCalled Start-Process -Scope It -Exactly 1 -ParameterFilter {
            $FilePath -eq 'C:\Riot\RiotClientServices.exe' -and
            $ArgumentList -match '--launch-product=league_of_legends' -and
            $ArgumentList -match '--launch-patchline=live' -and
            $ArgumentList -match '--locale=ja_JP'
        }
    }

    It 'lance le jeu même quand le fichier de langue est inaccessible — Riot vient d''être fermé, abandonner laisserait l''utilisateur sans rien' {
        Mock Write-Warning {}
        Mock Stop-RiotProcesses { }
        Mock Set-LeagueLocale { throw 'yaml introuvable' }
        Mock Start-Process { }
        Start-LeagueClientByCommandLine 'C:\Riot\RiotClientServices.exe' 'C:\absent\settings.yaml' 'ja_JP' | Should Be $true
        Assert-MockCalled Start-Process -Scope It -Exactly 1
        Assert-MockCalled Write-Warning -Scope It -Exactly 1
    }

    It 'rend faux sans lever d''exception quand le Riot Client est introuvable' {
        Mock Write-Warning {}
        Mock Stop-RiotProcesses { }
        Mock Set-LeagueLocale { }
        Mock Start-Process { throw 'fichier introuvable' }
        Start-LeagueClientByCommandLine 'C:\perime\RiotClientServices.exe' 'C:\yaml\settings.yaml' 'ja_JP' | Should Be $false
    }
}

Describe 'Start-LeagueClient' {
    It 'passe par l''API locale et ne touche pas au chemin historique quand tout répond' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'api'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 0
    }

    It 'reprend le chemin historique dès que l''API locale échoue' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'legacy'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 1 -ParameterFilter { $Value -eq 'ja_JP' }
    }

    It 'ne tue pas un client de jeu apparu juste après l''échéance, et replie la fenêtre Riot comme après un succès' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $true }
        Mock Start-LeagueClientByCommandLine { return $true }
        Mock Close-RiotClientWindow { return $true }
        Mock Write-LaunchLogLine { }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'api'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 0
        Assert-MockCalled Close-RiotClientWindow -Scope It -Exactly 1
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Detail -match 'fenêtre du Riot Client fermée' }
    }

    It 'remonte la cause de l''échec du chemin rapide, pour le journal' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'route'; StatusCode = 404; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        $launch = Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { }
        $launch.Outcome            | Should Be 'legacy'
        $launch.Failure.Kind       | Should Be 'route'
        $launch.Failure.StatusCode | Should Be 404
        $launch.Failure.Stage      | Should Be 'launch'
    }

    It 'passe en démarrage manuel quand l''utilisateur force le démarrage, avec la cause pour le journal' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'cancelled'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        $launch = Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } -ShouldStop { $true }
        $launch.Outcome      | Should Be 'legacy'
        $launch.Failure.Kind | Should Be 'cancelled'
        Assert-MockCalled Start-LeagueClientByLocalApi -Scope It -Exactly 1 -ParameterFilter { $null -ne $ShouldStop }
    }

    It 'ne retient aucune cause quand l''API a réussi' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        (Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { }).Failure | Should BeNullOrEmpty
    }

    It 'signale l''échec quand même le chemin historique ne peut pas démarrer le Riot Client' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $false }
        Start-LeagueClient -Path 'C:\perime\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'failed'
    }

    It 'prend directement le chemin historique avec -NoLocalApi, sans rien tenter par l''API' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -NoLocalApi -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'legacy'
        Assert-MockCalled Start-LeagueClientByLocalApi -Scope It -Exactly 0
        Assert-MockCalled Stop-GameClient -Scope It -Exactly 0
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 1
    }

    It 's''arrête sans démarrage manuel ni kill quand l''utilisateur clique la croix' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'cancelled'; StatusCode = 424; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        Mock Write-LaunchLogLine { }
        $launch = Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } -ShouldStop { $false } -ShouldAbort { $true }
        $launch.Outcome | Should Be 'cancelled'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 0
        Assert-MockCalled Write-LaunchLogLine -Scope It -Exactly 1 -ParameterFilter { $Step -eq 'ABORT' }
    }

    It 'transmet à la boucle un arrêt qui vaut pour « Forcer » comme pour la croix' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { param($Path, $Value, $OnTick, $OnStatus, $ShouldStop) $script:stopSeen = & $ShouldStop; return [pscustomobject]@{ Success = $true; Failure = $null } }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } -ShouldStop { $false } -ShouldAbort { $true } | Out-Null
        $script:stopSeen | Should Be $true
    }

    It 'n''interrompt jamais l''installation, même quand rien ne répond' {
        Mock Stop-GameClient { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $false }
        { Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } } | Should Not Throw
    }
}
