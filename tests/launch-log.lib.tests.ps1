<#
.SYNOPSIS
    Tests Pester 3.4 de lib\launch-log.lib.ps1 : journal horodaté du lanceur.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')

Describe 'Format-LaunchLogLine' {
    It 'horodate chaque ligne et aligne l''étape' {
        $line = Format-LaunchLogLine 'API' 'POST /product-launcher/... -> 200'
        $line | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}  API'
        $line | Should Match 'POST /product-launcher/\.\.\. -> 200$'
    }

    It 'tient sur une seule ligne, quel que soit le détail' {
        (Format-LaunchLogLine 'END' 'issue=api duree=10,4s') -split "`n" | Should Not BeNullOrEmpty
        ((Format-LaunchLogLine 'END' 'issue=api') -split "`n").Count | Should Be 1
    }
}

Describe 'Write-LaunchLogLine' {
    AfterEach { Set-LaunchLogPath '' }

    It 'ajoute les lignes à la suite, sans écraser les précédentes' {
        $path = Join-Path $TestDrive 'launch.log'
        Set-LaunchLogPath $path
        Write-LaunchLogLine 'START' 'locale=ja_JP' | Should Be $true
        Write-LaunchLogLine 'END' 'issue=api'      | Should Be $true
        $lines = @(Get-Content $path)
        $lines.Count | Should Be 2
        $lines[0] | Should Match 'START'
        $lines[1] | Should Match 'END'
    }

    It 'ne journalise rien tant qu''aucun chemin n''est défini' {
        Write-LaunchLogLine 'START' 'locale=ja_JP' | Should Be $false
    }

    It 'ne fait jamais échouer un lancement quand le dossier refuse l''écriture' {
        Set-LaunchLogPath 'C:\interdit\sous\dossier\launch.log'
        Write-LaunchLogLine 'START' 'locale=ja_JP' | Should Be $false
    }

    It 'n''écrit jamais le mot de passe du lockfile — seuls la méthode, le chemin et le code' {
        $path = Join-Path $TestDrive 'launch-secret.log'
        Set-LaunchLogPath $path
        Write-LaunchLogLine 'API' 'PUT /riotclient/product-locales/products/league_of_legends/patchlines/live -> 201'
        (Get-Content $path -Raw) -match 'mot-de-passe|Authorization|Basic ' | Should Be $false
    }
}

Describe 'Limit-LaunchLogSize' {
    It 'laisse intact un journal de taille raisonnable' {
        $path = Join-Path $TestDrive 'petit.log'
        Set-Content $path 'une ligne' -Encoding UTF8
        Limit-LaunchLogSize $path | Should Be $false
        @(Get-Content $path).Count | Should Be 1
    }

    It 'écarte la moitié la plus ancienne d''un journal trop gros, sur des lignes entières' {
        $path = Join-Path $TestDrive 'gros.log'
        $lines = 1..4000 | ForEach-Object { '2026-09-20 02:45:11  API     ligne de journal numero {0}' -f $_ }
        Set-Content $path $lines -Encoding UTF8
        (Get-Item $path).Length -gt $LaunchLogMaxBytes | Should Be $true
        Limit-LaunchLogSize $path | Should Be $true
        $kept = @(Get-Content $path)
        $kept.Count | Should Be 2000
        $kept[0] | Should Match 'numero 2001$'
    }

    It 'ne bronche pas sur un journal absent' {
        Limit-LaunchLogSize (Join-Path $TestDrive 'jamais-ecrit.log') | Should Be $false
    }
}

Describe 'Get-RecentLaunchCount' {
    function New-LogAt([datetime]$At, [string]$Step, [string]$Detail) { return '{0}  {1,-7} {2}' -f $At.ToString('yyyy-MM-dd HH:mm:ss'), $Step, $Detail }
    $now = Get-Date

    It 'compte les lancements de la fenêtre, pas les plus anciens' {
        $path = Join-Path $TestDrive 'launch.log'
        @(
            (New-LogAt $now.AddMinutes(-9) 'START' 'locale=ja_JP companion=aucun chemin=rapide riot=139')
            (New-LogAt $now.AddMinutes(-4) 'START' 'locale=fr_FR companion=aucun chemin=rapide riot=139')
            (New-LogAt $now.AddMinutes(-4) 'API'   'PUT /x -> 201 en 0,1s')
            (New-LogAt $now.AddMinutes(-1) 'START' 'locale=ja_JP companion=aucun chemin=rapide riot=139')
        ) | Set-Content -Path $path -Encoding UTF8
        Get-RecentLaunchCount $path $now.AddMinutes(-5) | Should Be 2
    }

    It 'ignore un lancement refusé — il n''a pas démarré le jeu' {
        $path = Join-Path $TestDrive 'launch.log'
        @(
            (New-LogAt $now.AddMinutes(-2) 'START' 'locale=ja_JP companion=aucun chemin=rapide riot=139')
            (New-LogAt $now.AddMinutes(-1) 'START' 'refusé — lancement déjà en cours (locale=fr_FR demandée)')
        ) | Set-Content -Path $path -Encoding UTF8
        Get-RecentLaunchCount $path $now.AddMinutes(-5) | Should Be 1
    }

    It 'rend zéro sans journal' {
        Get-RecentLaunchCount (Join-Path $TestDrive 'absent.log') $now.AddMinutes(-5) | Should Be 0
    }

    It 'rend zéro sans lever d''exception sur une ligne mal formée' {
        $path = Join-Path $TestDrive 'launch.log'
        'n''importe quoi  START   locale=ja_JP' | Set-Content -Path $path -Encoding UTF8
        { Get-RecentLaunchCount $path $now.AddMinutes(-5) } | Should Not Throw
        Get-RecentLaunchCount $path $now.AddMinutes(-5) | Should Be 0
    }
}

Describe 'Format-LaunchLogDuration' {
    It 'rend une durée en secondes, à la décimale' {
        Format-LaunchLogDuration ([pscustomobject]@{ Elapsed = [timespan]::FromSeconds(10.44) }) | Should Match '^10[.,]4s$'
    }
}
