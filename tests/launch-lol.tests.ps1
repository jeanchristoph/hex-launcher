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

Describe 'Wait-GameClientStart' {
    It 'confirme le lancement dès que le client de jeu est là' {
        Mock Test-GameClientRunning { return $true }
        Wait-GameClientStart 5 { } | Should Be $true
    }

    It 'renonce à l''échéance quand le client de jeu n''apparaît jamais' {
        Mock Test-GameClientRunning { return $false }
        Wait-GameClientStart 1 { } | Should Be $false
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

Describe 'Get-RemainingBudgetSeconds' {
    It 'rend ce qui reste du budget' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(20) }
        Get-RemainingBudgetSeconds $chrono 60 | Should Be 40
    }

    It 'laisse toujours une dernière seconde, même le budget épuisé' {
        $chrono = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(90) }
        Get-RemainingBudgetSeconds $chrono 60 | Should Be 1
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

    It 'partage un seul budget entre la langue et le lancement' {
        Mock Test-RiotClientRunning { return $true }
        Mock Start-RiotClient { return $true }
        Mock Wait-RiotProductLocale { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 201 } }
        Mock Wait-RiotProductLaunch { return [pscustomobject]@{ Success = $true; Kind = ''; StatusCode = 200 } }
        Mock Wait-GameClientStart { return $true }
        Start-LeagueClientByLocalApi $riotClient 'ja_JP' { } $null | Out-Null
        Assert-MockCalled Wait-RiotProductLocale -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -le $LocalApiBudgetSeconds -and $TimeoutSeconds -ge 1 }
        Assert-MockCalled Wait-RiotProductLaunch -Scope It -Exactly 1 -ParameterFilter { $TimeoutSeconds -le $LocalApiBudgetSeconds -and $TimeoutSeconds -ge 1 }
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

Describe 'Start-LeagueClientByLocalApi, suivi des étapes' {
    $riotClient = 'C:\Riot\RiotClientServices.exe'

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
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'api'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 0
    }

    It 'reprend le chemin historique dès que l''API locale échoue' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'legacy'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 1 -ParameterFilter { $Value -eq 'ja_JP' }
    }

    It 'ne tue pas un client de jeu apparu juste après l''échéance' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $true }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'api'
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 0
    }

    It 'remonte la cause de l''échec du chemin rapide, pour que la mémoire la retienne' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'route'; StatusCode = 404; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $true }
        $launch = Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { }
        $launch.Outcome            | Should Be 'legacy'
        $launch.Failure.Kind       | Should Be 'route'
        $launch.Failure.StatusCode | Should Be 404
        $launch.Failure.Stage      | Should Be 'launch'
    }

    It 'ne retient aucune cause quand l''API a réussi' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        (Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { }).Failure | Should BeNullOrEmpty
    }

    It 'signale l''échec quand même le chemin historique ne peut pas démarrer le Riot Client' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $false }
        Start-LeagueClient -Path 'C:\perime\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'failed'
    }

    It 'prend directement le chemin historique avec -NoLocalApi, sans rien tenter par l''API' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $true; Failure = $null } }
        Mock Start-LeagueClientByCommandLine { return $true }
        Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -NoLocalApi -OnTick { } | Select-Object -ExpandProperty Outcome | Should Be 'legacy'
        Assert-MockCalled Start-LeagueClientByLocalApi -Scope It -Exactly 0
        Assert-MockCalled Stop-GameClientProcesses -Scope It -Exactly 0
        Assert-MockCalled Start-LeagueClientByCommandLine -Scope It -Exactly 1
    }

    It 'n''interrompt jamais l''installation, même quand rien ne répond' {
        Mock Stop-GameClientProcesses { }
        Mock Start-LeagueClientByLocalApi { return [pscustomobject]@{ Success = $false; Failure = [pscustomobject]@{ Kind = 'timeout'; StatusCode = 464; Stage = 'launch' } } }
        Mock Test-GameClientRunning { return $false }
        Mock Start-LeagueClientByCommandLine { return $false }
        { Start-LeagueClient -Path 'C:\Riot\RiotClientServices.exe' -YamlPath 'C:\yaml' -Value 'ja_JP' -OnTick { } } | Should Not Throw
    }
}
