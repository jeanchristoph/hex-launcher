<#
.SYNOPSIS
    Assistant d'installation de hex-launcher : une seule fenêtre au thème League of Legends,
    quatre étapes — détection, applis compagnon, raccourcis, terminé.

.DESCRIPTION
    Lancé par install.bat (sans console). Les scripts existants restent le moteur : ils sont dot-sourcés
    (leur bloc Main est ignoré) et l'assistant n'orchestre que leurs fonctions :
        detect-config.ps1        → config.json (généré s'il manque, jamais écrasé)
        manage-companion-app.ps1 → choix, installation et désinstallation des applis compagnon
        create-shortcuts.ps1     → un raccourci par langue × appli compagnon dans la destination

    La navigation repose sur une machine à états pure (Get-NextInstallStep, Test-CanGoBack…) testée sans fenêtre ;
    les étapes du moteur et ses avertissements sont détournés vers le journal de la fenêtre (aucun splash séparé).

    Codes de sortie : 0 terminé · 1 erreur · 2 annulé
    Sécurité : refuse de tourner élevé (administrateur), comme manage-companion-app.ps1.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Destination "D:\Jeux"
#>
param(
    # Dossier où créer les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop')
)

. (Join-Path $PSScriptRoot 'lib\theme.lib.ps1')
. (Join-Path $PSScriptRoot 'detect-config.ps1')
. (Join-Path $PSScriptRoot 'manage-companion-app.ps1')
. (Join-Path $PSScriptRoot 'create-shortcuts.ps1') -Destination $Destination

$InstallConfigPath  = Join-Path $PSScriptRoot 'config.json'
$InstallCatalogPath = Join-Path $PSScriptRoot 'companion-apps.json'
$InstallWindowTitle = 'hex-launcher — installation'

# État partagé par les pages et les gestionnaires d'événements (les variables locales d'une page ne survivent pas au clic)
$script:InstallState = @{
    StepId           = 'detect'
    ExitCode         = 2
    IsBusy           = $false
    Config           = $null
    ConfigCreated    = $false
    DetectionItems   = @()
    Catalog          = @()
    Installed        = @()
    Locales          = @()
    ExistingShortcuts = @()
    ShortcutPaths    = @()
    Form             = $null
    Layout           = $null
    Controls         = @{}
}

# ---------------------------------------------------------------- Machine à états (pure, sans WinForms)

$InstallSteps      = @('detect', 'apps', 'shortcuts', 'done')
$InstallStepTitles = @{ detect = '1. Bienvenue'; apps = '2. Applis compagnon'; shortcuts = '3. Raccourcis'; done = '4. Terminé' }
$InstallPageTitles = @{ detect = 'Bienvenue'; apps = 'Applis compagnon'; shortcuts = 'Raccourcis'; done = 'Terminé' }

function Get-InstallStepIndex([string]$Id) {
    return [array]::IndexOf($InstallSteps, $Id)
}

function Get-NextInstallStep([string]$Id) {
    $index = Get-InstallStepIndex $Id
    if ($index -lt 0 -or $index -ge $InstallSteps.Count - 1) { return $null }
    return $InstallSteps[$index + 1]
}

function Get-PreviousInstallStep([string]$Id) {
    $index = Get-InstallStepIndex $Id
    if ($index -le 0) { return $null }
    return $InstallSteps[$index - 1]
}

# BUSINESS_RULE : une fois terminé, tout est appliqué — on ne revient pas en arrière
function Test-CanGoBack([string]$Id) {
    if ($Id -eq 'done') { return $false }
    return ($null -ne (Get-PreviousInstallStep $Id))
}

# 'Done' (étape passée), 'Current' ou 'Upcoming'
function Get-InstallStepStatus([string]$Id, [string]$CurrentId) {
    $index   = Get-InstallStepIndex $Id
    $current = Get-InstallStepIndex $CurrentId
    if ($index -lt $current) { return 'Done' }
    if ($index -eq $current) { return 'Current' }
    return 'Upcoming'
}

function Get-InstallStepLabel([string]$Id, [string]$CurrentId) {
    $title = $InstallStepTitles[$Id]
    if ((Get-InstallStepStatus $Id $CurrentId) -eq 'Done') { return "✓ $title" }
    return $title
}

function Get-InstallStepColor([string]$Status) {
    switch ($Status) {
        'Done'    { return 'Accent' }
        'Current' { return 'Gold' }
    }
    return 'Muted'
}

function Get-NextButtonText([string]$Id) {
    switch ($Id) {
        'apps'      { return 'Appliquer' }
        'shortcuts' { return 'Appliquer' }
        'done'      { return 'Fermer' }
    }
    return 'Suivant'
}

# Géométrie déduite de la zone cliente : colonne des étapes à gauche, page au centre, barre et boutons en bas
function Get-InstallLayout([int]$ClientWidth, [int]$ClientHeight) {
    $contentTop  = 70
    $buttonsTop  = $ClientHeight - 34 - 12
    $progressTop = $buttonsTop - 22
    return @{
        SidebarWidth  = 230
        ContentLeft   = 250
        ContentTop    = $contentTop
        ContentWidth  = $ClientWidth - 250 - 14
        ContentHeight = $progressTop - $contentTop - 8
        ProgressTop   = $progressTop
        RuleTop       = $buttonsTop - 12
        ButtonsTop    = $buttonsTop
        ButtonWidth   = 110
    }
}

# ---------------------------------------------------------------- Listes à cocher (pure)

# ItemCheck est levé AVANT que la case change : le changement en attente est appliqué pour refléter l'état à venir
function Get-CheckedItemIds([string[]]$Ids, [int[]]$CheckedIndices, [int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    $checked = @($CheckedIndices | Where-Object { $_ -ne $PendingIndex })
    if ($PendingIndex -ge 0 -and $PendingChecked) { $checked += $PendingIndex }
    return @($checked | Sort-Object | ForEach-Object { $Ids[$_] })
}

# Élément de liste à cocher : Key (identifiant) + Label (texte affiché) ; l'appelant enveloppe dans @()
function New-InstallListItem([string]$Key, [string]$Label) {
    return [pscustomobject]@{ Key = $Key; Label = $Label }
}

function Get-CompanionListItems([object[]]$Catalog, [object[]]$Installed) {
    return @($Catalog | ForEach-Object { New-InstallListItem $_.id (Get-CompanionChoiceLabel $_ $Installed) })
}

function Get-LocaleListItems([object[]]$Locales) {
    return @($Locales | ForEach-Object { New-InstallListItem $_.code "$($_.code)   $($_.label)" })
}

function Get-ShortcutCompanionListItems([object[]]$CompanionApps) {
    return @($CompanionApps | ForEach-Object { New-InstallListItem $_.id $_.name })
}

# ---------------------------------------------------------------- Détection (pure)

function Test-InstallPathPresent([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return [bool](Test-Path $Path)
}

# Un élément détecté : libellé, valeur affichée dans un encadré, statut sous l'encadré (Accent = trouvé, Danger = manquant)
function New-DetectionItem([string]$Label, [string]$Path, [string]$MissingText) {
    if (Test-InstallPathPresent $Path) { return [pscustomobject]@{ Label = $Label; Value = $Path; Status = 'Trouvé'; Color = 'Accent' } }
    return [pscustomobject]@{ Label = $Label; Value = $Path; Status = "Introuvable — $MissingText"; Color = 'Danger' }
}

function Get-CompanionNamesText([object[]]$CompanionApps) {
    $names = @($CompanionApps | ForEach-Object { $_.name } | Where-Object { $_ })
    if ($names.Count -eq 0) { return 'aucune' }
    return ($names -join ', ')
}

function Get-DetectionItems($Config) {
    return @(
        (New-DetectionItem 'Riot Client' $Config.riotClientPath "corrigez riotClientPath dans config.json")
        (New-DetectionItem 'Fichier de langue de LoL' $Config.productSettingsPath "League of Legends est-il installé ?")
        [pscustomobject]@{ Label = 'Applis compagnon déjà installées'; Value = (Get-CompanionNamesText @($Config.companionApps)); Status = ''; Color = 'Cream' }
    )
}

# Vue en lignes (Text + Color) des éléments détectés, pour les résumés et les tests
function Get-DetectionSummaryLines($Config) {
    return @(Get-DetectionItems $Config | ForEach-Object {
        $text = "$($_.Label) : $($_.Value)"
        if ($_.Color -eq 'Danger') { $text += " — introuvable ($($_.Status -replace '^Introuvable — ', ''))" }
        [pscustomobject]@{ Text = $text; Color = $(if ($_.Color -eq 'Danger') { 'Danger' } else { 'Cream' }) }
    })
}

function Get-ConfigStatusText([bool]$Created, [string]$Path) {
    if ($Created) { return "Un fichier de réglages (config.json) a été créé pour cet ordinateur." }
    return "Vos réglages existants (config.json) sont conservés tels quels."
}

# Un config.json existant n'est jamais écrasé : les réglages faits à la main sont conservés (même règle que detect-config.ps1)
function Initialize-InstallConfig([string]$Path) {
    $created = -not (Test-Path $Path)
    if ($created) { Write-LaunchConfig (New-LaunchConfig) $Path }
    return @{ Config = (Read-LaunchConfig $Path); Created = $created }
}

# ---------------------------------------------------------------- Bilans (pure)

function Get-CompanionOutcomeLines($Result) {
    $lines = @(foreach ($name in @($Result.UninstallFailed)) {
        "Erreur : $name est toujours présente — rien n'a été installé, config.json inchangé. Corrigez puis cliquez à nouveau sur Appliquer."
    })
    $lines += @(foreach ($name in @($Result.InstallFailed)) {
        "Avertissement : $name n'est pas installée pour l'instant — le lanceur l'ignorera tant qu'elle est absente."
    })
    if ($lines.Count -eq 0) { $lines = @('Applis compagnon à jour.') }
    return $lines
}

function Resolve-ShortcutCompanions($Config, [string[]]$Ids) {
    return @($Ids | ForEach-Object { Find-LaunchCompanion $Config $_ } | Where-Object { $null -ne $_ })
}

function Get-ShortcutCountText([string[]]$Paths) {
    $paths = @($Paths | Where-Object { $_ })
    if ($paths.Count -eq 0) { return 'Raccourcis : aucun créé' }
    $folders = @($paths | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique)
    $plural  = if ($paths.Count -gt 1) { 's' } else { '' }
    return "Raccourcis : $($paths.Count) créé$plural dans $($folders -join ', ')"
}

function Get-CompletionSummaryLines($Config, [string]$ConfigPath, [string[]]$ShortcutPaths) {
    return @(
        "Configuration : $ConfigPath"
        "Applis compagnon retenues : $(Get-CompanionNamesText @($Config.companionApps))"
        (Get-ShortcutCountText $ShortcutPaths)
    )
}

# ---------------------------------------------------------------- Journal et sûreté d'exécution

# Ajoute une ligne au journal de la page courante (s'il y en a un) et rafraîchit la fenêtre
function Write-InstallLog([string]$Text) {
    $log = $script:InstallState.Controls.Log
    if ($null -eq $log) { return }
    if ($log.TextLength -gt 0) { $log.AppendText("`r`n") }
    $log.AppendText($Text)
    Invoke-SplashTick
}

# Les avertissements du moteur (Write-Warning) n'ont pas de console ici : ils sont détournés vers le journal.
# Rend la dernière valeur produite par l'action.
function Invoke-InstallLogged([scriptblock]$Action) {
    $result = $null
    & $Action 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) { Write-InstallLog "Avertissement : $($_.Message)" }
        else { $result = $_ }
    } | Out-Null
    return $result
}

function Show-InstallErrorBox([string]$Text) {
    [void][System.Windows.Forms.MessageBox]::Show($Text, $InstallWindowTitle, 'OK', 'Error')
}

function Stop-InstallOnError([string]$Message) {
    $script:InstallState.ExitCode = 1
    $script:InstallState.IsBusy   = $false
    Show-InstallErrorBox "L'installation a échoué :`r`n`r`n$Message"
    if ($null -ne $script:InstallState.Form) { $script:InstallState.Form.Close() }
}

# Une exception dans un gestionnaire d'événement WinForms serait avalée : on la transforme en fin d'installation (code 1)
function Invoke-InstallSafely([scriptblock]$Action) {
    try   { & $Action }
    catch { Stop-InstallOnError $_.Exception.Message }
}

# Reçoit les étapes du moteur (« Téléchargement de X… ») dans le journal ; aucun splash séparé
function Register-InstallCompanionUi {
    if ($null -eq $script:CompanionUi) { $script:CompanionUi = @{ OnStep = $null; UseSplash = $true } }
    $script:CompanionUi.OnStep    = { param([string]$Text) Write-InstallLog $Text }
    $script:CompanionUi.UseSplash = $false
}

# ---------------------------------------------------------------- Fenêtre

function New-InstallSidebar([int]$Height) {
    $panel      = New-ThemedPanel 0 0 230 $Height
    $panel.Dock = 'Left'
    $panel.Controls.Add((New-ThemedLabel "HEX`r`nLAUNCHER" 20 24 200 66 'Gold' 15 'Bold'))
    $panel.Controls.Add((New-ThemedLabel 'League of Legends' 20 92 200 24 'Muted' 10))
    $labels = @{}
    for ($i = 0; $i -lt $InstallSteps.Count; $i++) {
        $label = New-ThemedLabel '' 20 (150 + 36 * $i) 200 28 'Muted' 10
        $labels[$InstallSteps[$i]] = $label
        $panel.Controls.Add($label)
    }
    $script:InstallState.Controls.StepLabels = $labels
    return $panel
}

function New-InstallFooter($Layout) {
    $controls = $script:InstallState.Controls
    $right    = $Layout.ContentLeft + $Layout.ContentWidth
    $controls.Progress = New-ThemedProgressBar $Layout.ContentLeft $Layout.ProgressTop $Layout.ContentWidth
    $controls.Cancel   = New-ThemedButton 'Annuler' $Layout.ContentLeft $Layout.ButtonsTop $Layout.ButtonWidth
    $controls.Back     = New-ThemedButton 'Retour' ($right - 2 * $Layout.ButtonWidth - 10) $Layout.ButtonsTop $Layout.ButtonWidth
    $controls.Next     = New-ThemedButton 'Suivant' ($right - $Layout.ButtonWidth) $Layout.ButtonsTop $Layout.ButtonWidth 34 $true
    $controls.Cancel.Add_Click({ Invoke-InstallSafely { Invoke-InstallCancel } })
    $controls.Back.Add_Click({ Invoke-InstallSafely { Invoke-InstallBack } })
    $controls.Next.Add_Click({ Invoke-InstallSafely { Invoke-InstallNext } })
    return @($controls.Progress, (New-ThemedRule $Layout.ContentLeft $Layout.RuleTop $Layout.ContentWidth), $controls.Cancel, $controls.Back, $controls.Next)
}

function New-InstallWindow {
    $state    = $script:InstallState
    $form     = New-ThemedForm $InstallWindowTitle 800 560
    $layout   = Get-InstallLayout $form.ClientSize.Width $form.ClientSize.Height
    $controls = $state.Controls
    $controls.PageTitle = New-ThemedTitle '' $layout.ContentLeft 24 $layout.ContentWidth
    $controls.Content   = New-ThemedPanel $layout.ContentLeft $layout.ContentTop $layout.ContentWidth $layout.ContentHeight 'Background'
    $form.Controls.Add((New-InstallSidebar $form.ClientSize.Height))
    $form.Controls.AddRange([System.Windows.Forms.Control[]](@($controls.PageTitle, $controls.Content) + (New-InstallFooter $layout)))
    # Pendant une installation, fermer la fenêtre laisserait un installeur orphelin : la croix est neutralisée
    $form.Add_FormClosing({ param($sender, $e) if ($script:InstallState.IsBusy) { $e.Cancel = $true } })
    $state.Form   = $form
    $state.Layout = $layout
    return $form
}

function Update-InstallSidebar([string]$CurrentId) {
    $labels = $script:InstallState.Controls.StepLabels
    foreach ($id in $InstallSteps) {
        $status = Get-InstallStepStatus $id $CurrentId
        $style  = if ($status -eq 'Current') { 'Bold' } else { 'Regular' }
        $labels[$id].Text      = Get-InstallStepLabel $id $CurrentId
        $labels[$id].ForeColor = Get-ThemeColor (Get-InstallStepColor $status)
        $labels[$id].Font      = New-ThemeFont 10 $style
    }
}

function Update-InstallNavigation {
    $state    = $script:InstallState
    $controls = $state.Controls
    $isDone   = $state.StepId -eq 'done'
    $controls.Next.Text      = Get-NextButtonText $state.StepId
    $controls.Back.Visible   = Test-CanGoBack $state.StepId
    $controls.Cancel.Visible = -not $isDone
    $state.Form.AcceptButton = $controls.Next
    $state.Form.CancelButton = if ($isDone) { $controls.Next } else { $controls.Cancel }
}

# Gèle la navigation et les saisies pendant une action longue ; la barre marquee signale l'attente
function Set-InstallBusy([bool]$Busy) {
    $state    = $script:InstallState
    $controls = $state.Controls
    $state.IsBusy = $Busy
    foreach ($button in @($controls.Cancel, $controls.Back, $controls.Next)) { $button.Enabled = -not $Busy }
    foreach ($control in @($controls.Inputs)) { $control.Enabled = -not $Busy }
    $controls.Progress.Visible = $Busy
    Invoke-SplashTick
}

function Set-InstallPageTitle([string]$Text) {
    $script:InstallState.Controls.PageTitle.Text = $Text.ToUpperInvariant()
}

function Clear-InstallContent {
    $content = $script:InstallState.Controls.Content
    $old     = @($content.Controls | ForEach-Object { $_ })
    $content.Controls.Clear()
    foreach ($control in $old) { $control.Dispose() }
}

function Add-InstallContent([object[]]$Controls) {
    $script:InstallState.Controls.Content.Controls.AddRange([System.Windows.Forms.Control[]]$Controls)
}

# $Items : liste de @{ Key ; Label } ; les clés de $Preselected sont cochées ; les clés sont rangées dans Tag
function New-InstallCheckedList([object[]]$Items, [string[]]$Preselected, [int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $list = New-ThemedCheckedListBox $Left $Top $Width $Height
    foreach ($item in $Items) {
        $index = $list.Items.Add($item.Label)
        $list.SetItemChecked($index, ($Preselected -contains $item.Key))
    }
    $list.Tag = [string[]]@($Items | ForEach-Object { $_.Key })
    return $list
}

function Get-InstallCheckedKeys($List, [int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    return Get-CheckedItemIds $List.Tag @($List.CheckedIndices) $PendingIndex $PendingChecked
}

# ---------------------------------------------------------------- Page 1 : détection

function Initialize-InstallDetection {
    $state = $script:InstallState
    if ($null -ne $state.Config) { return }
    $detection = Initialize-InstallConfig $InstallConfigPath
    $state.Config         = $detection.Config
    $state.ConfigCreated  = $detection.Created
    $state.DetectionItems = @(Get-DetectionItems $detection.Config)
}

# Libellé, encadré (2 lignes, retour à la ligne) et statut ; retourne les contrôles et la hauteur occupée
function New-DetectionItemControls($Item, [int]$Top, [int]$Width) {
    $controls = @(
        (New-ThemedLabel $Item.Label 0 $Top $Width 22 'Gold' 10 'Bold')
        (New-ThemedField $Item.Value 0 ($Top + 24) $Width 46)
    )
    $height = 74
    if ($Item.Status) { $controls += New-ThemedLabel $Item.Status 0 ($Top + 72) $Width 22 $Item.Color; $height += 24 }
    return @{ Controls = $controls; Height = $height + 8 }
}

function Show-InstallDetectPage {
    Initialize-InstallDetection
    $state = $script:InstallState
    $width = $state.Layout.ContentWidth
    $controls = @(
        (New-ThemedLabel "Bienvenue ! Voici ce que nous avons trouvé sur cet ordinateur — rien n'est modifié à cette étape. Si un emplacement est faux, vous pourrez le corriger dans config.json et relancer l'installation." 0 0 $width 48 'Muted')
        (New-ThemedLabel (Get-ConfigStatusText $state.ConfigCreated $InstallConfigPath) 0 52 $width 22 'Accent')
    )
    $top = 86
    foreach ($item in $state.DetectionItems) {
        $built = New-DetectionItemControls $item $top $width
        $controls += $built.Controls
        $top += $built.Height
    }
    Add-InstallContent $controls
}

# ---------------------------------------------------------------- Page 2 : applis compagnon

function Get-InstallCompanionChoice([int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    $controls = $script:InstallState.Controls
    return @{
        SelectedIds     = @(Get-InstallCheckedKeys $controls.AppList $PendingIndex $PendingChecked)
        UninstallOthers = [bool]$controls.UninstallBox.Checked
    }
}

function Update-InstallCompanionSummary([int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    $state   = $script:InstallState
    $actions = Get-CompanionActions $state.Catalog $state.Installed (Get-InstallCompanionChoice $PendingIndex $PendingChecked)
    $state.Controls.Log.Text = Format-CompanionActions $actions
}

function New-InstallAppsControls {
    $state    = $script:InstallState
    $controls = $state.Controls
    $width    = $state.Layout.ContentWidth
    $items    = @(Get-CompanionListItems $state.Catalog $state.Installed)
    $controls.AppList      = New-InstallCheckedList $items (Get-PreselectedCompanionIds $state.Catalog $state.Installed $state.Config) 0 50 $width (24 * [Math]::Max(1, $items.Count) + 8)
    $checkTop              = 50 + $controls.AppList.Height + 10
    $controls.UninstallBox = New-ThemedCheckBox 'Désinstaller les applis décochées présentes sur ce PC' 0 $checkTop $width
    $controls.Log          = New-ThemedLog 0 ($checkTop + 62) $width ($state.Layout.ContentHeight - $checkTop - 62)
    $controls.Inputs       = @($controls.AppList, $controls.UninstallBox)
    $controls.AppList.Add_ItemCheck({ param($sender, $e) Invoke-InstallSafely { Update-InstallCompanionSummary $e.Index ($e.NewValue -eq 'Checked') } })
    $controls.UninstallBox.Add_CheckedChanged({ Invoke-InstallSafely { Update-InstallCompanionSummary } })
    return @(
        (New-ThemedLabel 'Applis lancées après le jeu (un raccourci par appli cochée). Les applis cochées absentes seront installées.' 0 0 $width 44 'Muted')
        $controls.AppList
        $controls.UninstallBox
        (New-ThemedLabel 'Actions prévues' 0 ($checkTop + 36) $width 22 'Gold' 10 'Bold')
        $controls.Log
    )
}

function Show-InstallAppsPage {
    $state = $script:InstallState
    $state.Catalog   = @(Read-CompanionCatalog $InstallCatalogPath)
    $state.Installed = @(Get-InstalledCompanionApps $state.Catalog)
    Add-InstallContent (New-InstallAppsControls)
    Update-InstallCompanionSummary
}

# Journal : étapes (hook OnStep), avertissements du moteur, puis bilan ; navigation gelée pendant l'exécution
function Invoke-InstallCompanionActions($Actions) {
    Set-InstallBusy $true
    try {
        Write-InstallLog ''
        Write-InstallLog 'Application des changements…'
        $result = Invoke-InstallLogged { Invoke-CompanionActions $Actions }
    }
    finally { Set-InstallBusy $false }
    foreach ($line in Get-CompanionOutcomeLines $result) { Write-InstallLog $line }
    return $result
}

# Rend vrai si l'on peut passer à l'étape suivante ; une désinstallation échouée laisse la page affichée, config.json intact
function Invoke-InstallAppsStep {
    $state   = $script:InstallState
    $actions = Get-CompanionActions $state.Catalog $state.Installed (Get-InstallCompanionChoice)
    if (Test-CompanionActionsPending $actions) {
        $result = Invoke-InstallCompanionActions $actions
        if (@($result.UninstallFailed).Count -gt 0) { return $false }
    }
    Write-CompanionConfig $state.Config $InstallConfigPath $actions.Selected | Out-Null
    $state.Installed = @(Get-InstalledCompanionApps $state.Catalog)
    return $true
}

# ---------------------------------------------------------------- Page 3 : raccourcis

function New-InstallShortcutsControls {
    $state    = $script:InstallState
    $controls = $state.Controls
    $layout   = $state.Layout
    $companionApps = @($state.Config.companionApps)
    $columnWidth   = [int](($layout.ContentWidth - 20) / 2)
    $rightColumn   = $columnWidth + 20
    $companionRows = [Math]::Max(1, $companionApps.Count)
    $controls.LocaleList    = New-InstallCheckedList (Get-LocaleListItems $state.Locales) (Get-PreselectedCodes $state.Locales $state.ExistingShortcuts) 0 72 $columnWidth 230
    $controls.CompanionList = New-InstallCheckedList (Get-ShortcutCompanionListItems $companionApps) (Get-PreselectedShortcutCompanionIds $companionApps $state.ExistingShortcuts) $rightColumn 72 $columnWidth ([Math]::Min(230, 24 * $companionRows + 8))
    $controls.Log           = New-ThemedLog 0 312 $layout.ContentWidth ($layout.ContentHeight - 312)
    $controls.Inputs        = @($controls.LocaleList, $controls.CompanionList)
    return @(
        (New-ThemedLabel "Un raccourci par langue cochée × appli compagnon cochée, dans $Destination. Sans appli cochée : un raccourci par langue, sans compagnon." 0 0 $layout.ContentWidth 44 'Muted')
        (New-ThemedLabel 'Langues' 0 48 $columnWidth 22 'Gold' 10 'Bold')
        (New-ThemedLabel 'Applis compagnon' $rightColumn 48 $columnWidth 22 'Gold' 10 'Bold')
        $controls.LocaleList
        $controls.CompanionList
        $controls.Log
    )
}

function Show-InstallShortcutsPage {
    $state = $script:InstallState
    $state.Locales           = @(Read-LocaleCatalog $localesPath)
    $state.ExistingShortcuts = @(Get-ExistingLaunchShortcuts $Destination)
    Add-InstallContent (New-InstallShortcutsControls)
}

function Get-InstallShortcutSelection {
    $controls = $script:InstallState.Controls
    return @{
        Codes        = @(Get-InstallCheckedKeys $controls.LocaleList)
        CompanionIds = @(Get-InstallCheckedKeys $controls.CompanionList)
    }
}

function New-InstallShortcuts([object[]]$Combinations) {
    $created = foreach ($combination in $Combinations) {
        $path = Invoke-InstallLogged { New-LaunchShortcutWithFallback $combination }
        Write-InstallLog "Créé : $path"
        $path
    }
    return @($created | Where-Object { $_ })
}

# Rend vrai si des raccourcis ont été créés ; sans langue cochée, on reste sur la page
function Invoke-InstallShortcutsStep {
    $state     = $script:InstallState
    $selection = Get-InstallShortcutSelection
    if ($selection.Codes.Count -eq 0) {
        Write-InstallLog 'Aucune langue cochée : cochez au moins une langue pour créer un raccourci.'
        return $false
    }
    $combinations = Get-ShortcutCombinations $selection.Codes (Resolve-ShortcutCompanions $state.Config $selection.CompanionIds)
    $state.ShortcutPaths = @(New-InstallShortcuts $combinations)
    foreach ($line in @(Remove-ObsoleteShortcuts $state.ExistingShortcuts $combinations)) { Write-InstallLog $line }
    return $true
}

# ---------------------------------------------------------------- Page 4 : terminé

function Show-InstallDonePage {
    $state = $script:InstallState
    $width = $state.Layout.ContentWidth
    $state.ExitCode = 0
    $controls = @(New-ThemedLabel 'Installation terminée.' 0 0 $width 26 'Accent' 11 'Bold')
    $top = 44
    foreach ($line in Get-CompletionSummaryLines $state.Config $InstallConfigPath $state.ShortcutPaths) {
        $controls += New-ThemedLabel $line 0 $top $width 46 'Cream'
        $top += 52
    }
    $controls += New-ThemedLabel 'Double-cliquez sur un raccourci pour lancer le jeu dans la langue voulue. Relancez install.bat pour ajouter ou retirer des langues ou des applis compagnon.' 0 ($top + 8) $width 60 'Muted'
    Add-InstallContent $controls
}

# ---------------------------------------------------------------- Navigation

function Show-InstallPage([string]$StepId) {
    $state = $script:InstallState
    $state.StepId          = $StepId
    $state.Controls.Log    = $null
    $state.Controls.Inputs = @()
    Clear-InstallContent
    Update-InstallSidebar $StepId
    Set-InstallPageTitle $InstallPageTitles[$StepId]
    switch ($StepId) {
        'detect'    { Show-InstallDetectPage }
        'apps'      { Show-InstallAppsPage }
        'shortcuts' { Show-InstallShortcutsPage }
        'done'      { Show-InstallDonePage }
    }
    Update-InstallNavigation
}

# Action d'une page au clic sur Suivant/Appliquer ; rend vrai si l'on peut avancer
function Invoke-InstallStepAction([string]$StepId) {
    switch ($StepId) {
        'apps'      { return Invoke-InstallAppsStep }
        'shortcuts' { return Invoke-InstallShortcutsStep }
    }
    return $true
}

function Invoke-InstallNext {
    $state = $script:InstallState
    if ($state.StepId -eq 'done') { $state.Form.Close(); return }
    if (-not (Invoke-InstallStepAction $state.StepId)) { return }
    Show-InstallPage (Get-NextInstallStep $state.StepId)
}

function Invoke-InstallBack {
    $stepId = $script:InstallState.StepId
    if (-not (Test-CanGoBack $stepId)) { return }
    Show-InstallPage (Get-PreviousInstallStep $stepId)
}

function Invoke-InstallCancel {
    $script:InstallState.ExitCode = 2
    $script:InstallState.Form.Close()
}

# Rend le code de sortie du script
function Start-InstallWizard {
    if (Test-CompanionElevated) {
        Show-InstallErrorBox "Ne pas exécuter en tant qu'administrateur : les installeurs sont per-user et les désinstalleurs sont lus dans le registre utilisateur.`r`n`r`nRelancez install.bat normalement."
        return 1
    }
    Register-InstallCompanionUi
    $form = New-InstallWindow
    Show-InstallPage 'detect'
    [void]$form.ShowDialog()
    $form.Dispose()
    return $script:InstallState.ExitCode
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    try   { [int]$exitCode = Start-InstallWizard; exit $exitCode }
    catch { Show-InstallErrorBox "L'installation a échoué :`r`n`r`n$($_.Exception.Message)"; exit 1 }
}
