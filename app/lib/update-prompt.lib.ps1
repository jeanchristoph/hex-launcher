<#
.SYNOPSIS
    Fenêtre « Mise à jour disponible » au thème LoL : Installer / Plus tard, case « Ne plus me demander jusqu'à la
    prochaine version », lien vers les nouveautés.

.DESCRIPTION
    Chargé par dot-sourcing, après i18n.lib.ps1 et Initialize-Translation :
        . (Join-Path $PSScriptRoot 'lib\update-prompt.lib.ps1')

    La case n'a d'effet qu'avec « Plus tard » : choisir « Installer » ne mémorise aucun refus.
#>

. (Join-Path $PSScriptRoot 'theme.lib.ps1')
. (Join-Path $PSScriptRoot 'update.lib.ps1')

$UpdatePromptWidth  = 460
$UpdatePromptHeight = 250

# Choix de l'utilisateur : @{ Install ; SkipVersion }
function Resolve-UpdatePromptChoice([System.Windows.Forms.DialogResult]$Result, [bool]$IsSkipChecked) {
    $isInstall = $Result -eq [System.Windows.Forms.DialogResult]::OK
    return @{ Install = $isInstall; SkipVersion = (-not $isInstall) -and $IsSkipChecked }
}

function New-UpdatePromptLink([string]$PageUrl) {
    $link           = New-Object System.Windows.Forms.LinkLabel
    $link.Text      = Get-Text 'update.releaseNotes'
    $link.Location  = New-Object System.Drawing.Point(24, 92)
    $link.AutoSize  = $true
    $link.LinkColor = Get-ThemeColor 'Gold'
    $link.Font      = New-ThemeFont 9.5
    $link.Add_LinkClicked({ Start-Process $PageUrl }.GetNewClosure())
    return $link
}

# Fenêtre prête à afficher ; la case est rendue dans .Tag pour relire son état après ShowDialog
function New-UpdatePromptForm($Release, [string]$InstalledVersion) {
    $form = New-ThemedForm (Get-Text 'update.title') $UpdatePromptWidth $UpdatePromptHeight
    $form.TopMost = $true
    $skip    = New-ThemedCheckBox (Get-Text 'update.skipVersion') 24 124 400
    $install = New-ThemedButton (Get-Text 'update.install') 186 166 120 34 $true
    $later   = New-ThemedButton (Get-Text 'update.later') 316 166 110 34
    $install.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $later.DialogResult   = [System.Windows.Forms.DialogResult]::Cancel
    $form.AcceptButton = $install
    $form.CancelButton = $later
    $form.Controls.AddRange(@(
        (New-ThemedLabel (Get-Text 'update.message' $Release.Version, $InstalledVersion) 24 20 400 64),
        (New-UpdatePromptLink $Release.PageUrl), $skip, $install, $later))
    $form.Tag = $skip
    return $form
}

function Show-UpdatePrompt($Release, [string]$InstalledVersion) {
    $form = New-UpdatePromptForm $Release $InstalledVersion
    try {
        $result = $form.ShowDialog()
        return Resolve-UpdatePromptChoice $result ([bool]$form.Tag.Checked)
    } finally {
        $form.Dispose()
    }
}

# Pose la question et mémorise le refus s'il est demandé ; rend vrai si l'utilisateur veut installer
function Confirm-UpdateInstall($Release, [string]$InstalledVersion, [string]$StatePath) {
    $choice = Show-UpdatePrompt $Release $InstalledVersion
    if ($choice.SkipVersion) { Save-SkippedVersion $StatePath $Release.Version }
    return $choice.Install
}
