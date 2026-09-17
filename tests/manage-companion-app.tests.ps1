<#
.SYNOPSIS
    Tests Pester 3.4 de manage-companion-app.ps1 — le script est dot-sourcé, son bloc Main est ignoré.
    Aucun installeur, désinstalleur ni accès réseau réel : tout est mocké.
    Rappel Pester 3 : un Mock déclaré dans un It survit jusqu'à la fin du Describe → re-déclarer quand l'ordre compte.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\manage-companion-app.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

# Les textes attendus sont français quelle que soit la langue de Windows sur la machine de test
Initialize-Translation 'fr' | Out-Null

function New-TestOptions([hashtable]$Overrides = @{}) {
    $options = @{
        RequestedIds = @(); HasRequest = $false; UninstallOthers = $false; Force = $false; DryRun = $false
        ConfigPath = ''; CatalogPath = (Join-Path $here '..\app\companion-apps.json')
    }
    foreach ($key in $Overrides.Keys) { $options[$key] = $Overrides[$key] }
    return $options
}

function New-TestChoice([string[]]$Ids, [bool]$UninstallOthers = $false) {
    return @{ SelectedIds = $Ids; UninstallOthers = $UninstallOthers }
}

# ---------------------------------------------------------------- Actions

Describe 'Get-CompanionActions' {
    $porofessor = New-TestCompanionApp -Id 'porofessor'
    $blitz      = New-TestCompanionApp -Id 'blitz'
    $opgg       = New-TestCompanionApp -Id 'opgg'
    $catalog    = @($porofessor, $blitz, $opgg)

    It 'installe les applis cochées absentes et garde celles déjà présentes' {
        $actions = Get-CompanionActions $catalog @(New-TestInstalledApp $blitz) (New-TestChoice @('blitz', 'opgg'))
        ($actions.Selected | ForEach-Object { $_.id }) -join ',' | Should Be 'blitz,opgg'
        ($actions.Install | ForEach-Object { $_.id }) -join ',' | Should Be 'opgg'
        $actions.Uninstall.Count | Should Be 0
    }

    It 'ne désinstalle rien par défaut, même si des applis décochées sont présentes' {
        $actions = Get-CompanionActions $catalog @((New-TestInstalledApp $blitz), (New-TestInstalledApp $opgg)) (New-TestChoice @('blitz'))
        $actions.Uninstall.Count | Should Be 0
        $actions.Install.Count | Should Be 0
    }

    It 'désinstalle les applis décochées présentes quand l''utilisateur l''a demandé' {
        $actions = Get-CompanionActions $catalog @((New-TestInstalledApp $porofessor), (New-TestInstalledApp $opgg)) (New-TestChoice @('blitz') $true)
        ($actions.Uninstall | ForEach-Object { $_.App.id }) -join ',' | Should Be 'porofessor,opgg'
        ($actions.Install | ForEach-Object { $_.id }) -join ',' | Should Be 'blitz'
    }

    It 'ne fait rien quand la sélection est vide sans demande de désinstallation' {
        $actions = Get-CompanionActions $catalog @(New-TestInstalledApp $blitz) (New-TestChoice @())
        $actions.Selected.Count | Should Be 0
        $actions.Install.Count | Should Be 0
        $actions.Uninstall.Count | Should Be 0
    }

    It 'rend des tableaux vides sur une machine vierge où rien n''est coché' {
        $actions = Get-CompanionActions $catalog @() (New-TestChoice @())
        $actions.Install.Count | Should Be 0
        $actions.Uninstall.Count | Should Be 0
    }

    It 'ordonne la sélection selon le catalogue, pas selon la saisie' {
        $actions = Get-CompanionActions $catalog @() (New-TestChoice @('opgg', 'porofessor'))
        ($actions.Selected | ForEach-Object { $_.id }) -join ',' | Should Be 'porofessor,opgg'
    }
}

Describe 'Format-CompanionActions' {
    It 'affiche la notice de désinstallation quand l''appli en a une' {
        $poro    = New-TestCompanionApp -Id 'porofessor' -Mode 'interactive' -Notice 'Décochez Overwolf'
        $actions = Get-CompanionActions @($poro, (New-TestCompanionApp -Id 'blitz')) @(New-TestInstalledApp $poro) (New-TestChoice @('blitz') $true)
        $text    = Format-CompanionActions $actions
        $text | Should Match 'Désinstaller porofessor'
        $text | Should Match 'Décochez Overwolf'
        $text | Should Match 'Installer blitz'
    }

    It 'affiche la notice d''installation quand l''appli en a une' {
        $poro = New-TestCompanionApp -Id 'porofessor'
        $poro.install | Add-Member -NotePropertyName notice -NotePropertyValue 'Suivez les étapes Overwolf' -Force
        Format-CompanionActions (Get-CompanionActions @($poro) @() (New-TestChoice @('porofessor'))) | Should Match 'Suivez les étapes Overwolf'
    }

    It 'indique qu''il n''y a rien à faire' {
        Format-CompanionActions (Get-CompanionActions @(New-TestCompanionApp -Id 'blitz') @() (New-TestChoice @())) | Should Match 'Aucune installation'
    }

    It 'affiche la notice dans la langue active quand le catalogue la traduit' {
        $poro = New-TestCompanionApp -Id 'porofessor'
        $poro.install | Add-Member -NotePropertyName notice -NotePropertyValue ([pscustomobject]@{ fr = 'Suivez Overwolf'; en = 'Follow Overwolf' }) -Force
        $actions = Get-CompanionActions @($poro) @() (New-TestChoice @('porofessor'))
        try {
            Format-CompanionActions $actions | Should Match 'Suivez Overwolf'
            Initialize-Translation 'en' | Out-Null
            $text = Format-CompanionActions $actions
            $text | Should Match '- Install porofessor'
            $text | Should Match 'Follow Overwolf'
            Initialize-Translation 'ja' | Out-Null
            Format-CompanionActions $actions | Should Match 'Follow Overwolf'
        }
        finally { Initialize-Translation 'fr' | Out-Null }
    }
}

Describe 'Get-PreselectedCompanionIds' {
    $catalog = @((New-TestCompanionApp -Id 'blitz'), (New-TestCompanionApp -Id 'opgg'))

    It 'reprend le choix précédent de config.json plutôt que la détection' {
        $config = [pscustomobject]@{ companionApps = @([pscustomobject]@{ id = 'opgg' }) }
        (Get-PreselectedCompanionIds $catalog @(New-TestInstalledApp $catalog[0]) $config) -join ',' | Should Be 'opgg'
    }

    It 'retombe sur les applis détectées quand config.json n''en liste aucune' {
        $config = [pscustomobject]@{ companionApps = @() }
        (Get-PreselectedCompanionIds $catalog @(New-TestInstalledApp $catalog[0]) $config) -join ',' | Should Be 'blitz'
    }

    It 'ignore une entrée de config.json absente du catalogue' {
        $config = [pscustomobject]@{ companionApps = @([pscustomobject]@{ id = 'inconnue' }) }
        (Get-PreselectedCompanionIds $catalog @() $config).Count | Should Be 0
    }
}

Describe 'Resolve-CompanionChoice' {
    $catalog = @((New-TestCompanionApp -Id 'blitz'), (New-TestCompanionApp -Id 'opgg'))
    $config  = [pscustomobject]@{ companionApps = @() }
    Mock Show-CompanionPicker { param($Catalog, $Installed, $PreselectedIds) return @{ SelectedIds = $PreselectedIds; UninstallOthers = $false } }

    It 'rejette un identifiant absent du catalogue' {
        { Resolve-CompanionChoice $catalog @() $config (New-TestOptions @{ HasRequest = $true; RequestedIds = @('mobalytics') }) } | Should Throw
    }

    It 'accepte « none » comme sélection vide sans ouvrir le dialogue' {
        (Resolve-CompanionChoice $catalog @() $config (New-TestOptions @{ HasRequest = $true; RequestedIds = @('none') })).SelectedIds.Count | Should Be 0
        Assert-MockCalled -Scope It Show-CompanionPicker -Exactly -Times 0
    }

    It 'découpe une liste passée en une seule chaîne "blitz,opgg"' {
        $choice = Resolve-CompanionChoice $catalog @() $config (New-TestOptions @{ HasRequest = $true; RequestedIds = @('blitz,opgg'); UninstallOthers = $true })
        $choice.SelectedIds -join ',' | Should Be 'blitz,opgg'
        $choice.UninstallOthers | Should Be $true
    }

    It 'ouvre le dialogue pré-coché sur les applis détectées quand rien n''est demandé' {
        $choice = Resolve-CompanionChoice $catalog @(New-TestInstalledApp $catalog[1]) $config (New-TestOptions)
        $choice.SelectedIds -join ',' | Should Be 'opgg'
        Assert-MockCalled -Scope It Show-CompanionPicker -Exactly -Times 1
    }
}

# ---------------------------------------------------------------- Process

Describe 'Start-CompanionProcess' {
    Mock Wait-WithAnimation {}

    It 'rend le code de sortie du process direct' {
        Mock Start-Process { [pscustomobject]@{ HasExited = $true; ExitCode = 7 } }
        Start-CompanionProcess 'x.exe' '/S' 10 | Should Be 7
    }

    It 'omet ArgumentList quand il n''y a pas d''arguments' {
        Mock Start-Process { [pscustomobject]@{ HasExited = $true; ExitCode = 0 } }
        Start-CompanionProcess 'x.exe' '' 10 | Out-Null
        Assert-MockCalled -Scope It Start-Process -Exactly -Times 1 -ParameterFilter { $null -eq $ArgumentList -and $PassThru }
    }

    It 'rend null sans bloquer quand le process ne rend pas la main dans le délai' {
        Mock Start-Process { [pscustomobject]@{ HasExited = $false; ExitCode = $null } }
        Start-CompanionProcess 'x.exe' '' 0 | Should BeNullOrEmpty
    }
}

# ---------------------------------------------------------------- Désinstallation

Describe 'Resolve-TrustedCompanionUninstaller' {
    It 'rend null sans commande dans le registre' {
        Resolve-TrustedCompanionUninstaller (New-TestInstalledApp (New-TestCompanionApp) (New-RegistryEntry 'App' '')) | Should BeNullOrEmpty
    }

    It 'rend null si le désinstalleur n''est pas signé par l''éditeur attendu' {
        Mock Test-CompanionBinaryTrusted { $false }
        Resolve-TrustedCompanionUninstaller (New-TestInstalledApp (New-TestCompanionApp)) | Should BeNullOrEmpty
    }

    It 'rend chemin et arguments d''un désinstalleur de confiance' {
        Mock Test-CompanionBinaryTrusted { $true }
        $command = Resolve-TrustedCompanionUninstaller (New-TestInstalledApp (New-TestCompanionApp))
        $command.Path | Should Be 'C:\Apps\u.exe'
        $command.Arguments | Should Be '/S'
    }
}

Describe 'Uninstall-CompanionApp' {
    Mock Start-CompanionProcess { 0 }
    Mock Stop-CompanionProcesses {}
    Mock Wait-CompanionUninstalled { $true }
    Mock Set-SplashVisible {}

    It 'refuse et ne lance rien quand le désinstalleur n''est pas de confiance' {
        Mock Resolve-TrustedCompanionUninstaller { $null }
        Uninstall-CompanionApp (New-TestInstalledApp (New-TestCompanionApp)) | Should Be $false
        Assert-MockCalled -Scope It Start-CompanionProcess -Exactly -Times 0
    }

    It 'ferme l''appli, lance le désinstalleur de confiance et attend sa disparition' {
        Mock Resolve-TrustedCompanionUninstaller { @{ Path = 'C:\Apps\u.exe'; Arguments = '/S' } }
        Uninstall-CompanionApp (New-TestInstalledApp (New-TestCompanionApp -ProcessNames @('App'))) | Should Be $true
        Assert-MockCalled -Scope It Stop-CompanionProcesses -Exactly -Times 1
        Assert-MockCalled -Scope It Start-CompanionProcess -Exactly -Times 1 -ParameterFilter { $Path -eq 'C:\Apps\u.exe' -and $Arguments -eq '/S' }
        Assert-MockCalled -Scope It Set-SplashVisible -Exactly -Times 0
    }

    It 'rend faux si l''appli est toujours présente après l''attente' {
        Mock Resolve-TrustedCompanionUninstaller { @{ Path = 'C:\Apps\u.exe'; Arguments = '/S' } }
        Mock Wait-CompanionUninstalled { $false }
        Uninstall-CompanionApp (New-TestInstalledApp (New-TestCompanionApp)) | Should Be $false
    }

    It 'masque le splash pendant le dialogue de l''éditeur puis le réaffiche (mode interactif)' {
        Mock Resolve-TrustedCompanionUninstaller { @{ Path = 'C:\Apps\u.exe'; Arguments = '' } }
        Mock Wait-CompanionUninstalled { $true }
        Uninstall-CompanionApp (New-TestInstalledApp (New-TestCompanionApp -Id 'porofessor' -Mode 'interactive')) | Should Be $true
        Assert-MockCalled -Scope It Set-SplashVisible -Exactly -Times 1 -ParameterFilter { $Visible -eq $false }
        Assert-MockCalled -Scope It Set-SplashVisible -Exactly -Times 1 -ParameterFilter { $Visible -eq $true }
    }
}

Describe 'Wait-CompanionInteractiveUninstall' {
    Mock Wait-WithAnimation {}
    $poro = New-TestCompanionApp -Id 'porofessor' -Mode 'interactive' -DialogProcessNames @('OWUninstallMenu')

    It 'attend l''apparition puis la fermeture du dialogue avant la sonde finale' {
        $script:dialogPolls = 0
        Mock Test-CompanionInstalled { $true }
        Mock Test-CompanionDialogOpen { $script:dialogPolls++; return ($script:dialogPolls -in 2..4) }
        Mock Wait-CompanionState { $true }
        Wait-CompanionInteractiveUninstall $poro | Should Be $true
        Assert-MockCalled -Scope It Wait-CompanionState -Exactly -Times 1 -ParameterFilter { $Installed -eq $false }
        $script:dialogPolls | Should BeGreaterThan 4
    }

    It 'court-circuite l''attente du dialogue dès que l''appli a disparu' {
        Mock Test-CompanionInstalled { $false }
        Mock Test-CompanionDialogOpen { $false }
        Mock Wait-CompanionState { $true }
        Wait-CompanionInteractiveUninstall $poro | Should Be $true
        Assert-MockCalled -Scope It Wait-WithAnimation -Exactly -Times 0
    }

    It 'rend faux quand l''utilisateur a fermé le dialogue sans désinstaller' {
        Mock Test-CompanionInstalled { $true }
        Mock Test-CompanionDialogOpen { $false }
        Mock Wait-CompanionState { $false }
        Wait-CompanionInteractiveUninstall $poro | Should Be $false
    }
}

Describe 'Test-CompanionDialogOpen' {
    It 'rend faux sans process de dialogue déclaré' {
        Test-CompanionDialogOpen (New-TestCompanionApp) | Should Be $false
    }
}

# ---------------------------------------------------------------- Installation

Describe 'Start-CompanionInstaller' {
    Mock Set-SplashTopMost {}

    It 'retire le premier plan du splash pendant l''installeur puis le rétablit' {
        Mock Start-CompanionProcess { 0 }
        Start-CompanionInstaller 'x.exe' '/S' 10 | Should Be 0
        Assert-MockCalled -Scope It Set-SplashTopMost -Exactly -Times 1 -ParameterFilter { $TopMost -eq $false }
        Assert-MockCalled -Scope It Set-SplashTopMost -Exactly -Times 1 -ParameterFilter { $TopMost -eq $true }
    }

    It 'rétablit le premier plan même si le lancement échoue' {
        Mock Start-CompanionProcess { throw 'introuvable' }
        { Start-CompanionInstaller 'x.exe' '/S' 10 } | Should Throw
        Assert-MockCalled -Scope It Set-SplashTopMost -Exactly -Times 1 -ParameterFilter { $TopMost -eq $true }
    }
}

Describe 'Install-CompanionViaWinget' {
    $blitz = New-TestCompanionApp -Id 'blitz' -Strategy 'winget'
    Mock Set-SplashTopMost {}

    It 'refuse quand winget est absent' {
        Mock Get-CompanionWingetPath { $null }
        Mock Start-CompanionInstaller { 0 }
        Install-CompanionViaWinget $blitz | Should Be $false
        Assert-MockCalled -Scope It Start-CompanionInstaller -Exactly -Times 0
    }

    It 'lance winget par son chemin résolu, source épinglée, puis attend l''installation' {
        Mock Get-CompanionWingetPath { 'C:\winget.exe' }
        Mock Start-CompanionInstaller { 0 }
        Mock Wait-CompanionState { $true }
        Install-CompanionViaWinget $blitz | Should Be $true
        Assert-MockCalled -Scope It Start-CompanionInstaller -Exactly -Times 1 -ParameterFilter { $Path -eq 'C:\winget.exe' -and $Arguments -match '^install --id Vendor\.App --exact --silent --source winget' }
        Assert-MockCalled -Scope It Wait-CompanionState -Exactly -Times 1 -ParameterFilter { $Installed -eq $true -and $TimeoutSeconds -eq 30 }
    }

    It 'sonde brièvement puis abandonne quand winget échoue' {
        Mock Get-CompanionWingetPath { 'C:\winget.exe' }
        Mock Start-CompanionInstaller { 1 }
        Mock Wait-CompanionState { $false }
        Install-CompanionViaWinget $blitz | Should Be $false
        Assert-MockCalled -Scope It Wait-CompanionState -Exactly -Times 1 -ParameterFilter { $TimeoutSeconds -eq $WingetFailureProbeSeconds }
    }
}

Describe 'Invoke-CompanionDownload' {
    # Vrais jobs locaux sans réseau : le job de téléchargement est remplacé par un job trivial
    Mock Wait-WithAnimation {}

    It 'attend la fin du job et rend la main sans erreur' {
        Mock New-CompanionDownloadJob { Start-Job -ScriptBlock { 'ok' } }
        { Invoke-CompanionDownload 'https://example.test/a.exe' 'C:\tmp\a.exe' } | Should Not Throw
    }

    It 'lève une erreur si le job a échoué' {
        Mock New-CompanionDownloadJob { Start-Job -ScriptBlock { throw 'réseau' } }
        { Invoke-CompanionDownload 'https://example.test/a.exe' 'C:\tmp\a.exe' } | Should Throw
    }

    It 'arrête le job et lève une erreur au-delà du délai' {
        $DownloadTimeoutSeconds = 0
        Mock New-CompanionDownloadJob { Start-Job -ScriptBlock { Start-Sleep 30 } }
        { Invoke-CompanionDownload 'https://example.test/a.exe' 'C:\tmp\a.exe' } | Should Throw
        @(Get-Job | Where-Object { $_.State -eq 'Running' }).Count | Should Be 0
    }
}

Describe 'Install-CompanionViaDownload' {
    Mock Invoke-CompanionDownload {}
    Mock Start-CompanionInstaller { 0 }
    Mock Remove-Item {}
    Mock New-CompanionDownloadPath { 'C:\tmp\rnd\companion-opgg-x.exe' }
    $opgg = New-TestCompanionApp -Id 'opgg'

    It 'refuse un installeur dont la signature n''est pas celle de l''éditeur' {
        Mock Test-CompanionBinaryTrusted { $false }
        Install-CompanionViaDownload $opgg | Should Be $false
        Assert-MockCalled -Scope It Start-CompanionInstaller -Exactly -Times 0
    }

    It 'exécute l''installeur signé avec ses arguments puis attend l''installation' {
        Mock Test-CompanionBinaryTrusted { $true }
        Mock Wait-CompanionState { $true }
        Install-CompanionViaDownload $opgg | Should Be $true
        Assert-MockCalled -Scope It Invoke-CompanionDownload -Exactly -Times 1 -ParameterFilter { $Url -eq 'https://example.test/setup.exe' }
        Assert-MockCalled -Scope It Start-CompanionInstaller -Exactly -Times 1 -ParameterFilter { $Arguments -eq '/S' -and $TimeoutSeconds -eq 30 }
    }

    It 'supprime le dossier temporaire même quand l''installation est refusée' {
        Mock Test-CompanionBinaryTrusted { $false }
        Install-CompanionViaDownload $opgg | Out-Null
        Assert-MockCalled -Scope It Remove-Item -Exactly -Times 1 -ParameterFilter { $Path -eq 'C:\tmp\rnd' }
    }
}

Describe 'New-CompanionDownloadPath' {
    It 'produit un chemin dans un sous-dossier aléatoire de TEMP, sans le mot installer' {
        $path = New-CompanionDownloadPath 'opgg'
        $path | Should Match ([regex]::Escape($env:TEMP))
        (Split-Path $path -Leaf) | Should Not Match 'install|setup'
        Remove-Item (Split-Path $path -Parent) -Recurse -Force
    }
}

Describe 'Install-CompanionApp' {
    Mock Install-CompanionViaBrowser { $false }
    Mock Stop-CompanionProcesses {}

    It 'rend vrai sans repli quand l''installation réussit' {
        Mock Install-CompanionViaWinget { $true }
        Install-CompanionApp (New-TestCompanionApp -Strategy 'winget') | Should Be $true
        Assert-MockCalled -Scope It Install-CompanionViaBrowser -Exactly -Times 0
    }

    It 'ferme l''appli si l''installeur l''a lancée (elle démarre avec le jeu, pas maintenant)' {
        Mock Install-CompanionViaDownload { $true }
        Install-CompanionApp (New-TestCompanionApp -Strategy 'download' -ProcessNames @('App')) | Out-Null
        Assert-MockCalled -Scope It Stop-CompanionProcesses -Exactly -Times 1
    }

    It 'replie sur le navigateur quand winget échoue' {
        Mock Install-CompanionViaWinget { $false }
        Install-CompanionApp (New-TestCompanionApp -Strategy 'winget' -Fallback 'browser') | Should Be $false
        Assert-MockCalled -Scope It Install-CompanionViaBrowser -Exactly -Times 1
        Assert-MockCalled -Scope It Stop-CompanionProcesses -Exactly -Times 0
    }

    It 'replie aussi quand le téléchargement lève une exception' {
        Mock Install-CompanionViaDownload { throw 'réseau indisponible' }
        Install-CompanionApp (New-TestCompanionApp -Strategy 'download' -Fallback 'browser') | Should Be $false
        Assert-MockCalled -Scope It Install-CompanionViaBrowser -Exactly -Times 1
    }

    It 'absorbe aussi une exception du repli' {
        Mock Install-CompanionViaWinget { $false }
        Mock Install-CompanionViaBrowser { throw 'pas de navigateur' }
        { Install-CompanionApp (New-TestCompanionApp -Strategy 'winget' -Fallback 'browser') } | Should Not Throw
    }

    It 'ne replie pas sans stratégie de repli' {
        Mock Install-CompanionViaWinget { $false }
        Mock Install-CompanionViaBrowser { $false }
        Install-CompanionApp (New-TestCompanionApp -Strategy 'winget' -Fallback '') | Should Be $false
        Assert-MockCalled -Scope It Install-CompanionViaBrowser -Exactly -Times 0
    }
}

# ---------------------------------------------------------------- config.json

Describe 'Write-CompanionConfig' {
    AfterEach { Remove-TestTempFiles }

    It 'écrit la liste des applis choisies et conserve les chemins Riot' {
        $path   = New-TempConfig
        $config = Read-LaunchConfig $path
        Write-CompanionConfig $config $path @((New-TestCompanionApp -Id 'blitz'), (New-TestCompanionApp -Id 'opgg')) | Should Be $true
        $again = Read-LaunchConfig $path
        $again.riotClientPath | Should Be 'C:\Riot\RiotClientServices.exe'
        (@($again.companionApps) | ForEach-Object { $_.id }) -join ',' | Should Be 'blitz,opgg'
        $again.companionApps[0].path | Should Be "$env:TEMP\app.exe"
    }

    It 'vide la liste quand aucune appli n''est choisie' {
        $path   = New-TempLegacyConfig
        $config = Read-LaunchConfig $path
        Write-CompanionConfig $config $path @() | Should Be $true
        @((Read-LaunchConfig $path).companionApps).Count | Should Be 0
    }

    It 'ne réécrit pas un fichier dont la liste ne change pas' {
        $path   = New-TempConfig ('[' + ((ConvertTo-LaunchCompanionEntry (New-TestCompanionApp -Id 'blitz')) | ConvertTo-Json) + ']')
        $before = (Get-Item $path).LastWriteTimeUtc
        $config = Read-LaunchConfig $path
        Write-CompanionConfig $config $path @(New-TestCompanionApp -Id 'blitz') | Should Be $false
        (Get-Item $path).LastWriteTimeUtc | Should Be $before
    }
}

# ---------------------------------------------------------------- Orchestration

Describe 'Invoke-CompanionActions' {
    Mock New-SplashWindow { $null }
    Mock Close-SplashWindow {}
    $catalog = @((New-TestCompanionApp -Id 'porofessor'), (New-TestCompanionApp -Id 'opgg'), (New-TestCompanionApp -Id 'blitz'))

    It 'ouvre le splash, désinstalle puis installe, et ferme le splash' {
        Mock Uninstall-CompanionApp { $true }
        Mock Install-CompanionApp { $true }
        $actions = Get-CompanionActions $catalog @(New-TestInstalledApp $catalog[0]) (New-TestChoice @('blitz') $true)
        $result  = Invoke-CompanionActions $actions
        $result.UninstallFailed.Count | Should Be 0
        $result.InstallFailed.Count | Should Be 0
        Assert-MockCalled -Scope It Uninstall-CompanionApp -Exactly -Times 1
        Assert-MockCalled -Scope It Install-CompanionApp -Exactly -Times 1
        Assert-MockCalled -Scope It New-SplashWindow -Exactly -Times 1
        Assert-MockCalled -Scope It Close-SplashWindow -Exactly -Times 1
    }

    It 'n''installe rien quand une désinstallation a échoué' {
        Mock Uninstall-CompanionApp { $false }
        Mock Install-CompanionApp { $true }
        $actions = Get-CompanionActions $catalog @(New-TestInstalledApp $catalog[0]) (New-TestChoice @('blitz') $true)
        $result  = Invoke-CompanionActions $actions
        $result.UninstallFailed -join ',' | Should Be 'porofessor'
        Assert-MockCalled -Scope It Install-CompanionApp -Exactly -Times 0
    }

    It 'liste les installations échouées' {
        Mock Uninstall-CompanionApp { $true }
        Mock Install-CompanionApp { $false }
        $actions = Get-CompanionActions $catalog @() (New-TestChoice @('blitz', 'opgg'))
        (Invoke-CompanionActions $actions).InstallFailed -join ',' | Should Be 'opgg,blitz'
    }

    It 'ferme le splash même si une action lève une erreur' {
        Mock Uninstall-CompanionApp { $true }
        Mock Install-CompanionApp { throw 'boom' }
        $actions = Get-CompanionActions $catalog @() (New-TestChoice @('blitz'))
        { Invoke-CompanionActions $actions } | Should Throw
        Assert-MockCalled -Scope It Close-SplashWindow -Exactly -Times 1
    }
}

Describe 'Invoke-CompanionManagement' {
    AfterEach { Remove-TestTempFiles }
    Mock Test-CompanionElevated { $false }
    Mock Get-InstalledCompanionApps { @() }
    Mock Invoke-CompanionActions { @{ UninstallFailed = @(); InstallFailed = @() } }
    Mock Write-CompanionConfig { $true }
    Mock Confirm-CompanionActions { $true }

    It 'refuse de tourner élevé' {
        Mock Test-CompanionElevated { $true }
        { Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) } | Should Throw
    }

    It 'échoue si config.json est absent' {
        Mock Test-CompanionElevated { $false }
        { Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = 'C:\introuvable\config.json' }) } | Should Throw
    }

    It 'sort en 2 quand l''utilisateur annule le dialogue' {
        Mock Test-CompanionElevated { $false }
        Mock Resolve-CompanionChoice { $null }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) | Should Be 2
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 0
    }

    It 'en DryRun, n''exécute rien et n''écrit pas config.json' {
        Mock Test-CompanionElevated { $false }
        Mock Resolve-CompanionChoice { New-TestChoice @('blitz') }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig); DryRun = $true }) | Should Be 0
        Assert-MockCalled -Scope It Invoke-CompanionActions -Exactly -Times 0
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 0
    }

    It 'sort en 2 sans rien faire quand la confirmation est refusée' {
        Mock Test-CompanionElevated { $false }
        Mock Resolve-CompanionChoice { New-TestChoice @('blitz') }
        Mock Confirm-CompanionActions { $false }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) | Should Be 2
        Assert-MockCalled -Scope It Invoke-CompanionActions -Exactly -Times 0
    }

    It 'exécute les actions, écrit config.json et sort en 0 une fois confirmé' {
        Mock Test-CompanionElevated { $false }
        Mock Resolve-CompanionChoice { New-TestChoice @('blitz') }
        Mock Confirm-CompanionActions { $true }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) | Should Be 0
        Assert-MockCalled -Scope It Invoke-CompanionActions -Exactly -Times 1
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 1 -ParameterFilter { ($SelectedApps | ForEach-Object { $_.id }) -join ',' -eq 'blitz' }
    }

    It 'sort en 2 et n''écrit pas config.json quand une désinstallation a échoué' {
        Mock Test-CompanionElevated { $false }
        Mock Get-InstalledCompanionApps { @(New-TestInstalledApp (New-TestCompanionApp -Id 'opgg')) }
        Mock Resolve-CompanionChoice { New-TestChoice @('blitz') $true }
        Mock Confirm-CompanionActions { $true }
        Mock Invoke-CompanionActions { @{ UninstallFailed = @('opgg'); InstallFailed = @() } }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) | Should Be 2
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 0
    }

    It 'ne demande pas de confirmation ni d''action quand rien ne change, mais aligne config.json' {
        Mock Test-CompanionElevated { $false }
        Mock Get-InstalledCompanionApps { @() }
        Mock Resolve-CompanionChoice { New-TestChoice @() }
        Mock Confirm-CompanionActions { $true }
        Mock Invoke-CompanionActions { @{ UninstallFailed = @(); InstallFailed = @() } }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig) }) | Should Be 0
        Assert-MockCalled -Scope It Confirm-CompanionActions -Exactly -Times 0
        Assert-MockCalled -Scope It Invoke-CompanionActions -Exactly -Times 0
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 1
    }

    It 'avec Force, n''ouvre pas de confirmation' {
        Mock Test-CompanionElevated { $false }
        Mock Resolve-CompanionChoice { New-TestChoice @('opgg') }
        Mock Confirm-CompanionActions { $true }
        Mock Invoke-CompanionActions { @{ UninstallFailed = @(); InstallFailed = @() } }
        Invoke-CompanionManagement (New-TestOptions @{ ConfigPath = (New-TempConfig); Force = $true }) | Should Be 0
        Assert-MockCalled -Scope It Confirm-CompanionActions -Exactly -Times 0
        Assert-MockCalled -Scope It Invoke-CompanionActions -Exactly -Times 1
    }
}
