<#
.SYNOPSIS
    Assistant de configuration de hex-launcher : une seule fenêtre au thème League of Legends,
    quatre étapes — détection, applis compagnon, raccourcis, terminé.

.DESCRIPTION
    Lancé par setup.bat (sans console). Les scripts existants restent le moteur : ils sont dot-sourcés
    (leur bloc Main est ignoré) et l'assistant n'orchestre que leurs fonctions :
        detect-config.ps1        → config.json (généré s'il manque, jamais écrasé ; chemins Riot corrigeables sur la page 1)
        manage-companion-app.ps1 → choix, installation et désinstallation des applis compagnon
        create-shortcuts.ps1     → un raccourci par langue × appli compagnon dans la destination

    La navigation repose sur une machine à états pure (Get-NextInstallStep, Test-CanGoBack…) testée sans fenêtre ;
    les étapes du moteur et ses avertissements sont détournés vers le journal de la fenêtre (aucun splash séparé).

    Codes de sortie : 0 terminé · 1 erreur · 2 annulé
    Sécurité : refuse de tourner élevé (administrateur), comme manage-companion-app.ps1.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File setup.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Destination "D:\Jeux"
    powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Language ja
#>
param(
    # Dossier où créer les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop'),

    # Langue de l'assistant : fr, en ou ja (défaut : langue de Windows, sinon anglais)
    [string]$Language
)

. (Join-Path $PSScriptRoot 'lib\i18n.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\theme.lib.ps1')
. (Join-Path $PSScriptRoot 'detect-config.ps1')
. (Join-Path $PSScriptRoot 'manage-companion-app.ps1')
. (Join-Path $PSScriptRoot 'create-shortcuts.ps1') -Destination $Destination

# Après les dot-sourcings : chaque moteur recharge la lib i18n, qui remet son état à zéro
Initialize-Translation (Resolve-UiLanguage $Language (Get-UICulture).Name) | Out-Null

$SetupConfigPath  = Join-Path $PSScriptRoot 'config.json'
$SetupCatalogPath = Join-Path $PSScriptRoot 'companion-apps.json'

function Get-SetupWindowTitle {
    return Get-Text 'setup.windowTitle'
}

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
    IconSets         = @()
    ExistingShortcuts = @()
    ShortcutPaths    = @()
    SetupShortcutPath = ''
    PendingSelection = $null   # cases cochées à restaurer au redessin de la page (changement de langue)
    Form             = $null
    Layout           = $null
    Controls         = @{}
}

# Contrôles propres à une page : remis à zéro à chaque affichage, pour ne jamais lire un contrôle détruit
$SetupPageControlNames = @('Log', 'AppList', 'UninstallBox', 'LocaleList', 'CompanionList', 'RiotPathBoxes', 'RiotPathStatuses')

# Dossier d'installation habituel de Riot : point de départ de « Parcourir… » quand le chemin courant ne mène nulle part
$SetupRiotGamesFolder = 'C:\Riot Games'

# ---------------------------------------------------------------- Machine à états (pure, sans WinForms)

$SetupSteps = @('detect', 'apps', 'shortcuts', 'done')

function Get-SetupStepIndex([string]$Id) {
    return [array]::IndexOf($SetupSteps, $Id)
}

# Textes lus à chaque affichage, jamais figés au chargement : la langue peut changer en cours de route
function Get-SetupPageTitle([string]$Id) {
    return Get-Text "setup.page.$Id"
}

# « 1. Bienvenue » : rang de l'étape + titre de la page
function Get-SetupStepTitle([string]$Id) {
    return "$((Get-SetupStepIndex $Id) + 1). $(Get-SetupPageTitle $Id)"
}

function Get-NextInstallStep([string]$Id) {
    $index = Get-SetupStepIndex $Id
    if ($index -lt 0 -or $index -ge $SetupSteps.Count - 1) { return $null }
    return $SetupSteps[$index + 1]
}

function Get-PreviousInstallStep([string]$Id) {
    $index = Get-SetupStepIndex $Id
    if ($index -le 0) { return $null }
    return $SetupSteps[$index - 1]
}

# BUSINESS_RULE : une fois terminé, tout est appliqué — on ne revient pas en arrière
function Test-CanGoBack([string]$Id) {
    if ($Id -eq 'done') { return $false }
    return ($null -ne (Get-PreviousInstallStep $Id))
}

# 'Done' (étape passée), 'Current' ou 'Upcoming'
function Get-SetupStepStatus([string]$Id, [string]$CurrentId) {
    $index   = Get-SetupStepIndex $Id
    $current = Get-SetupStepIndex $CurrentId
    if ($index -lt $current) { return 'Done' }
    if ($index -eq $current) { return 'Current' }
    return 'Upcoming'
}

function Get-SetupStepLabel([string]$Id, [string]$CurrentId) {
    $title = Get-SetupStepTitle $Id
    if ((Get-SetupStepStatus $Id $CurrentId) -eq 'Done') { return "✓ $title" }
    return $title
}

function Get-SetupStepColor([string]$Status) {
    switch ($Status) {
        'Done'    { return 'Accent' }
        'Current' { return 'Gold' }
    }
    return 'Muted'
}

function Get-NextButtonText([string]$Id) {
    switch ($Id) {
        'apps'      { return Get-Text 'common.apply' }
        'shortcuts' { return Get-Text 'common.apply' }
        'done'      { return Get-Text 'setup.button.close' }
    }
    return Get-Text 'setup.button.next'
}

# Géométrie déduite de la zone cliente : colonne des étapes à gauche, page au centre, barre et boutons en bas
function Get-SetupLayout([int]$ClientWidth, [int]$ClientHeight) {
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
function New-SetupListItem([string]$Key, [string]$Label) {
    return [pscustomobject]@{ Key = $Key; Label = $Label }
}

function Get-CompanionListItems([object[]]$Catalog, [object[]]$Installed) {
    return @($Catalog | ForEach-Object { New-SetupListItem $_.id (Get-CompanionChoiceLabel $_ $Installed) })
}

function Get-LocaleListItems([object[]]$Locales) {
    return @($Locales | ForEach-Object { New-SetupListItem $_.code "$($_.code)   $($_.label)" })
}

# Un jeu d'icônes par sous-dossier de ico\ ; le nom du dossier est le libellé
function Get-IconSetListItems([object[]]$Sets) {
    return @($Sets | ForEach-Object { New-SetupListItem $_.Name $_.Name })
}

# Jeu présélectionné : celui de config.json s'il existe encore, sinon le jeu par défaut
function Get-PreselectedIconSetName($Config, [object[]]$Sets) {
    $wanted = Find-IconSet $Sets (Get-LaunchIconSetName $Config)
    if ($wanted) { return $wanted.Name }
    $default = Get-DefaultIconSet $Sets
    if ($default) { return $default.Name }
    return ''
}

# Image d'aperçu d'un jeu : l'entrée de hex-launcher.ico de la taille demandée (ou la plus grande en dessous) ; $null si illisible
function New-IconSetPreviewImage($Set, [int]$Size) {
    if (-not $Set) { return $null }
    try {
        $entries = @(Read-IcoEntries (Get-IconSetFilePath $Set $IconSetBaseIcon))
        $chosen  = @($entries | Where-Object { $_.Size -le $Size } | Sort-Object Size -Descending | Select-Object -First 1)
        if ($chosen.Count -eq 0) { $chosen = @($entries | Sort-Object Size | Select-Object -First 1) }
        $image = $chosen[0].Bitmap.Clone()
        $entries | ForEach-Object { $_.Bitmap.Dispose() }
        return $image
    } catch { return $null }
}

function Get-ShortcutCompanionListItems([object[]]$CompanionApps) {
    return @($CompanionApps | ForEach-Object { New-SetupListItem $_.id $_.name })
}

# ---------------------------------------------------------------- Détection (pure)

function Test-SetupPathPresent([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return [bool](Test-Path $Path)
}

# Statut d'un chemin : trouvé (Accent) ou introuvable avec la raison (Danger) ; recalculé à chaque frappe sur la page
function Get-DetectionPathStatus([string]$Path, [string]$MissingReason) {
    $isFound = Test-SetupPathPresent (ConvertTo-LaunchPathValue $Path)
    return @{
        IsFound = $isFound
        Text    = $(if ($isFound) { Get-Text 'setup.detect.found' } else { Get-Text 'setup.detect.missing' $MissingReason })
        Color   = $(if ($isFound) { 'Accent' } else { 'Danger' })
    }
}

# Un élément détecté : libellé, valeur affichée dans un encadré, statut sous l'encadré (Accent = trouvé, Danger = manquant).
# IsFound et MissingReason portent l'état ; Status n'est que son texte affiché.
# Key (clé de Get-LaunchRiotPaths) et FileFilter ne sont posés que sur un chemin corrigeable dans la page.
function New-DetectionItem([string]$Label, [string]$Path, [string]$MissingReason, [string]$Key = '', [string]$FileFilter = '') {
    $status = Get-DetectionPathStatus $Path $MissingReason
    return [pscustomobject]@{
        Label = $Label; Value = $Path; IsFound = $status.IsFound; MissingReason = $MissingReason
        Status = $status.Text; Color = $status.Color; Key = $Key; FileFilter = $FileFilter
    }
}

function Test-DetectionItemEditable($Item) {
    return -not [string]::IsNullOrEmpty($Item.Key)
}

# Dossier d'ouverture de « Parcourir… » : celui du chemin courant s'il existe, sinon C:\Riot Games, sinon le choix de Windows ('')
function Get-SetupBrowseStartFolder([string]$CurrentPath) {
    $folder = ''
    if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
        try { $folder = [string](Split-Path $CurrentPath -Parent) } catch { $folder = '' }
    }
    if ($folder -and (Test-Path $folder)) { return $folder }
    if (Test-Path $SetupRiotGamesFolder) { return $SetupRiotGamesFolder }
    return ''
}

function Get-CompanionNamesText([object[]]$CompanionApps) {
    $names = @($CompanionApps | ForEach-Object { $_.name } | Where-Object { $_ })
    if ($names.Count -eq 0) { return Get-Text 'common.none' }
    return ($names -join ', ')
}

# Raison d'un manque : nom du fichier attendu et son dossier habituel (ceux que detect-config.ps1 cherche),
# pour que l'utilisateur sache quoi chercher dans « Parcourir… »
function Get-DetectionMissingReason([string]$Key, [string]$UsualPath) {
    return Get-Text $Key (Split-Path $UsualPath -Leaf), (Split-Path $UsualPath -Parent)
}

function Get-DetectionItems($Config) {
    return @(
        (New-DetectionItem (Get-Text 'setup.detect.riotClient') $Config.riotClientPath (Get-DetectionMissingReason 'setup.detect.fixRiotClient' $RiotClientDefault) 'RiotClientPath' (Get-Text 'setup.detect.filterExe'))
        (New-DetectionItem (Get-Text 'setup.detect.productSettings') $Config.productSettingsPath (Get-DetectionMissingReason 'setup.detect.isLolInstalled' $ProductSettings) 'ProductSettingsPath' (Get-Text 'setup.detect.filterYaml'))
        [pscustomobject]@{
            Label = (Get-Text 'setup.detect.installedApps'); Value = (Get-CompanionNamesText @($Config.companionApps))
            IsFound = $true; MissingReason = ''; Status = ''; Color = 'Cream'; Key = ''; FileFilter = ''
        }
    )
}

function Find-DetectionItem([object[]]$Items, [string]$Key) {
    return @($Items | Where-Object { $_.Key -eq $Key }) | Select-Object -First 1
}

# Rappel du résumé final : un chemin Riot toujours introuvable après l'assistant, avec son libellé et sa valeur
function Get-MissingRiotPathLines($Config) {
    return @(Get-DetectionItems $Config | Where-Object { -not $_.IsFound } | ForEach-Object { Get-Text 'setup.done.pathMissing' $_.Label, $_.Value })
}

# Vue en lignes (Text + Color) des éléments détectés, pour les résumés et les tests
function Get-DetectionSummaryLines($Config) {
    return @(Get-DetectionItems $Config | ForEach-Object {
        if ($_.IsFound) { [pscustomobject]@{ Text = (Get-Text 'setup.detect.summary' $_.Label, $_.Value); Color = 'Cream' } }
        else { [pscustomobject]@{ Text = (Get-Text 'setup.detect.summaryMissing' $_.Label, $_.Value, $_.MissingReason); Color = 'Danger' } }
    })
}

function Get-ConfigStatusText([bool]$Created, [string]$Path) {
    if ($Created) { return Get-Text 'setup.detect.configCreated' }
    return Get-Text 'setup.detect.configKept'
}

# Un config.json existant n'est jamais écrasé : les réglages faits à la main sont conservés (même règle que detect-config.ps1)
function Initialize-SetupConfig([string]$Path) {
    $created = -not (Test-Path $Path)
    if ($created) { Write-LaunchConfig (New-LaunchConfig) $Path }
    return @{ Config = (Read-LaunchConfig $Path); Created = $created }
}

# ---------------------------------------------------------------- Bilans (pure)

function Get-CompanionOutcomeLines($Result) {
    $lines = @(foreach ($name in @($Result.UninstallFailed)) { Get-Text 'setup.apps.uninstallFailed' $name })
    $lines += @(foreach ($name in @($Result.InstallFailed)) { Get-Text 'common.warning' (Get-Text 'companion.notInstalledYet' $name) })
    if ($lines.Count -eq 0) { $lines = @(Get-Text 'setup.apps.upToDate') }
    return $lines
}

function Resolve-ShortcutCompanions($Config, [string[]]$Ids) {
    return @($Ids | ForEach-Object { Find-LaunchCompanion $Config $_ } | Where-Object { $null -ne $_ })
}

function Get-ShortcutCountText([string[]]$Paths) {
    $paths = @($Paths | Where-Object { $_ })
    if ($paths.Count -eq 0) { return Get-Text 'setup.done.shortcuts.none' }
    $folders = @($paths | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique)
    $key     = if ($paths.Count -gt 1) { 'setup.done.shortcuts.many' } else { 'setup.done.shortcuts.one' }
    return Get-Text $key $paths.Count, ($folders -join ', ')
}

function Get-CompletionSummaryLines($Config, [string]$ConfigPath, [string[]]$ShortcutPaths, [string]$SetupShortcutPath = '') {
    $lines = @(
        (Get-Text 'setup.done.config' $ConfigPath)
        (Get-Text 'setup.done.companions' (Get-CompanionNamesText @($Config.companionApps)))
        (Get-ShortcutCountText $ShortcutPaths)
    )
    if ($SetupShortcutPath) { $lines += Get-Text 'setup.done.setupShortcut' $SetupShortcutPath }
    return $lines
}

# ---------------------------------------------------------------- Journal et sûreté d'exécution

# Ajoute une ligne au journal de la page courante (s'il y en a un) et rafraîchit la fenêtre
function Write-SetupLog([string]$Text) {
    $log = $script:InstallState.Controls.Log
    if ($null -eq $log) { return }
    if ($log.TextLength -gt 0) { $log.AppendText("`r`n") }
    $log.AppendText($Text)
    Invoke-SplashTick
}

# Les avertissements du moteur (Write-Warning) n'ont pas de console ici : ils sont détournés vers le journal.
# Rend la dernière valeur produite par l'action.
function Invoke-SetupLogged([scriptblock]$Action) {
    $result = $null
    & $Action 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) { Write-SetupLog (Get-Text 'common.warning' $_.Message) }
        else { $result = $_ }
    } | Out-Null
    return $result
}

function Show-SetupErrorBox([string]$Text) {
    [void][System.Windows.Forms.MessageBox]::Show($Text, (Get-SetupWindowTitle), 'OK', 'Error')
}

function Stop-SetupOnError([string]$Message) {
    $script:InstallState.ExitCode = 1
    $script:InstallState.IsBusy   = $false
    Show-SetupErrorBox (Get-Text 'setup.error.failed' $Message)
    if ($null -ne $script:InstallState.Form) { $script:InstallState.Form.Close() }
}

# Une exception dans un gestionnaire d'événement WinForms serait avalée : on la transforme en fin d'installation (code 1)
function Invoke-SetupSafely([scriptblock]$Action) {
    try   { & $Action }
    catch { Stop-SetupOnError $_.Exception.Message }
}

# Reçoit les étapes du moteur (« Téléchargement de X… ») dans le journal ; aucun splash séparé
function Register-SetupCompanionUi {
    if ($null -eq $script:CompanionUi) { $script:CompanionUi = @{ OnStep = $null; UseSplash = $true } }
    $script:CompanionUi.OnStep    = { param([string]$Text) Write-SetupLog $Text }
    $script:CompanionUi.UseSplash = $false
}

# ---------------------------------------------------------------- Fenêtre

function New-SetupSidebar([int]$Height) {
    $panel      = New-ThemedPanel 0 0 230 $Height
    $panel.Dock = 'Left'
    $panel.Controls.Add((New-ThemedLabel "HEX`r`nLAUNCHER" 20 24 200 66 'Gold' 15 'Bold'))
    $panel.Controls.Add((New-ThemedLabel 'League of Legends' 20 92 200 24 'Muted' 10))
    $labels = @{}
    for ($i = 0; $i -lt $SetupSteps.Count; $i++) {
        $label = New-ThemedLabel '' 20 (150 + 36 * $i) 200 28 'Muted' 10
        $labels[$SetupSteps[$i]] = $label
        $panel.Controls.Add($label)
    }
    $script:InstallState.Controls.StepLabels = $labels
    $panel.Controls.AddRange([System.Windows.Forms.Control[]](New-SetupLanguageControls $Height))
    return $panel
}

# Libellé + liste déroulante des langues ; SelectionChangeCommitted ne réagit qu'au choix de l'utilisateur
function New-SetupLanguageControls([int]$SidebarHeight) {
    $controls = $script:InstallState.Controls
    $controls.LanguageLabel = New-ThemedLabel '' 20 ($SidebarHeight - 100) 190 22 'Muted' 9
    $controls.LanguageBox   = New-ThemedComboBox (Get-UiLanguageItems) (Get-UiLanguage) 20 ($SidebarHeight - 76) 190
    $controls.LanguageBox.Add_SelectionChangeCommitted({
        Invoke-SetupSafely { Set-SetupLanguage (Get-ThemedComboBoxKey $script:InstallState.Controls.LanguageBox) | Out-Null }
    })
    return @($controls.LanguageLabel, $controls.LanguageBox)
}

function New-SetupFooter($Layout) {
    $controls = $script:InstallState.Controls
    $right    = $Layout.ContentLeft + $Layout.ContentWidth
    $controls.Progress = New-ThemedProgressBar $Layout.ContentLeft $Layout.ProgressTop $Layout.ContentWidth
    $controls.Cancel   = New-ThemedButton '' $Layout.ContentLeft $Layout.ButtonsTop $Layout.ButtonWidth
    $controls.Back     = New-ThemedButton '' ($right - 2 * $Layout.ButtonWidth - 10) $Layout.ButtonsTop $Layout.ButtonWidth
    $controls.Next     = New-ThemedButton '' ($right - $Layout.ButtonWidth) $Layout.ButtonsTop $Layout.ButtonWidth 34 $true
    $controls.Cancel.Add_Click({ Invoke-SetupSafely { Invoke-SetupCancel } })
    $controls.Back.Add_Click({ Invoke-SetupSafely { Invoke-SetupBack } })
    $controls.Next.Add_Click({ Invoke-SetupSafely { Invoke-SetupNext } })
    return @($controls.Progress, (New-ThemedRule $Layout.ContentLeft $Layout.RuleTop $Layout.ContentWidth), $controls.Cancel, $controls.Back, $controls.Next)
}

function New-SetupWindow {
    $state    = $script:InstallState
    $form     = New-ThemedForm (Get-SetupWindowTitle) 800 620
    $layout   = Get-SetupLayout $form.ClientSize.Width $form.ClientSize.Height
    $controls = $state.Controls
    $controls.PageTitle = New-ThemedTitle '' $layout.ContentLeft 24 $layout.ContentWidth
    $controls.Content   = New-ThemedPanel $layout.ContentLeft $layout.ContentTop $layout.ContentWidth $layout.ContentHeight 'Background'
    $form.Controls.Add((New-SetupSidebar $form.ClientSize.Height))
    $form.Controls.AddRange([System.Windows.Forms.Control[]](@($controls.PageTitle, $controls.Content) + (New-SetupFooter $layout)))
    # Pendant une installation, fermer la fenêtre laisserait un installeur orphelin : la croix est neutralisée
    $form.Add_FormClosing({ param($sender, $e) if ($script:InstallState.IsBusy) { $e.Cancel = $true } })
    $state.Form   = $form
    $state.Layout = $layout
    return $form
}

function Update-SetupSidebar([string]$CurrentId) {
    $labels = $script:InstallState.Controls.StepLabels
    foreach ($id in $SetupSteps) {
        $status = Get-SetupStepStatus $id $CurrentId
        $style  = if ($status -eq 'Current') { 'Bold' } else { 'Regular' }
        $labels[$id].Text      = Get-SetupStepLabel $id $CurrentId
        $labels[$id].ForeColor = Get-ThemeColor (Get-SetupStepColor $status)
        $labels[$id].Font      = New-ThemeFont 10 $style
    }
    $languageLabel = $script:InstallState.Controls.LanguageLabel
    if ($null -ne $languageLabel) { $languageLabel.Text = Get-Text 'setup.language' }
}

function Update-SetupNavigation {
    $state    = $script:InstallState
    $controls = $state.Controls
    $isDone   = $state.StepId -eq 'done'
    $controls.Cancel.Text    = Get-Text 'common.cancel'
    $controls.Back.Text      = Get-Text 'setup.button.back'
    $controls.Next.Text      = Get-NextButtonText $state.StepId
    $controls.Back.Visible   = Test-CanGoBack $state.StepId
    $controls.Cancel.Visible = -not $isDone
    $state.Form.AcceptButton = $controls.Next
    $state.Form.CancelButton = if ($isDone) { $controls.Next } else { $controls.Cancel }
    # Le focus revient au bouton principal : laissé sur le sélecteur de langue, il le surlignerait aux couleurs système
    $state.Form.ActiveControl = $controls.Next
}

# Gèle la navigation et les saisies pendant une action longue ; la barre marquee signale l'attente
function Set-SetupBusy([bool]$Busy) {
    $state    = $script:InstallState
    $controls = $state.Controls
    $state.IsBusy = $Busy
    foreach ($control in @($controls.Cancel, $controls.Back, $controls.Next, $controls.LanguageBox)) { if ($null -ne $control) { $control.Enabled = -not $Busy } }
    foreach ($control in @($controls.Inputs)) { $control.Enabled = -not $Busy }
    $controls.Progress.Visible = $Busy
    Invoke-SplashTick
}

function Set-SetupPageTitle([string]$Text) {
    $script:InstallState.Controls.PageTitle.Text = $Text.ToUpperInvariant()
}

function Clear-SetupContent {
    $content = $script:InstallState.Controls.Content
    $old     = @($content.Controls | ForEach-Object { $_ })
    $content.Controls.Clear()
    foreach ($control in $old) { $control.Dispose() }
}

function Add-SetupContent([object[]]$Controls) {
    $script:InstallState.Controls.Content.Controls.AddRange([System.Windows.Forms.Control[]]$Controls)
}

# $Items : liste de @{ Key ; Label } ; les clés de $Preselected sont cochées ; les clés sont rangées dans Tag
function New-SetupCheckedList([object[]]$Items, [string[]]$Preselected, [int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $list = New-ThemedCheckedListBox $Left $Top $Width $Height
    foreach ($item in $Items) {
        $index = $list.Items.Add($item.Label)
        $list.SetItemChecked($index, ($Preselected -contains $item.Key))
    }
    $list.Tag = [string[]]@($Items | ForEach-Object { $_.Key })
    return $list
}

function Get-SetupCheckedKeys($List, [int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    return Get-CheckedItemIds $List.Tag @($List.CheckedIndices) $PendingIndex $PendingChecked
}

# Saisie de la page courante : clés cochées par liste présente, état de la case de désinstallation
function Get-SetupPageSelection {
    $controls  = $script:InstallState.Controls
    $selection = @{}
    foreach ($name in @('AppList', 'LocaleList', 'CompanionList')) {
        if ($null -ne $controls[$name]) { $selection[$name] = @(Get-SetupCheckedKeys $controls[$name]) }
    }
    if ($null -ne $controls.IconSetList) { $selection.IconSetList = @(Get-SetupSelectedIconSetName $controls.IconSetList) }
    if ($null -ne $controls.UninstallBox) { $selection.UninstallOthers = [bool]$controls.UninstallBox.Checked }
    if ($null -ne $controls.LegacyLaunchBox) { $selection.LegacyLaunchBox = @([string]$controls.LegacyLaunchBox.Checked) }
    if ($null -ne $controls.RiotPathBoxes) { $selection.RiotPaths = Get-SetupRiotPathInputs }
    return $selection
}

# Chemins Riot tels que saisis sur la page, sous les clés de Get-LaunchRiotPaths
function Get-SetupRiotPathInputs {
    $boxes  = $script:InstallState.Controls.RiotPathBoxes
    $inputs = @{}
    foreach ($key in @($boxes.Keys)) { $inputs[$key] = [string]$boxes[$key].Text }
    return $inputs
}

# Chemin à afficher : la saisie en attente (redessin) prime sur la valeur de config.json
function Get-SetupPendingRiotPath([string]$Key, [string]$Default) {
    $pending = $script:InstallState.PendingSelection
    if ($null -ne $pending -and $pending.ContainsKey('RiotPaths') -and $pending.RiotPaths.ContainsKey($Key)) { return [string]$pending.RiotPaths[$Key] }
    return $Default
}

# Présélection d'une liste : la saisie en attente (redessin) prime sur le calcul par défaut
function Get-SetupPreselection([string]$ListName, [string[]]$Default) {
    $pending = $script:InstallState.PendingSelection
    if ($null -ne $pending -and $pending.ContainsKey($ListName)) { return @($pending[$ListName]) }
    return @($Default)
}

function Get-SetupPendingUninstallOthers([bool]$Default = $false) {
    $pending = $script:InstallState.PendingSelection
    if ($null -ne $pending -and $pending.ContainsKey('UninstallOthers')) { return [bool]$pending.UninstallOthers }
    return $Default
}

# ---------------------------------------------------------------- Page 1 : détection

function Initialize-SetupDetection {
    $state = $script:InstallState
    if ($null -eq $state.Config) {
        $detection = Initialize-SetupConfig $SetupConfigPath
        $state.Config        = $detection.Config
        $state.ConfigCreated = $detection.Created
    }
    # Recalculé à chaque affichage : les libellés suivent la langue active
    $state.DetectionItems = @(Get-DetectionItems $state.Config)
}

# Géométrie d'une ligne de la page : libellé, encadré de 3 lignes pour un chemin (celui du yaml sous ProgramData
# en occupe trois à cette largeur) ou d'une ligne pour une valeur en lecture seule, statut sur 3 lignes (la raison
# d'un manque cite le fichier attendu et son dossier habituel — celui du yaml est long)
$SetupDetectionRow = @{ FieldTop = 22; FieldHeight = 56; ReadOnlyFieldHeight = 30; StatusTop = 80; StatusHeight = 56; Gap = 6 }

# Libellé, encadré en lecture seule et statut éventuel ; retourne les contrôles et la hauteur occupée
function New-DetectionItemControls($Item, [int]$Top, [int]$Width) {
    $row      = $SetupDetectionRow
    $controls = @(
        (New-ThemedLabel $Item.Label 0 $Top $Width 22 'Gold' 10 'Bold')
        (New-ThemedField $Item.Value 0 ($Top + $row.FieldTop) $Width $row.ReadOnlyFieldHeight)
    )
    $height = $row.FieldTop + $row.ReadOnlyFieldHeight
    if ($Item.Status) { $controls += New-ThemedLabel $Item.Status 0 ($Top + $row.StatusTop) $Width $row.StatusHeight $Item.Color; $height = $row.StatusTop + $row.StatusHeight }
    return @{ Controls = $controls; Inputs = @(); Height = $height + $row.Gap }
}

# Libellé, champ modifiable + « Parcourir… », statut recalculé à chaque frappe ; les contrôles sont retenus par clé
function New-RiotPathItemControls($Item, [int]$Top, [int]$Width) {
    $row      = $SetupDetectionRow
    $controls = $script:InstallState.Controls
    $buttonWidth = $script:InstallState.Layout.ButtonWidth
    $box    = New-ThemedInputField (Get-SetupPendingRiotPath $Item.Key $Item.Value) 0 ($Top + $row.FieldTop) ($Width - $buttonWidth - 10) $row.FieldHeight
    $browse = New-ThemedButton (Get-Text 'setup.detect.browse') ($Width - $buttonWidth) ($Top + $row.FieldTop) $buttonWidth $row.FieldHeight
    $status = New-ThemedLabel '' 0 ($Top + $row.StatusTop) $Width $row.StatusHeight $Item.Color
    $box.Tag = $Item.Key
    $browse.Tag = $Item.Key
    $controls.RiotPathBoxes[$Item.Key]    = $box
    $controls.RiotPathStatuses[$Item.Key] = $status
    Update-SetupRiotPathStatus $Item.Key
    $box.Add_TextChanged({ param($sender, $e) Invoke-SetupSafely { Update-SetupRiotPathStatus $sender.Tag } })
    $browse.Add_Click({ param($sender, $e) Invoke-SetupSafely { Invoke-SetupBrowseRiotPath $sender.Tag } })
    return @{
        Controls = @((New-ThemedLabel $Item.Label 0 $Top $Width 22 'Gold' 10 'Bold'), $box, $browse, $status)
        Inputs   = @($box, $browse)
        Height   = $row.StatusTop + $row.StatusHeight + $row.Gap
    }
}

# Le statut suit la saisie : « Trouvé » dès que le chemin mène à un fichier, la raison du manque sinon
function Update-SetupRiotPathStatus([string]$Key) {
    $state  = $script:InstallState
    $item   = Find-DetectionItem $state.DetectionItems $Key
    $label  = $state.Controls.RiotPathStatuses[$Key]
    if ($null -eq $item -or $null -eq $label) { return }
    $status = Get-DetectionPathStatus $state.Controls.RiotPathBoxes[$Key].Text $item.MissingReason
    $label.Text      = $status.Text
    $label.ForeColor = Get-ThemeColor $status.Color
}

# Boîte de sélection de fichier ; rend le chemin choisi, $null si l'utilisateur annule
function Show-SetupFileDialog([string]$CurrentPath, [string]$Filter, [string]$Title) {
    $dialog                  = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title            = $Title
    $dialog.Filter           = $Filter
    $dialog.CheckFileExists  = $true
    $dialog.InitialDirectory = Get-SetupBrowseStartFolder $CurrentPath
    $owner  = $script:InstallState.Form
    $result = if ($null -ne $owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.FileName
}

function Invoke-SetupBrowseRiotPath([string]$Key) {
    $state  = $script:InstallState
    $item   = Find-DetectionItem $state.DetectionItems $Key
    $box    = $state.Controls.RiotPathBoxes[$Key]
    $chosen = Show-SetupFileDialog (ConvertTo-LaunchPathValue $box.Text) $item.FileFilter $item.Label
    if ($chosen) { $box.Text = $chosen }
}

function Show-SetupDetectPage {
    Initialize-SetupDetection
    $state    = $script:InstallState
    $width    = $state.Layout.ContentWidth
    $state.Controls.RiotPathBoxes    = @{}
    $state.Controls.RiotPathStatuses = @{}
    $controls = @(
        (New-ThemedLabel (Get-Text 'setup.detect.intro') 0 0 $width 48 'Muted')
        (New-ThemedLabel (Get-ConfigStatusText $state.ConfigCreated $SetupConfigPath) 0 50 $width 22 'Accent')
    )
    $top    = 78
    $inputs = @()
    foreach ($item in $state.DetectionItems) {
        $built = if (Test-DetectionItemEditable $item) { New-RiotPathItemControls $item $top $width } else { New-DetectionItemControls $item $top $width }
        $controls += $built.Controls
        $inputs   += @($built.Inputs)
        $top      += $built.Height
    }
    $state.Controls.Inputs = $inputs
    Add-SetupContent $controls
}

# Chemins enregistrés seulement s'ils ont changé ; un chemin introuvable n'empêche pas d'avancer, le résumé final le rappelle
function Invoke-SetupDetectStep {
    $state = $script:InstallState
    if ($null -eq $state.Controls.RiotPathBoxes) { return $true }
    Save-LaunchRiotPaths $state.Config $SetupConfigPath (Get-SetupRiotPathInputs) | Out-Null
    return $true
}

# ---------------------------------------------------------------- Page 2 : applis compagnon

function Get-SetupCompanionChoice([int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    $controls = $script:InstallState.Controls
    return @{
        SelectedIds     = @(Get-SetupCheckedKeys $controls.AppList $PendingIndex $PendingChecked)
        UninstallOthers = [bool]$controls.UninstallBox.Checked
    }
}

function Update-SetupCompanionSummary([int]$PendingIndex = -1, [bool]$PendingChecked = $false) {
    $state   = $script:InstallState
    $actions = Get-CompanionActions $state.Catalog $state.Installed (Get-SetupCompanionChoice $PendingIndex $PendingChecked)
    $state.Controls.Log.Text = Format-CompanionActions $actions
}

function New-SetupAppsControls {
    $state    = $script:InstallState
    $controls = $state.Controls
    $width    = $state.Layout.ContentWidth
    $items    = @(Get-CompanionListItems $state.Catalog $state.Installed)
    $controls.AppList      = New-SetupCheckedList $items (Get-SetupPreselection 'AppList' (Get-PreselectedCompanionIds $state.Catalog $state.Installed $state.Config)) 0 50 $width (24 * [Math]::Max(1, $items.Count) + 8)
    $checkTop              = 50 + $controls.AppList.Height + 10
    $controls.UninstallBox = New-ThemedCheckBox (Get-Text 'companion.uninstallOthers') 0 $checkTop $width
    $controls.UninstallBox.Checked = Get-SetupPendingUninstallOthers
    $controls.Log          = New-ThemedLog 0 ($checkTop + 62) $width ($state.Layout.ContentHeight - $checkTop - 62)
    $controls.Inputs       = @($controls.AppList, $controls.UninstallBox)
    $controls.AppList.Add_ItemCheck({ param($sender, $e) Invoke-SetupSafely { Update-SetupCompanionSummary $e.Index ($e.NewValue -eq 'Checked') } })
    $controls.UninstallBox.Add_CheckedChanged({ Invoke-SetupSafely { Update-SetupCompanionSummary } })
    return @(
        (New-ThemedLabel (Get-Text 'companion.hint') 0 0 $width 44 'Muted')
        $controls.AppList
        $controls.UninstallBox
        (New-ThemedLabel (Get-Text 'companion.plannedActions') 0 ($checkTop + 36) $width 22 'Gold' 10 'Bold')
        $controls.Log
    )
}

function Show-SetupAppsPage {
    $state = $script:InstallState
    $state.Catalog   = @(Read-CompanionCatalog $SetupCatalogPath)
    $state.Installed = @(Get-InstalledCompanionApps $state.Catalog)
    Add-SetupContent (New-SetupAppsControls)
    Update-SetupCompanionSummary
}

# Journal : étapes (hook OnStep), avertissements du moteur, puis bilan ; navigation gelée pendant l'exécution
function Invoke-SetupCompanionActions($Actions) {
    Set-SetupBusy $true
    try {
        Write-SetupLog ''
        Write-SetupLog (Get-Text 'setup.apps.applying')
        $result = Invoke-SetupLogged { Invoke-CompanionActions $Actions }
    }
    finally { Set-SetupBusy $false }
    foreach ($line in Get-CompanionOutcomeLines $result) { Write-SetupLog $line }
    return $result
}

# Rend vrai si l'on peut passer à l'étape suivante ; une désinstallation échouée laisse la page affichée, config.json intact
function Invoke-SetupAppsStep {
    $state   = $script:InstallState
    $actions = Get-CompanionActions $state.Catalog $state.Installed (Get-SetupCompanionChoice)
    if (Test-CompanionActionsPending $actions) {
        $result = Invoke-SetupCompanionActions $actions
        if (@($result.UninstallFailed).Count -gt 0) { return $false }
    }
    Write-CompanionConfig $state.Config $SetupConfigPath $actions.Selected | Out-Null
    $state.Installed = @(Get-InstalledCompanionApps $state.Catalog)
    return $true
}

# ---------------------------------------------------------------- Page 3 : raccourcis

function New-SetupShortcutsControls {
    $state    = $script:InstallState
    $controls = $state.Controls
    $layout   = $state.Layout
    $companionApps = @($state.Config.companionApps)
    $columnWidth   = [int](($layout.ContentWidth - 20) / 2)
    $rightColumn   = $columnWidth + 20
    $companionRows = [Math]::Max(1, $companionApps.Count)
    $companionHeight = [Math]::Min(110, 24 * $companionRows + 8)
    $iconSetsTop     = 72 + $companionHeight + 12
    $previewSize     = 64
    $controls.LocaleList    = New-SetupCheckedList (Get-LocaleListItems $state.Locales) (Get-SetupPreselection 'LocaleList' (Get-PreselectedCodes $state.Locales $state.ExistingShortcuts)) 0 72 $columnWidth 230
    $controls.CompanionList = New-SetupCheckedList (Get-ShortcutCompanionListItems $companionApps) (Get-SetupPreselection 'CompanionList' (Get-PreselectedShortcutCompanionIds $companionApps $state.ExistingShortcuts)) $rightColumn 72 $columnWidth $companionHeight
    $controls.IconSetList   = New-SetupIconSetList $state.IconSets (Get-SetupPreselectedIconSetName $state) $rightColumn ($iconSetsTop + 24) ($columnWidth - $previewSize - 12) $previewSize
    $controls.IconSetPreview = New-ThemedPicture ($rightColumn + $columnWidth - $previewSize) ($iconSetsTop + 24) $previewSize
    # Pleine largeur sous les deux colonnes : le libellé dit quand cocher la case, et cette explication ne tient
    # pas dans une demi-colonne — la tronquer priverait la case de ce qui la rend utilisable
    $legacyTop      = 306
    $logTop         = $legacyTop + 34
    $controls.LegacyLaunchBox = New-SetupLegacyLaunchBox $state 0 $legacyTop $layout.ContentWidth
    $controls.Log           = New-ThemedLog 0 $logTop $layout.ContentWidth ($layout.ContentHeight - $logTop)
    $controls.Inputs        = @($controls.LocaleList, $controls.CompanionList, $controls.IconSetList)
    $controls.IconSetList.Add_SelectedIndexChanged({ Invoke-SetupSafely { Update-SetupIconSetPreview } })
    Update-SetupIconSetPreview
    return @(
        (New-ThemedLabel (Get-Text 'setup.shortcuts.intro' $Destination) 0 0 $layout.ContentWidth 44 'Muted')
        (New-ThemedLabel (Get-Text 'shortcuts.languages') 0 48 $columnWidth 22 'Gold' 10 'Bold')
        (New-ThemedLabel (Get-Text 'setup.shortcuts.companions') $rightColumn 48 $columnWidth 22 'Gold' 10 'Bold')
        (New-ThemedLabel (Get-Text 'setup.shortcuts.iconSet') $rightColumn $iconSetsTop $columnWidth 22 'Gold' 10 'Bold')
        $controls.LocaleList
        $controls.CompanionList
        $controls.IconSetList
        $controls.IconSetPreview
        $controls.LegacyLaunchBox
        $controls.Log
    )
}

# Case décochée par défaut : le lancement direct est le comportement normal, la case est le recours quand il
# ne fonctionne pas. Libellée par le symptôme, pour être actionnable sans connaître la mécanique.
function New-SetupLegacyLaunchBox($State, [int]$Left, [int]$Top, [int]$Width) {
    $box = New-ThemedCheckBox (Get-Text 'setup.shortcuts.legacyLaunch') $Left $Top $Width
    # @() obligatoire : un retour à un seul élément se déroule en chaîne, et $pending[0] rendrait un caractère
    $pending = @(Get-SetupPreselection 'LegacyLaunchBox' @())
    if ($pending.Count -gt 0) {
        $box.Checked = [bool]($pending[0] -eq 'True')
    } else {
        $box.Checked = -not (Get-LaunchUseLocalApi $State.Config)
    }
    return $box
}

# Liste des jeux, le jeu présélectionné sélectionné ; les clés (noms de dossier) dans Tag comme les listes à cocher
function New-SetupIconSetList([object[]]$Sets, [string]$Preselected, [int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $list = New-ThemedListBox $Left $Top $Width $Height
    $items = @(Get-IconSetListItems $Sets)
    foreach ($item in $items) { $list.Items.Add($item.Label) | Out-Null }
    $list.Tag = [string[]]@($items | ForEach-Object { $_.Key })
    $index = [Array]::IndexOf($list.Tag, $Preselected)
    if ($index -ge 0) { $list.SelectedIndex = $index }
    return $list
}

# Jeu présélectionné : saisie en attente (redessin) sinon config.json / défaut
function Get-SetupPreselectedIconSetName($State) {
    $pending = @(Get-SetupPreselection 'IconSetList' @())
    if ($pending.Count -gt 0) { return [string]$pending[0] }
    return Get-PreselectedIconSetName $State.Config $State.IconSets
}

function Get-SetupSelectedIconSetName($List) {
    if ($null -eq $List -or $List.SelectedIndex -lt 0) { return '' }
    return $List.Tag[$List.SelectedIndex]
}

# Aperçu = hex-launcher.ico du jeu sélectionné ; l'image précédente est libérée
function Update-SetupIconSetPreview {
    $controls = $script:InstallState.Controls
    $set      = Find-IconSet $script:InstallState.IconSets (Get-SetupSelectedIconSetName $controls.IconSetList)
    $previous = $controls.IconSetPreview.Image
    $controls.IconSetPreview.Image = New-IconSetPreviewImage $set $controls.IconSetPreview.Width
    if ($previous) { $previous.Dispose() }
}

function Show-SetupShortcutsPage {
    $state = $script:InstallState
    $state.Locales           = @(Read-LocaleCatalog $localesPath)
    $state.ExistingShortcuts = @(Get-ExistingLaunchShortcuts $Destination)
    $state.IconSets          = @(Get-IconSets $icoRoot)
    Add-SetupContent (New-SetupShortcutsControls)
}

function Get-SetupShortcutSelection {
    $controls = $script:InstallState.Controls
    return @{
        Codes        = @(Get-SetupCheckedKeys $controls.LocaleList)
        CompanionIds = @(Get-SetupCheckedKeys $controls.CompanionList)
        IconSet      = Get-SetupSelectedIconSetName $controls.IconSetList
        UseLocalApi  = -not [bool]$controls.LegacyLaunchBox.Checked
    }
}

function New-SetupShortcuts([object[]]$Combinations) {
    $created = foreach ($combination in $Combinations) {
        $path = Invoke-SetupLogged { New-LaunchShortcutWithFallback $combination }
        Write-SetupLog (Get-Text 'shortcuts.created' $path)
        $path
    }
    return @($created | Where-Object { $_ })
}

# Rend vrai si des raccourcis ont été créés ; sans langue cochée, on reste sur la page
function Invoke-SetupShortcutsStep {
    $state     = $script:InstallState
    $selection = Get-SetupShortcutSelection
    if ($selection.Codes.Count -eq 0) {
        Write-SetupLog (Get-Text 'setup.shortcuts.noLanguage')
        return $false
    }
    $iconSet = Select-IconSetForConfig $state.Config $SetupConfigPath $selection.IconSet
    if ($iconSet) { Write-SetupLog (Get-Text 'setup.shortcuts.iconSetChosen' $iconSet.Name) }
    if ($null -ne $selection.UseLocalApi) {
        Save-LaunchUseLocalApi $state.Config $SetupConfigPath ([bool]$selection.UseLocalApi) | Out-Null
        Write-SetupLog (Get-Text $(if ($selection.UseLocalApi) { 'setup.shortcuts.directLaunchChosen' } else { 'setup.shortcuts.legacyLaunchChosen' }))
    }
    $combinations = Get-ShortcutCombinations $selection.Codes (Resolve-ShortcutCompanions $state.Config $selection.CompanionIds)
    $state.ShortcutPaths = @(New-SetupShortcuts $combinations)
    foreach ($line in @(Remove-ObsoleteShortcuts $state.ExistingShortcuts $combinations)) { Write-SetupLog $line }
    $state.SetupShortcutPath = New-SetupConfigurationShortcut
    return $true
}

# Le raccourci vers setup.bat : toujours recréé (il suit un déplacement du dossier) ; un échec ne bloque pas l'étape
function New-SetupConfigurationShortcut {
    try {
        $path = Invoke-SetupLogged { New-SetupShortcutWithFallback }
        Write-SetupLog (Get-Text 'shortcuts.created' $path)
        return [string]$path
    } catch {
        Write-SetupLog (Get-Text 'common.warning' $_.Exception.Message)
        return ''
    }
}

# ---------------------------------------------------------------- Page 4 : terminé

function Show-SetupDonePage {
    $state = $script:InstallState
    $width = $state.Layout.ContentWidth
    $state.ExitCode = 0
    $controls = @(New-ThemedLabel (Get-Text 'setup.done.title') 0 0 $width 26 'Accent' 11 'Bold')
    $top = 44
    foreach ($line in Get-CompletionSummaryLines $state.Config $SetupConfigPath $state.ShortcutPaths $state.SetupShortcutPath) {
        $controls += New-ThemedLabel $line 0 $top $width 46 'Cream'
        $top += 52
    }
    foreach ($line in Get-MissingRiotPathLines $state.Config) {
        $controls += New-ThemedLabel $line 0 $top $width 46 'Danger'
        $top += 52
    }
    $controls += New-ThemedLabel (Get-Text 'setup.done.hint') 0 ($top + 8) $width 60 'Muted'
    Add-SetupContent $controls
}

# ---------------------------------------------------------------- Navigation

function Show-SetupPage([string]$StepId) {
    $state = $script:InstallState
    $state.StepId = $StepId
    foreach ($name in $SetupPageControlNames) { $state.Controls[$name] = $null }
    $state.Controls.Inputs = @()
    Clear-SetupContent
    Update-SetupSidebar $StepId
    Set-SetupPageTitle (Get-SetupPageTitle $StepId)
    try {
        switch ($StepId) {
            'detect'    { Show-SetupDetectPage }
            'apps'      { Show-SetupAppsPage }
            'shortcuts' { Show-SetupShortcutsPage }
            'done'      { Show-SetupDonePage }
        }
    }
    finally { $state.PendingSelection = $null }
    Update-SetupNavigation
}

# Change la langue active et redessine la page courante sans perdre la saisie ; rend vrai si la langue a changé.
# Ignoré pendant une action longue (le journal en cours resterait dans l'ancienne langue) ou pour une langue inconnue.
function Set-SetupLanguage([string]$Language) {
    $state = $script:InstallState
    if ($state.IsBusy -or -not (Test-UiLanguageSupported $Language) -or $Language -eq (Get-UiLanguage)) { return $false }
    $state.PendingSelection = Get-SetupPageSelection
    Initialize-Translation $Language | Out-Null
    if ($null -ne $state.Form) { $state.Form.Text = Get-SetupWindowTitle }
    Sync-SetupLanguageBox $Language
    Show-SetupPage $state.StepId
    return $true
}

# Aligne le sélecteur sur la langue active (bascule par programme) ; sans effet s'il l'affiche déjà
function Sync-SetupLanguageBox([string]$Language) {
    $box = $script:InstallState.Controls.LanguageBox
    if ($null -eq $box -or (Get-ThemedComboBoxKey $box) -eq $Language) { return }
    $box.SelectedIndex = [array]::IndexOf($box.Tag, $Language)
}

# Action d'une page au clic sur Suivant/Appliquer ; rend vrai si l'on peut avancer
function Invoke-SetupStepAction([string]$StepId) {
    switch ($StepId) {
        'detect'    { return Invoke-SetupDetectStep }
        'apps'      { return Invoke-SetupAppsStep }
        'shortcuts' { return Invoke-SetupShortcutsStep }
    }
    return $true
}

function Invoke-SetupNext {
    $state = $script:InstallState
    if ($state.StepId -eq 'done') { $state.Form.Close(); return }
    if (-not (Invoke-SetupStepAction $state.StepId)) { return }
    Show-SetupPage (Get-NextInstallStep $state.StepId)
}

function Invoke-SetupBack {
    $stepId = $script:InstallState.StepId
    if (-not (Test-CanGoBack $stepId)) { return }
    Show-SetupPage (Get-PreviousInstallStep $stepId)
}

function Invoke-SetupCancel {
    $script:InstallState.ExitCode = 2
    $script:InstallState.Form.Close()
}

# Rend le code de sortie du script
function Start-SetupWizard {
    if (Test-CompanionElevated) {
        Show-SetupErrorBox "$(Get-Text 'common.notElevated')`r`n`r`n$(Get-Text 'setup.error.elevatedHint')"
        return 1
    }
    Register-SetupCompanionUi
    $form = New-SetupWindow
    Show-SetupPage 'detect'
    [void]$form.ShowDialog()
    $form.Dispose()
    return $script:InstallState.ExitCode
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    try   { [int]$exitCode = Start-SetupWizard; exit $exitCode }
    catch { Show-SetupErrorBox (Get-Text 'setup.error.failed' $_.Exception.Message); exit 1 }
}
