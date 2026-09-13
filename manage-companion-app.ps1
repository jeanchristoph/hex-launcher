<#
.SYNOPSIS
    Choisit les applications compagnon (Porofessor, Blitz, OP.GG, Mobalytics…), installe celles qui manquent,
    désinstalle sur demande celles qui ne sont plus voulues, et écrit la liste companionApps de config.json.

.DESCRIPTION
    Appelé par install.bat entre la détection (detect-config.ps1) et la création des raccourcis.

    - Lit companion-apps.json (catalogue) et config.json
    - Boîte de dialogue à cases à cocher (ou -Apps en mode script), pré-cochée depuis config.json, sinon depuis
      les applis détectées sur la machine
    - Installe les applis cochées absentes ; désinstalle les applis décochées présentes UNIQUEMENT si la case
      « désinstaller » est cochée (ou -UninstallOthers) — jamais d'office
    - Confirmation listant exactement les actions, sauf -Force
    - Écrit companionApps dans config.json seulement si la liste change ; un refus ou un échec de
      désinstallation annule l'étape sans rien installer ni écrire

    Sécurité : refuse de tourner élevé (administrateur) ; tout binaire exécuté — installeur téléchargé ou
    désinstalleur lu dans le registre — doit porter une signature Authenticode valide de l'éditeur attendu
    par le catalogue. Le registre Windows n'est jamais écrit par ce script (lecture des clés Uninstall).

    Codes de sortie : 0 ok · 1 erreur · 2 annulé ou refusé par l'utilisateur

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File manage-companion-app.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File manage-companion-app.ps1 -Apps blitz,opgg
    powershell -NoProfile -ExecutionPolicy Bypass -File manage-companion-app.ps1 -Apps blitz -UninstallOthers -Force
    powershell -NoProfile -ExecutionPolicy Bypass -File manage-companion-app.ps1 -Apps none -DryRun
#>
param(
    # Identifiants du catalogue à garder/installer (ex. blitz,opgg), ou "none". Absent → boîte de dialogue.
    [string[]]$Apps,

    # Désinstalle les applis du catalogue présentes sur la machine mais non listées dans -Apps
    [switch]$UninstallOthers,

    # Par défaut : config.json et companion-apps.json à côté de ce script
    [string]$ConfigPath,
    [string]$CatalogPath,

    # Ne demande pas de confirmation avant d'installer/désinstaller (déploiement scripté)
    [switch]$Force,

    # Affiche ce qui serait fait sans installer, désinstaller ni écrire config.json
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'lib\companion-app.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\splash.lib.ps1')

$NoCompanionId              = 'none'
$SilentUninstallTimeout     = 120
$InteractiveDialogAppear    = 15
$InteractiveDialogTimeout   = 600
$DownloadTimeoutSeconds     = 900
$WingetFailureProbeSeconds  = 10
$WingetArguments            = '--exact --silent --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity'

# Splash affiché pendant les actions (null en dehors) ; SplashTick = une seconde d'attente qui entretient sa barre
$script:CompanionSplash = $null
$SplashTick = { Wait-WithAnimation 1 }

# Étape en cours : console + ligne de statut du splash
function Write-CompanionStep([string]$Text) {
    Write-Host "  $Text"
    Update-SplashStatus $script:CompanionSplash $Text
}

# ---------------------------------------------------------------- Garde

# Un script élevé exécuterait des désinstalleurs lus dans HKCU (modifiable par tout process de l'utilisateur)
# avec les droits administrateur : on refuse. Les installeurs per-user n'en ont pas besoin.
function Test-CompanionElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- Dialogue de choix

function New-CompanionButton([string]$Text, [int]$Left, [int]$Top, [string]$DialogResult) {
    $button              = New-Object System.Windows.Forms.Button
    $button.Text         = $Text
    $button.Location     = New-Object System.Drawing.Point($Left, $Top)
    $button.Size         = New-Object System.Drawing.Size(90, 30)
    $button.DialogResult = $DialogResult
    return $button
}

function Get-CompanionChoiceLabel($App, [object[]]$Installed) {
    if ($Installed | Where-Object { $_.App.id -eq $App.id }) { return "$($App.name)   (installée)" }
    return $App.name
}

function New-CompanionCheckedList([object[]]$Catalog, [object[]]$Installed, [string[]]$PreselectedIds, [int]$Top) {
    $list              = New-Object System.Windows.Forms.CheckedListBox
    $list.Location     = New-Object System.Drawing.Point(12, $Top)
    $list.Size         = New-Object System.Drawing.Size(360, (24 * $Catalog.Count + 8))
    $list.CheckOnClick = $true
    foreach ($entry in $Catalog) {
        $index = $list.Items.Add((Get-CompanionChoiceLabel $entry $Installed))
        $list.SetItemChecked($index, ($PreselectedIds -contains $entry.id))
    }
    return $list
}

# Retourne @{ SelectedIds = [ids cochés]; UninstallOthers = [bool] } ou $null si annulé
function Show-CompanionPicker([object[]]$Catalog, [object[]]$Installed, [string[]]$PreselectedIds) {
    $listTop    = 60
    $checkTop   = $listTop + 24 * $Catalog.Count + 8 + 12
    $buttonsTop = $checkTop + 40

    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = 'League of Legends — applications compagnon'
    $form.Size            = New-Object System.Drawing.Size(400, ($buttonsTop + 80))
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)

    $hint          = New-Object System.Windows.Forms.Label
    $hint.Text     = 'Applis lancées après le jeu (un raccourci par appli cochée). Les applis cochées absentes seront installées.'
    $hint.Location = New-Object System.Drawing.Point(12, 12)
    $hint.Size     = New-Object System.Drawing.Size(360, 44)

    $list = New-CompanionCheckedList $Catalog $Installed $PreselectedIds $listTop

    $uninstall          = New-Object System.Windows.Forms.CheckBox
    $uninstall.Text     = 'Désinstaller les applis décochées présentes sur ce PC'
    $uninstall.Location = New-Object System.Drawing.Point(12, $checkTop)
    $uninstall.Size     = New-Object System.Drawing.Size(360, 26)
    $uninstall.Checked  = $false

    $ok     = New-CompanionButton 'Appliquer' 180 $buttonsTop 'OK'
    $cancel = New-CompanionButton 'Annuler'   282 $buttonsTop 'Cancel'
    $form.Controls.AddRange(@($hint, $list, $uninstall, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    if ($form.ShowDialog() -ne 'OK') { return $null }
    return @{
        SelectedIds     = @($list.CheckedIndices | ForEach-Object { $Catalog[$_].id })
        UninstallOthers = [bool]$uninstall.Checked
    }
}

# Pré-cochage : la liste companionApps de config.json (choix précédent), sinon les applis détectées
function Get-PreselectedCompanionIds([object[]]$Catalog, [object[]]$Installed, $Config) {
    $fromConfig = @($Config.companionApps | Where-Object { Find-CompanionCatalogEntry $Catalog $_.id } | ForEach-Object { $_.id })
    if ($fromConfig.Count -gt 0) { return $fromConfig }
    return @($Installed | ForEach-Object { $_.App.id })
}

# -Apps fourni → validé contre le catalogue ("none" = aucune) ; sinon dialogue
function Resolve-CompanionChoice([object[]]$Catalog, [object[]]$Installed, $Config, $Options) {
    if (-not $Options.HasRequest) { return Show-CompanionPicker $Catalog $Installed (Get-PreselectedCompanionIds $Catalog $Installed $Config) }
    $ids     = @($Options.RequestedIds | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ -and $_ -ne $NoCompanionId })
    $unknown = @($ids | Where-Object { -not (Find-CompanionCatalogEntry $Catalog $_) })
    if ($unknown.Count -gt 0) {
        throw "Application(s) inconnue(s) dans companion-apps.json : $($unknown -join ', ') (attendu : $NoCompanionId, $(($Catalog | ForEach-Object { $_.id }) -join ', '))"
    }
    return @{ SelectedIds = $ids; UninstallOthers = [bool]$Options.UninstallOthers }
}

# ---------------------------------------------------------------- Actions à mener

# BUSINESS_RULE : on installe les applis cochées absentes ; on ne désinstalle une appli décochée que si
# l'utilisateur l'a demandé explicitement (case ou -UninstallOthers) — jamais par exclusivité.
function Get-CompanionActions([object[]]$Catalog, [object[]]$Installed, $Choice) {
    $selected     = @($Catalog | Where-Object { $Choice.SelectedIds -contains $_.id })
    $installedIds = @($Installed | ForEach-Object { $_.App.id })
    return [pscustomobject]@{
        Selected  = $selected
        Install   = @($selected | Where-Object { $installedIds -notcontains $_.id })
        Uninstall = @(if ($Choice.UninstallOthers) { $Installed | Where-Object { $Choice.SelectedIds -notcontains $_.App.id } })
    }
}

function Test-CompanionActionsPending($Actions) {
    return ($Actions.Uninstall.Count -gt 0) -or ($Actions.Install.Count -gt 0)
}

function Format-CompanionActions($Actions) {
    $lines = @(foreach ($item in $Actions.Uninstall) {
        "- Désinstaller $($item.App.name)"
        if ($item.App.uninstall.notice) { "    $($item.App.uninstall.notice)" }
    })
    $lines += @(foreach ($app in $Actions.Install) {
        "- Installer $($app.name) ($($app.install.strategy))"
        if ($app.install.notice) { "    $($app.install.notice)" }
    })
    if ($lines.Count -eq 0) { $lines = @('- Aucune installation ni désinstallation nécessaire') }
    return ($lines -join "`r`n")
}

function Confirm-CompanionActions($Actions) {
    $text   = "Actions prévues :`r`n`r`n$(Format-CompanionActions $Actions)`r`n`r`nContinuer ?"
    $result = [System.Windows.Forms.MessageBox]::Show($text, 'Applications compagnon', 'YesNo', 'Question')
    return ($result -eq 'Yes')
}

# ---------------------------------------------------------------- Process

function Stop-CompanionProcesses([string[]]$Names) {
    $names = @($Names | Where-Object { $_ })
    if ($names.Count -eq 0) { return }
    Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Sans -Wait (qui attendrait tout l'arbre de process : une appli lancée par l'installeur bloquerait indéfiniment).
# On attend le process direct en entretenant le splash, jusqu'à l'échéance ; la sonde d'état reste juge.
# Retourne le code de sortie, ou $null si le process n'a pas rendu la main dans le délai.
function Start-CompanionProcess([string]$Path, [string]$Arguments, [int]$TimeoutSeconds) {
    $options = @{ FilePath = $Path; PassThru = $true }
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $options.ArgumentList = $Arguments }
    $process  = Start-Process @options
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) { Wait-WithAnimation 0.25 }
    if (-not $process.HasExited) { return $null }
    return $process.ExitCode
}

# Un installeur peut afficher sa propre fenêtre (setup Overwolf quand il est absent) : le splash cesse d'être
# au premier plan le temps de l'exécution, pour ne pas la recouvrir
function Start-CompanionInstaller([string]$Path, [string]$Arguments, [int]$TimeoutSeconds) {
    Set-SplashTopMost $script:CompanionSplash $false
    try     { return Start-CompanionProcess $Path $Arguments $TimeoutSeconds }
    finally { Set-SplashTopMost $script:CompanionSplash $true }
}

# ---------------------------------------------------------------- Désinstallation

function Test-CompanionDialogOpen($App) {
    $names = @($App.uninstall.dialogProcessNames | Where-Object { $_ })
    if ($names.Count -eq 0) { return $false }
    return [bool](Get-Process -Name $names -ErrorAction SilentlyContinue)
}

function Wait-CompanionDialogState($App, [bool]$Open, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-CompanionDialogOpen $App) -eq $Open) { return $true }
        if (-not (Test-CompanionInstalled $App)) { return $true }
        Wait-WithAnimation 1
    }
    return ((Test-CompanionDialogOpen $App) -eq $Open)
}

# Mode interactif : l'éditeur affiche son propre dialogue (menu Overwolf) et rend la main avant que
# l'utilisateur ait choisi. Trois phases : apparition du dialogue, fermeture, puis fin asynchrone.
function Wait-CompanionInteractiveUninstall($App) {
    Wait-CompanionDialogState $App -Open $true  -TimeoutSeconds $InteractiveDialogAppear  | Out-Null
    Wait-CompanionDialogState $App -Open $false -TimeoutSeconds $InteractiveDialogTimeout | Out-Null
    return Wait-CompanionState $App -Installed $false -TimeoutSeconds $SilentUninstallTimeout -OnTick $SplashTick
}

function Wait-CompanionUninstalled($App) {
    if ($App.uninstall.mode -eq 'interactive') { return Wait-CompanionInteractiveUninstall $App }
    return Wait-CompanionState $App -Installed $false -TimeoutSeconds $SilentUninstallTimeout -OnTick $SplashTick
}

# Désinstalleur lu dans le registre : chemin absolu, .exe, signé par l'éditeur attendu — sinon on n'y touche pas
function Resolve-TrustedCompanionUninstaller($Installed) {
    $commandLine = Resolve-CompanionUninstallCommand $Installed.App $Installed.Registry
    if (-not $commandLine) { return $null }
    $command = Split-CompanionCommandLine $commandLine
    if (-not (Test-CompanionBinaryTrusted $command.Path $Installed.App.signer)) { return $null }
    return $command
}

function Uninstall-CompanionApp($Installed) {
    $app     = $Installed.App
    $command = Resolve-TrustedCompanionUninstaller $Installed
    if (-not $command) {
        Write-Warning "$($app.name) : désinstalleur absent du registre ou non signé par $($app.signer.organization) — à désinstaller depuis Windows"
        return $false
    }
    Write-CompanionStep "Désinstallation de $($app.name)…"
    Stop-CompanionProcesses $app.processNames
    # Mode interactif : le dialogue de l'éditeur doit rester visible, le splash (TopMost) se retire
    $isInteractive = $app.uninstall.mode -eq 'interactive'
    if ($isInteractive) { Set-SplashVisible $script:CompanionSplash $false }
    Start-CompanionProcess $command.Path $command.Arguments $SilentUninstallTimeout | Out-Null
    $removed = Wait-CompanionUninstalled $app
    if ($isInteractive) { Set-SplashVisible $script:CompanionSplash $true }
    if (-not $removed) { Write-Warning "$($app.name) est toujours présente (désinstallation refusée, annulée ou trop longue)" }
    return $removed
}

# ---------------------------------------------------------------- Installation

function Get-CompanionWingetPath {
    $command = Get-Command winget -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Install-CompanionViaWinget($App) {
    $winget = Get-CompanionWingetPath
    if (-not $winget) { Write-Warning 'winget indisponible sur cette machine (App Installer absent)'; return $false }
    Write-CompanionStep "Installation de $($App.name) (winget)…"
    $exitCode = Start-CompanionInstaller $winget "install --id $($App.install.wingetId) $WingetArguments" $App.install.timeoutSeconds
    if ($exitCode -ne 0) {
        Write-Warning "winget a échoué (code $exitCode)"
        return Wait-CompanionState $App -Installed $true -TimeoutSeconds $WingetFailureProbeSeconds -OnTick $SplashTick
    }
    return Wait-CompanionState $App -Installed $true -TimeoutSeconds $App.install.timeoutSeconds -OnTick $SplashTick
}

function New-CompanionDownloadJob([string]$Url, [string]$OutFile) {
    return Start-Job -ScriptBlock {
        param($Url, $OutFile)
        $ProgressPreference = 'SilentlyContinue'   # la barre de progression ralentit Invoke-WebRequest en PS 5.1
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
    } -ArgumentList $Url, $OutFile
}

# Téléchargement dans un job pour que la barre du splash continue d'animer (Invoke-WebRequest est bloquant)
function Invoke-CompanionDownload([string]$Url, [string]$OutFile) {
    $job      = New-CompanionDownloadJob $Url $OutFile
    $deadline = (Get-Date).AddSeconds($DownloadTimeoutSeconds)
    try {
        while ($job.State -eq 'Running' -and (Get-Date) -lt $deadline) { Wait-WithAnimation 0.1 }
        if ($job.State -eq 'Running') { Stop-Job -Job $job; throw "téléchargement trop long (> $DownloadTimeoutSeconds s) : $Url" }
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
    }
    finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
}

# Dossier temporaire aléatoire, nom sans "install"/"setup" (évite l'heuristique UAC de Windows sur le nom)
function New-CompanionDownloadPath([string]$Id) {
    $directory = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    return Join-Path $directory "companion-$Id-$([guid]::NewGuid().ToString('N')).exe"
}

function Install-CompanionViaDownload($App) {
    $binary = New-CompanionDownloadPath $App.id
    try {
        Write-CompanionStep "Téléchargement de $($App.name)…"
        Invoke-CompanionDownload $App.install.url $binary
        if (-not (Test-CompanionBinaryTrusted $binary $App.signer)) {
            Write-Warning "Installeur $($App.name) : signature absente, invalide ou d'un autre éditeur que $($App.signer.organization) — installation refusée"
            return $false
        }
        Write-CompanionStep "Installation de $($App.name)…"
        Start-CompanionInstaller $binary $App.install.arguments $App.install.timeoutSeconds | Out-Null
        return Wait-CompanionState $App -Installed $true -TimeoutSeconds $App.install.timeoutSeconds -OnTick $SplashTick
    }
    finally { Remove-Item (Split-Path $binary -Parent) -Recurse -Force -ErrorAction SilentlyContinue }
}

# Pas installée à cet instant : l'utilisateur termine dans le navigateur, le lanceur ignore l'appli tant qu'elle est absente
function Install-CompanionViaBrowser($App) {
    Start-Process $App.install.browserUrl
    Write-CompanionStep "Page de téléchargement de $($App.name) ouverte dans le navigateur — installez-la, le lanceur la prendra en compte ensuite"
    return $false
}

function Invoke-CompanionInstallStrategy($App, [string]$Strategy) {
    switch ($Strategy) {
        'winget'   { return Install-CompanionViaWinget $App }
        'download' { return Install-CompanionViaDownload $App }
        'browser'  { return Install-CompanionViaBrowser $App }
    }
    return $false
}

function Invoke-CompanionInstallStrategySafely($App, [string]$Strategy) {
    try   { return Invoke-CompanionInstallStrategy $App $Strategy }
    catch { Write-Warning "Installation de $($App.name) ($Strategy) : $($_.Exception.Message)"; return $false }
}

# Certains installeurs lancent l'appli en fin d'installation (Mobalytics) : elle doit démarrer avec le jeu, pas maintenant
function Install-CompanionApp($App) {
    $installed = Invoke-CompanionInstallStrategySafely $App $App.install.strategy
    if ($installed) { Stop-CompanionProcesses $App.processNames; return $true }
    if ($App.install.strategy -eq 'browser' -or -not $App.install.fallback) { return $false }
    Write-Warning "Installation automatique de $($App.name) impossible — repli : $($App.install.fallback)"
    return Invoke-CompanionInstallStrategySafely $App $App.install.fallback
}

# ---------------------------------------------------------------- config.json

# Remplace companionApps par les applis choisies ; ne réécrit le fichier que si la liste change
function Write-CompanionConfig($Config, [string]$Path, [object[]]$SelectedApps) {
    $wanted = @($SelectedApps | ForEach-Object { ConvertTo-LaunchCompanionEntry $_ })
    if (Test-LaunchCompanionAppsEqual $Config.companionApps $wanted) { return $false }
    $Config | Add-Member -NotePropertyName companionApps -NotePropertyValue $wanted -Force
    Write-LaunchConfig $Config $Path
    return $true
}

# ---------------------------------------------------------------- Orchestration

# Retourne @{ UninstallFailed = [noms]; InstallFailed = [noms] } ; aucune installation si une désinstallation a échoué
function Invoke-CompanionActions($Actions) {
    $script:CompanionSplash = New-SplashWindow -Subtitle 'Applications compagnon'
    $result = @{ UninstallFailed = @(); InstallFailed = @() }
    try {
        foreach ($item in $Actions.Uninstall) {
            if (-not (Uninstall-CompanionApp $item)) { $result.UninstallFailed += $item.App.name }
        }
        if ($result.UninstallFailed.Count -gt 0) { return $result }
        foreach ($app in $Actions.Install) {
            if (-not (Install-CompanionApp $app)) { $result.InstallFailed += $app.name }
        }
        return $result
    }
    finally {
        Close-SplashWindow $script:CompanionSplash
        $script:CompanionSplash = $null
    }
}

function Write-CompanionOutcome($Actions, $Result, [bool]$ConfigChanged) {
    $names = @($Actions.Selected | ForEach-Object { $_.name })
    $summary = if ($names.Count -gt 0) { $names -join ', ' } else { 'aucune' }
    Write-Host "config.json $(if ($ConfigChanged) { 'mis à jour' } else { 'inchangé' }) : applications compagnon = $summary"
    foreach ($name in $Result.InstallFailed) {
        Write-Warning "$name n'est pas installée pour l'instant — le lanceur l'ignorera tant qu'elle est absente"
    }
}

# Retourne le code de sortie du script
function Invoke-CompanionManagement($Options) {
    if (Test-CompanionElevated) { throw "Ne pas exécuter en tant qu'administrateur : les installeurs sont per-user et les désinstalleurs sont lus dans le registre utilisateur" }
    if (-not (Test-Path $Options.ConfigPath)) { throw "config.json introuvable : $($Options.ConfigPath) — lancer detect-config.ps1 d'abord" }
    $catalog   = Read-CompanionCatalog $Options.CatalogPath
    $config    = Read-LaunchConfig $Options.ConfigPath
    $installed = @(Get-InstalledCompanionApps $catalog)
    $choice    = Resolve-CompanionChoice $catalog $installed $config $Options
    if ($null -eq $choice) { Write-Host 'Annulé : applications compagnon inchangées.'; return 2 }

    $actions = Get-CompanionActions $catalog $installed $choice
    Write-Host "Applications compagnon choisies : $(if ($actions.Selected.Count -gt 0) { ($actions.Selected | ForEach-Object { $_.name }) -join ', ' } else { 'aucune' })"
    Write-Host (Format-CompanionActions $actions)
    if ($Options.DryRun) { Write-Host '[DryRun] Rien n''a été exécuté, config.json inchangé.'; return 0 }
    if ((Test-CompanionActionsPending $actions) -and -not $Options.Force -and -not (Confirm-CompanionActions $actions)) {
        Write-Host 'Annulé : applications compagnon inchangées.'; return 2
    }

    $result = if (Test-CompanionActionsPending $actions) { Invoke-CompanionActions $actions } else { @{ UninstallFailed = @(); InstallFailed = @() } }
    if ($result.UninstallFailed.Count -gt 0) {
        Write-Warning "Désinstallation non aboutie ($($result.UninstallFailed -join ', ')) : rien n'a été installé, config.json inchangé."
        return 2
    }
    $changed = Write-CompanionConfig $config $Options.ConfigPath $actions.Selected
    Write-CompanionOutcome $actions $result $changed
    return 0
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    $options = @{
        RequestedIds    = $Apps
        HasRequest      = $PSBoundParameters.ContainsKey('Apps')
        UninstallOthers = [bool]$UninstallOthers
        Force           = [bool]$Force
        DryRun          = [bool]$DryRun
        ConfigPath      = if ($ConfigPath)  { $ConfigPath }  else { Join-Path $PSScriptRoot 'config.json' }
        CatalogPath     = if ($CatalogPath) { $CatalogPath } else { Join-Path $PSScriptRoot 'companion-apps.json' }
    }
    try   { [int]$exitCode = Invoke-CompanionManagement $options; exit $exitCode }
    catch { Write-Error $_; exit 1 }
}
