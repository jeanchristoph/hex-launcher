<#
.SYNOPSIS
    Tests Pester 3.4 de install.ps1 — le script est dot-sourcé, son bloc Main est ignoré : aucune fenêtre n'est affichée.
    Machine à états, résumés et orchestration des pages sont testés sans WinForms ; le moteur (installeurs,
    raccourcis, config.json) est mocké.
    Rappel Pester 3 : un Mock déclaré dans un It survit jusqu'à la fin du Describe → re-déclarer quand l'ordre compte.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\install.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

function New-TestLaunchConfig([object[]]$CompanionApps = @(), [string]$RiotPath = 'C:\Riot\RiotClientServices.exe', [string]$YamlPath = 'C:\ProgramData\lol.yaml') {
    return [pscustomobject]@{ riotClientPath = $RiotPath; productSettingsPath = $YamlPath; companionApps = $CompanionApps }
}

function New-TestCompanionEntry([string]$Id, [string]$Name) {
    return [pscustomobject]@{ id = $Id; name = $Name; path = "C:\Apps\$Id.exe"; arguments = '' }
}

# Faux formulaire : seule la fermeture est observée
function New-FakeForm {
    $form = [pscustomobject]@{ IsClosed = $false }
    $form | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.IsClosed = $true }
    return $form
}

function Reset-InstallTestState([hashtable]$Overrides = @{}) {
    $script:InstallState.StepId            = 'detect'
    $script:InstallState.ExitCode          = 2
    $script:InstallState.IsBusy            = $false
    $script:InstallState.Form              = $null
    $script:InstallState.Config            = $null
    $script:InstallState.Catalog           = @()
    $script:InstallState.Installed         = @()
    $script:InstallState.ExistingShortcuts = @()
    $script:InstallState.ShortcutPaths     = @()
    $script:InstallState.Controls          = @{}
    foreach ($key in $Overrides.Keys) { $script:InstallState[$key] = $Overrides[$key] }
}

# ---------------------------------------------------------------- Machine à états

Describe 'Machine à états de l''assistant' {
    It 'enchaîne détection, applis compagnon, raccourcis puis terminé' {
        $InstallSteps -join ',' | Should Be 'detect,apps,shortcuts,done'
    }

    It 'numérote les étapes dans l''ordre et rend -1 pour une étape inconnue' {
        Get-InstallStepIndex 'detect' | Should Be 0
        Get-InstallStepIndex 'done' | Should Be 3
        Get-InstallStepIndex 'inconnue' | Should Be -1
    }

    It 'donne l''étape suivante et aucune après la dernière' {
        Get-NextInstallStep 'detect' | Should Be 'apps'
        Get-NextInstallStep 'shortcuts' | Should Be 'done'
        Get-NextInstallStep 'done' | Should BeNullOrEmpty
        Get-NextInstallStep 'inconnue' | Should BeNullOrEmpty
    }

    It 'donne l''étape précédente et aucune avant la première' {
        Get-PreviousInstallStep 'apps' | Should Be 'detect'
        Get-PreviousInstallStep 'detect' | Should BeNullOrEmpty
        Get-PreviousInstallStep 'inconnue' | Should BeNullOrEmpty
    }

    It 'autorise le retour depuis les pages intermédiaires seulement' {
        Test-CanGoBack 'detect' | Should Be $false
        Test-CanGoBack 'apps' | Should Be $true
        Test-CanGoBack 'shortcuts' | Should Be $true
    }

    It 'interdit le retour une fois terminé : tout est déjà appliqué' {
        Test-CanGoBack 'done' | Should Be $false
    }

    It 'qualifie chaque étape par rapport à l''étape courante' {
        Get-InstallStepStatus 'detect' 'apps' | Should Be 'Done'
        Get-InstallStepStatus 'apps' 'apps' | Should Be 'Current'
        Get-InstallStepStatus 'shortcuts' 'apps' | Should Be 'Upcoming'
    }

    It 'coche les étapes passées et laisse les autres telles quelles' {
        Get-InstallStepLabel 'detect' 'apps' | Should Be '✓ 1. Bienvenue'
        Get-InstallStepLabel 'apps' 'apps' | Should Be '2. Applis compagnon'
        Get-InstallStepLabel 'shortcuts' 'apps' | Should Be '3. Raccourcis'
        Get-InstallStepLabel 'done' 'done' | Should Be '4. Terminé'
    }

    It 'colore l''étape courante en or, les faites en cyan, les autres en gris' {
        Get-InstallStepColor 'Current' | Should Be 'Gold'
        Get-InstallStepColor 'Done' | Should Be 'Accent'
        Get-InstallStepColor 'Upcoming' | Should Be 'Muted'
    }

    It 'nomme le bouton principal selon ce que la page exécute' {
        Get-NextButtonText 'detect' | Should Be 'Suivant'
        Get-NextButtonText 'apps' | Should Be 'Appliquer'
        Get-NextButtonText 'shortcuts' | Should Be 'Appliquer'
        Get-NextButtonText 'done' | Should Be 'Fermer'
    }
}

Describe 'Get-InstallLayout' {
    $layout = Get-InstallLayout 784 521

    It 'place les boutons en bas de la zone cliente' {
        $layout.ButtonsTop + 34 | Should BeLessThan 522
        $layout.RuleTop | Should BeLessThan $layout.ButtonsTop
    }

    It 'fait tenir la page entre le titre et la barre de progression' {
        $layout.ContentTop + $layout.ContentHeight | Should BeLessThan ($layout.ProgressTop + 1)
        $layout.ContentLeft + $layout.ContentWidth | Should BeLessThan 785
    }

    It 'réserve la colonne des étapes à gauche de la page' {
        $layout.ContentLeft | Should BeGreaterThan $layout.SidebarWidth
    }
}

# ---------------------------------------------------------------- Listes à cocher

Describe 'Get-CheckedItemIds' {
    $ids = @('porofessor', 'blitz', 'opgg')

    It 'rend les identifiants cochés dans l''ordre de la liste' {
        (Get-CheckedItemIds $ids @(2, 0)) -join ',' | Should Be 'porofessor,opgg'
    }

    It 'rend une liste vide quand rien n''est coché' {
        (Get-CheckedItemIds $ids @()).Count | Should Be 0
    }

    It 'ajoute la case en cours de cochage (ItemCheck précède le changement)' {
        (Get-CheckedItemIds $ids @(0) 1 $true) -join ',' | Should Be 'porofessor,blitz'
    }

    It 'retire la case en cours de décochage' {
        (Get-CheckedItemIds $ids @(0, 2) 2 $false) -join ',' | Should Be 'porofessor'
    }
}

Describe 'New-InstallCheckedList' {
    $items = @(@{ Key = 'ja_JP'; Label = 'ja_JP   日本語' }, @{ Key = 'fr_FR'; Label = 'fr_FR   Français' })

    It 'pré-coche les clés demandées et les retrouve sans fenêtre' {
        $list = New-InstallCheckedList $items @('fr_FR') 0 0 200 100
        $list.Items.Count | Should Be 2
        (Get-InstallCheckedKeys $list) -join ',' | Should Be 'fr_FR'
    }

    It 'anticipe un cochage en attente' {
        $list = New-InstallCheckedList $items @('fr_FR') 0 0 200 100
        (Get-InstallCheckedKeys $list 0 $true) -join ',' | Should Be 'ja_JP,fr_FR'
    }

    It 'accepte une liste vide' {
        $list = New-InstallCheckedList @() @() 0 0 200 100
        (Get-InstallCheckedKeys $list).Count | Should Be 0
    }
}

Describe 'Éléments des listes' {
    It 'suffixe « (installée) » les applis du catalogue présentes' {
        $blitz = New-TestCompanionApp -Id 'blitz'
        $items = @(Get-CompanionListItems @($blitz, (New-TestCompanionApp -Id 'opgg')) @(New-TestInstalledApp $blitz))
        $items[0].Key | Should Be 'blitz'
        $items[0].Label | Should Match 'installée'
        $items[1].Label | Should Be 'opgg'
    }

    It 'affiche code et libellé natif pour une langue' {
        $items = @(Get-LocaleListItems @([pscustomobject]@{ code = 'ja_JP'; label = '日本語' }))
        $items[0].Key | Should Be 'ja_JP'
        $items[0].Label | Should Be 'ja_JP   日本語'
    }

    It 'affiche le nom d''une appli compagnon de config.json' {
        $items = @(Get-ShortcutCompanionListItems @(New-TestCompanionEntry 'opgg' 'OP.GG'))
        $items[0].Key | Should Be 'opgg'
        $items[0].Label | Should Be 'OP.GG'
    }
}

# ---------------------------------------------------------------- Détection

Describe 'Get-DetectionSummaryLines' {
    Mock Test-Path { $true }

    It 'affiche les chemins présents en crème, sans mention introuvable' {
        $lines = @(Get-DetectionSummaryLines (New-TestLaunchConfig))
        $lines.Count | Should Be 3
        $lines[0].Text | Should Be 'Riot Client : C:\Riot\RiotClientServices.exe'
        $lines[0].Color | Should Be 'Cream'
        $lines[1].Text | Should Be 'Fichier de langue de LoL : C:\ProgramData\lol.yaml'
        $lines[1].Color | Should Be 'Cream'
    }

    It 'signale en rouge un Riot Client introuvable' {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq 'C:\absent\RiotClientServices.exe' }
        $lines = @(Get-DetectionSummaryLines (New-TestLaunchConfig -RiotPath 'C:\absent\RiotClientServices.exe'))
        $lines[0].Color | Should Be 'Danger'
        $lines[0].Text | Should Match 'introuvable'
        $lines[1].Color | Should Be 'Cream'
    }

    It 'signale en rouge un fichier de langue absent en demandant si LoL est installé' {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq 'C:\absent\lol.yaml' }
        $lines = @(Get-DetectionSummaryLines (New-TestLaunchConfig -YamlPath 'C:\absent\lol.yaml'))
        $lines[1].Color | Should Be 'Danger'
        $lines[1].Text | Should Match 'League of Legends est-il installé'
    }

    It 'considère un chemin vide comme introuvable sans interroger le disque' {
        $lines = @(Get-DetectionSummaryLines (New-TestLaunchConfig -RiotPath ''))
        $lines[0].Color | Should Be 'Danger'
        Assert-MockCalled -Scope It Test-Path -Exactly -Times 0 -ParameterFilter { $Path -eq '' }
    }

    It 'indique « aucune » sans appli compagnon détectée' {
        $lines = @(Get-DetectionSummaryLines (New-TestLaunchConfig))
        $lines[2].Text | Should Be 'Applis compagnon déjà installées : aucune'
        $lines[2].Color | Should Be 'Cream'
    }

    It 'liste les noms des applis compagnon détectées' {
        $config = New-TestLaunchConfig @((New-TestCompanionEntry 'blitz' 'Blitz'), (New-TestCompanionEntry 'opgg' 'OP.GG'))
        (Get-DetectionSummaryLines $config)[2].Text | Should Be 'Applis compagnon déjà installées : Blitz, OP.GG'
    }
}

Describe 'Get-DetectionItems' {
    Mock Test-Path { $true }

    It 'décrit chaque élément avec libellé, valeur et statut « Trouvé » en accent' {
        $items = @(Get-DetectionItems (New-TestLaunchConfig))
        $items.Count | Should Be 3
        $items[0].Label | Should Be 'Riot Client'
        $items[0].Value | Should Be 'C:\Riot\RiotClientServices.exe'
        $items[0].Status | Should Be 'Trouvé'
        $items[0].Color | Should Be 'Accent'
    }

    It 'explique quoi faire quand un chemin manque' {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq 'C:\absent\RiotClientServices.exe' }
        $items = @(Get-DetectionItems (New-TestLaunchConfig -RiotPath 'C:\absent\RiotClientServices.exe'))
        $items[0].Color | Should Be 'Danger'
        $items[0].Status | Should Match 'config.json'
    }

    It 'ne donne pas de statut à la ligne des applis compagnon' {
        $items = @(Get-DetectionItems (New-TestLaunchConfig))
        $items[2].Status | Should Be ''
    }
}

Describe 'Get-ConfigStatusText' {
    It 'rassure quand les réglages existants sont conservés' {
        Get-ConfigStatusText $false 'C:\x\config.json' | Should Match 'conservés'
    }

    It 'annonce la création du fichier de réglages' {
        Get-ConfigStatusText $true 'C:\x\config.json' | Should Match 'créé'
    }
}


Describe 'Initialize-InstallConfig' {
    AfterEach { Remove-TestTempFiles }
    Mock Write-LaunchConfig {}
    Mock New-LaunchConfig { [ordered]@{ riotClientPath = 'C:\r.exe'; productSettingsPath = 'C:\y'; companionApps = @() } }

    It 'génère config.json quand il manque, puis le relit' {
        Mock Read-LaunchConfig { New-TestLaunchConfig }
        $absent = Join-Path $env:TEMP ("config-absent-{0}.json" -f [guid]::NewGuid())
        $result = Initialize-InstallConfig $absent
        $result.Created | Should Be $true
        $result.Config.riotClientPath | Should Be 'C:\Riot\RiotClientServices.exe'
        Assert-MockCalled -Scope It New-LaunchConfig -Exactly -Times 1
        Assert-MockCalled -Scope It Write-LaunchConfig -Exactly -Times 1 -ParameterFilter { $Path -eq $absent }
    }

    It 'conserve un config.json existant sans le réécrire' {
        Mock Read-LaunchConfig { New-TestLaunchConfig }
        $result = Initialize-InstallConfig (New-TempConfig)
        $result.Created | Should Be $false
        Assert-MockCalled -Scope It Write-LaunchConfig -Exactly -Times 0
    }
}

# ---------------------------------------------------------------- Bilans

Describe 'Get-CompanionOutcomeLines' {
    It 'confirme que tout est à jour sans échec' {
        (Get-CompanionOutcomeLines @{ UninstallFailed = @(); InstallFailed = @() }) -join '|' | Should Be 'Applis compagnon à jour.'
    }

    It 'signale en erreur une désinstallation non aboutie' {
        $lines = @(Get-CompanionOutcomeLines @{ UninstallFailed = @('Porofessor'); InstallFailed = @() })
        $lines.Count | Should Be 1
        $lines[0] | Should Match '^Erreur : Porofessor'
        $lines[0] | Should Match 'config.json inchangé'
    }

    It 'avertit pour chaque installation non aboutie' {
        $lines = @(Get-CompanionOutcomeLines @{ UninstallFailed = @(); InstallFailed = @('Blitz', 'OP.GG') })
        $lines.Count | Should Be 2
        $lines[0] | Should Match '^Avertissement : Blitz'
        $lines[1] | Should Match '^Avertissement : OP.GG'
    }
}

Describe 'Resolve-ShortcutCompanions' {
    $config = New-TestLaunchConfig @((New-TestCompanionEntry 'blitz' 'Blitz'), (New-TestCompanionEntry 'opgg' 'OP.GG'))

    It 'retrouve les applis de config.json par identifiant, dans l''ordre demandé' {
        (Resolve-ShortcutCompanions $config @('opgg', 'blitz') | ForEach-Object { $_.name }) -join ',' | Should Be 'OP.GG,Blitz'
    }

    It 'ignore un identifiant absent de config.json' {
        @(Resolve-ShortcutCompanions $config @('inconnu', 'blitz')).Count | Should Be 1
    }

    It 'rend une liste vide sans identifiant' {
        (Resolve-ShortcutCompanions $config @()).Count | Should Be 0
    }
}

Describe 'Get-ShortcutCountText' {
    It 'indique qu''aucun raccourci n''a été créé' {
        Get-ShortcutCountText @() | Should Be 'Raccourcis : aucun créé'
    }

    It 'accorde au singulier pour un seul raccourci' {
        Get-ShortcutCountText @('C:\Bureau\League of Legends JP.lnk') | Should Be 'Raccourcis : 1 créé dans C:\Bureau'
    }

    It 'compte les raccourcis et cite chaque dossier une seule fois' {
        $paths = @('C:\Bureau\a.lnk', 'C:\Bureau\b.lnk', 'C:\lol\c.lnk')
        Get-ShortcutCountText $paths | Should Be 'Raccourcis : 3 créés dans C:\Bureau, C:\lol'
    }
}

Describe 'Get-CompletionSummaryLines' {
    It 'résume config.json, les applis retenues et les raccourcis' {
        $config = New-TestLaunchConfig @(New-TestCompanionEntry 'blitz' 'Blitz')
        $lines  = @(Get-CompletionSummaryLines $config 'C:\lol\config.json' @('C:\Bureau\League of Legends JP - Blitz.lnk'))
        $lines[0] | Should Be 'Configuration : C:\lol\config.json'
        $lines[1] | Should Be 'Applis compagnon retenues : Blitz'
        $lines[2] | Should Be 'Raccourcis : 1 créé dans C:\Bureau'
    }

    It 'indique « aucune » appli et aucun raccourci sur une installation minimale' {
        $lines = @(Get-CompletionSummaryLines (New-TestLaunchConfig) 'C:\lol\config.json' @())
        $lines[1] | Should Be 'Applis compagnon retenues : aucune'
        $lines[2] | Should Be 'Raccourcis : aucun créé'
    }
}

# ---------------------------------------------------------------- Journal et sûreté

Describe 'Write-InstallLog' {
    Mock Invoke-SplashTick {}

    It 'n''échoue pas quand la page n''a pas de journal' {
        Reset-InstallTestState
        { Write-InstallLog 'x' } | Should Not Throw
    }

    It 'ajoute les lignes à la suite, séparées par un retour à la ligne' {
        Reset-InstallTestState @{ Controls = @{ Log = (New-ThemedLog 0 0 100 100) } }
        Write-InstallLog 'Téléchargement de Blitz…'
        Write-InstallLog 'Créé : x.lnk'
        $script:InstallState.Controls.Log.Text | Should Be "Téléchargement de Blitz…`r`nCréé : x.lnk"
    }
}

Describe 'Invoke-InstallLogged' {
    Mock Write-InstallLog {}

    It 'rend la valeur produite par l''action' {
        Invoke-InstallLogged { 'valeur' } | Should Be 'valeur'
    }

    It 'détourne les avertissements du moteur vers le journal sans les mêler au résultat' {
        $result = Invoke-InstallLogged { Write-Warning 'winget indisponible'; @{ InstallFailed = @('Blitz') } }
        $result.InstallFailed -join ',' | Should Be 'Blitz'
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 1 -ParameterFilter { $Text -eq 'Avertissement : winget indisponible' }
    }

    It 'rend null quand l''action ne produit rien' {
        Invoke-InstallLogged { Write-Warning 'seul' } | Should BeNullOrEmpty
    }

    It 'laisse remonter une exception de l''action' {
        { Invoke-InstallLogged { throw 'boom' } } | Should Throw
    }
}

Describe 'Invoke-InstallSafely' {
    Mock Stop-InstallOnError {}

    It 'exécute l''action' {
        $script:safelyProbe = 0
        Invoke-InstallSafely { $script:safelyProbe = 1 }
        $script:safelyProbe | Should Be 1
        Assert-MockCalled -Scope It Stop-InstallOnError -Exactly -Times 0
    }

    It 'transforme une exception en arrêt de l''installation au lieu de la laisser avaler' {
        { Invoke-InstallSafely { throw 'boom' } } | Should Not Throw
        Assert-MockCalled -Scope It Stop-InstallOnError -Exactly -Times 1 -ParameterFilter { $Message -eq 'boom' }
    }
}

Describe 'Stop-InstallOnError' {
    Mock Show-InstallErrorBox {}

    It 'passe en code 1, lève le gel et ferme la fenêtre' {
        $form = New-FakeForm
        Reset-InstallTestState @{ Form = $form; IsBusy = $true }
        Stop-InstallOnError 'boom'
        $script:InstallState.ExitCode | Should Be 1
        $script:InstallState.IsBusy | Should Be $false
        $form.IsClosed | Should Be $true
        Assert-MockCalled -Scope It Show-InstallErrorBox -Exactly -Times 1 -ParameterFilter { $Text -match 'boom' }
    }

    It 'affiche l''erreur même sans fenêtre ouverte' {
        Reset-InstallTestState
        { Stop-InstallOnError 'boom' } | Should Not Throw
        $script:InstallState.ExitCode | Should Be 1
    }
}

Describe 'Register-InstallCompanionUi' {
    Mock Write-InstallLog {}

    It 'branche les étapes du moteur sur le journal et désactive le splash séparé' {
        Register-InstallCompanionUi
        $script:CompanionUi.UseSplash | Should Be $false
        & $script:CompanionUi.OnStep 'Téléchargement de Blitz…'
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 1 -ParameterFilter { $Text -eq 'Téléchargement de Blitz…' }
    }
}

# ---------------------------------------------------------------- Page applis compagnon

Describe 'Invoke-InstallAppsStep' {
    $blitz = New-TestCompanionApp -Id 'blitz'
    $opgg  = New-TestCompanionApp -Id 'opgg'
    Mock Write-CompanionConfig { $true }
    Mock Get-InstalledCompanionApps { @() }
    Mock Invoke-InstallCompanionActions { @{ UninstallFailed = @(); InstallFailed = @() } }

    It 'écrit config.json et avance sans rien exécuter quand rien n''est en attente' {
        Reset-InstallTestState @{ Catalog = @($blitz, $opgg); Installed = @(New-TestInstalledApp $blitz); Config = (New-TestLaunchConfig) }
        Mock Get-InstallCompanionChoice { @{ SelectedIds = @('blitz'); UninstallOthers = $false } }
        Invoke-InstallAppsStep | Should Be $true
        Assert-MockCalled -Scope It Invoke-InstallCompanionActions -Exactly -Times 0
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 1 -ParameterFilter { ($SelectedApps | ForEach-Object { $_.id }) -join ',' -eq 'blitz' }
    }

    It 'exécute les actions en attente puis écrit config.json' {
        Reset-InstallTestState @{ Catalog = @($blitz, $opgg); Installed = @(); Config = (New-TestLaunchConfig) }
        Mock Get-InstallCompanionChoice { @{ SelectedIds = @('opgg'); UninstallOthers = $false } }
        Invoke-InstallAppsStep | Should Be $true
        Assert-MockCalled -Scope It Invoke-InstallCompanionActions -Exactly -Times 1 -ParameterFilter { ($Actions.Install | ForEach-Object { $_.id }) -join ',' -eq 'opgg' }
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 1
        Assert-MockCalled -Scope It Get-InstalledCompanionApps -Exactly -Times 1
    }

    It 'reste sur la page et laisse config.json intact quand une désinstallation a échoué' {
        Reset-InstallTestState @{ Catalog = @($blitz, $opgg); Installed = @(New-TestInstalledApp $opgg); Config = (New-TestLaunchConfig) }
        Mock Get-InstallCompanionChoice { @{ SelectedIds = @('blitz'); UninstallOthers = $true } }
        Mock Invoke-InstallCompanionActions { @{ UninstallFailed = @('opgg'); InstallFailed = @() } }
        Invoke-InstallAppsStep | Should Be $false
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 0
    }

    It 'avance malgré une installation non aboutie (le lanceur ignorera l''appli absente)' {
        Reset-InstallTestState @{ Catalog = @($blitz, $opgg); Installed = @(); Config = (New-TestLaunchConfig) }
        Mock Get-InstallCompanionChoice { @{ SelectedIds = @('blitz'); UninstallOthers = $false } }
        Mock Invoke-InstallCompanionActions { @{ UninstallFailed = @(); InstallFailed = @('blitz') } }
        Invoke-InstallAppsStep | Should Be $true
        Assert-MockCalled -Scope It Write-CompanionConfig -Exactly -Times 1
    }
}

Describe 'Invoke-InstallCompanionActions' {
    Mock Set-InstallBusy {}
    Mock Write-InstallLog {}

    It 'gèle la fenêtre pendant les actions, la libère ensuite et journalise le bilan' {
        Mock Invoke-CompanionActions { @{ UninstallFailed = @(); InstallFailed = @('Blitz') } }
        $result = Invoke-InstallCompanionActions ([pscustomobject]@{ Install = @(); Uninstall = @() })
        $result.InstallFailed -join ',' | Should Be 'Blitz'
        Assert-MockCalled -Scope It Set-InstallBusy -Exactly -Times 1 -ParameterFilter { $Busy -eq $true }
        Assert-MockCalled -Scope It Set-InstallBusy -Exactly -Times 1 -ParameterFilter { $Busy -eq $false }
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 1 -ParameterFilter { $Text -match '^Avertissement : Blitz' }
    }

    It 'libère la fenêtre même si le moteur lève une erreur' {
        Mock Invoke-CompanionActions { throw 'boom' }
        { Invoke-InstallCompanionActions ([pscustomobject]@{ Install = @(); Uninstall = @() }) } | Should Throw
        Assert-MockCalled -Scope It Set-InstallBusy -Exactly -Times 1 -ParameterFilter { $Busy -eq $false }
    }
}

# ---------------------------------------------------------------- Page raccourcis

Describe 'Invoke-InstallShortcutsStep' {
    $config = New-TestLaunchConfig @(New-TestCompanionEntry 'blitz' 'Blitz')
    Mock Write-InstallLog {}
    Mock New-InstallShortcuts { @('C:\Bureau\League of Legends JP - Blitz.lnk') }
    Mock Remove-ObsoleteShortcuts { 'Retiré : C:\Bureau\League of Legends FR.lnk' }

    It 'reste sur la page sans rien créer quand aucune langue n''est cochée' {
        Reset-InstallTestState @{ Config = $config }
        Mock Get-InstallShortcutSelection { @{ Codes = @(); CompanionIds = @('blitz') } }
        Invoke-InstallShortcutsStep | Should Be $false
        Assert-MockCalled -Scope It New-InstallShortcuts -Exactly -Times 0
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 1 -ParameterFilter { $Text -match 'Aucune langue cochée' }
    }

    It 'crée une combinaison par langue × compagnon puis retire les raccourcis obsolètes' {
        Reset-InstallTestState @{ Config = $config }
        Mock Get-InstallShortcutSelection { @{ Codes = @('ja_JP'); CompanionIds = @('blitz') } }
        Invoke-InstallShortcutsStep | Should Be $true
        $script:InstallState.ShortcutPaths.Count | Should Be 1
        Assert-MockCalled -Scope It New-InstallShortcuts -Exactly -Times 1 -ParameterFilter { $Combinations.Count -eq 1 -and $Combinations[0].Name -eq 'League of Legends JP - Blitz' }
        Assert-MockCalled -Scope It Remove-ObsoleteShortcuts -Exactly -Times 1
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 1 -ParameterFilter { $Text -match '^Retiré' }
    }

    It 'crée un raccourci sans compagnon par langue quand aucune appli n''est cochée' {
        Reset-InstallTestState @{ Config = $config }
        Mock Get-InstallShortcutSelection { @{ Codes = @('ja_JP', 'fr_FR'); CompanionIds = @() } }
        Invoke-InstallShortcutsStep | Should Be $true
        Assert-MockCalled -Scope It New-InstallShortcuts -Exactly -Times 1 -ParameterFilter { $Combinations.Count -eq 2 -and $Combinations[1].Name -eq 'League of Legends FR' }
    }
}

Describe 'New-InstallShortcuts' {
    Mock Write-InstallLog {}

    It 'journalise chaque raccourci créé et rend leurs chemins' {
        Mock New-LaunchShortcutWithFallback { param($Combination) "C:\Bureau\$($Combination.Name).lnk" }
        $combinations = Get-ShortcutCombinations @('ja_JP', 'fr_FR') @()
        $paths = @(New-InstallShortcuts $combinations)
        $paths -join '|' | Should Be 'C:\Bureau\League of Legends JP.lnk|C:\Bureau\League of Legends FR.lnk'
        Assert-MockCalled -Scope It Write-InstallLog -Exactly -Times 2 -ParameterFilter { $Text -match '^Créé : ' }
    }

    It 'rend une liste vide sans combinaison' {
        @(New-InstallShortcuts @()).Count | Should Be 0
    }
}

# ---------------------------------------------------------------- Navigation

Describe 'Invoke-InstallStepAction' {
    Mock Invoke-InstallAppsStep { $false }
    Mock Invoke-InstallShortcutsStep { $true }

    It 'laisse passer la détection sans action' {
        Invoke-InstallStepAction 'detect' | Should Be $true
        Assert-MockCalled -Scope It Invoke-InstallAppsStep -Exactly -Times 0
        Assert-MockCalled -Scope It Invoke-InstallShortcutsStep -Exactly -Times 0
    }

    It 'délègue à la page des applis compagnon et respecte son verdict' {
        Invoke-InstallStepAction 'apps' | Should Be $false
        Assert-MockCalled -Scope It Invoke-InstallAppsStep -Exactly -Times 1
    }

    It 'délègue à la page des raccourcis' {
        Invoke-InstallStepAction 'shortcuts' | Should Be $true
        Assert-MockCalled -Scope It Invoke-InstallShortcutsStep -Exactly -Times 1
    }
}

Describe 'Invoke-InstallNext' {
    Mock Show-InstallPage {}

    It 'avance à la page suivante quand l''action de la page réussit' {
        Reset-InstallTestState @{ StepId = 'apps' }
        Mock Invoke-InstallStepAction { $true }
        Invoke-InstallNext
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 1 -ParameterFilter { $StepId -eq 'shortcuts' }
    }

    It 'reste sur la page quand son action échoue' {
        Reset-InstallTestState @{ StepId = 'apps' }
        Mock Invoke-InstallStepAction { $false }
        Invoke-InstallNext
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 0
    }

    It 'ferme la fenêtre depuis la page terminé' {
        $form = New-FakeForm
        Reset-InstallTestState @{ StepId = 'done'; Form = $form; ExitCode = 0 }
        Mock Invoke-InstallStepAction { $true }
        Invoke-InstallNext
        $form.IsClosed | Should Be $true
        $script:InstallState.ExitCode | Should Be 0
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 0
    }
}

Describe 'Invoke-InstallBack' {
    Mock Show-InstallPage {}

    It 'revient à la page précédente' {
        Reset-InstallTestState @{ StepId = 'shortcuts' }
        Invoke-InstallBack
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 1 -ParameterFilter { $StepId -eq 'apps' }
    }

    It 'ne fait rien sur la première page' {
        Reset-InstallTestState @{ StepId = 'detect' }
        Invoke-InstallBack
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 0
    }

    It 'ne fait rien une fois terminé' {
        Reset-InstallTestState @{ StepId = 'done' }
        Invoke-InstallBack
        Assert-MockCalled -Scope It Show-InstallPage -Exactly -Times 0
    }
}

Describe 'Invoke-InstallCancel' {
    It 'ferme la fenêtre avec le code 2' {
        $form = New-FakeForm
        Reset-InstallTestState @{ Form = $form; ExitCode = 0 }
        Invoke-InstallCancel
        $script:InstallState.ExitCode | Should Be 2
        $form.IsClosed | Should Be $true
    }
}

Describe 'Start-InstallWizard' {
    Mock Show-InstallErrorBox {}
    Mock New-InstallWindow { throw 'aucune fenêtre ne doit être créée' }

    It 'refuse de tourner élevé sans ouvrir de fenêtre' {
        Mock Test-CompanionElevated { $true }
        Start-InstallWizard | Should Be 1
        Assert-MockCalled -Scope It Show-InstallErrorBox -Exactly -Times 1 -ParameterFilter { $Text -match 'administrateur' }
        Assert-MockCalled -Scope It New-InstallWindow -Exactly -Times 0
    }
}
