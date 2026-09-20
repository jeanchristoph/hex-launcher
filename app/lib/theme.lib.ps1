<#
.SYNOPSIS
    Thème visuel League of Legends partagé : palette et fabriques de contrôles WinForms.

.DESCRIPTION
    Chargé par dot-sourcing depuis splash.lib.ps1 et setup.ps1 :
        . (Join-Path $PSScriptRoot 'lib\theme.lib.ps1')

    Palette inspirée du client LoL : fond nuit, or pour les titres et liserés, crème pour le texte,
    gris pour le secondaire, cyan pour ce qui est accompli.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$LolTheme = @{
    Background  = '#0A0E14'
    Panel       = '#0F1620'
    Border      = '#463714'
    Gold        = '#C8AA6E'
    GoldDark    = '#785A28'
    Cream       = '#F0E6D2'
    Muted       = '#A09B8C'
    Accent      = '#0AC8B9'
    Danger      = '#E84057'
}

function Get-ThemeColor([string]$Name) {
    return [System.Drawing.ColorTranslator]::FromHtml($LolTheme[$Name])
}

function New-ThemeFont([single]$Size = 10, [string]$Style = 'Regular', [string]$Family = 'Segoe UI') {
    return New-Object System.Drawing.Font($Family, $Size, [System.Drawing.FontStyle]::$Style)
}

. (Join-Path $PSScriptRoot 'icon-set.lib.ps1')

# Icône des fenêtres : hex-launcher.ico du jeu d'icônes par défaut (chemin attendu même s'il manque : l'appelant vérifie)
function Get-ThemeIconPath {
    $icoRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'ico'
    return Get-IconSetFilePath (Get-IconSetFolderOrDefault (Get-DefaultIconSet @(Get-IconSets $icoRoot)) $icoRoot) $IconSetBaseIcon
}

function New-ThemedForm([string]$Title, [int]$Width, [int]$Height) {
    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = $Title
    $form.Size            = New-Object System.Drawing.Size($Width, $Height)
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = Get-ThemeColor 'Background'
    $form.ForeColor       = Get-ThemeColor 'Cream'
    $form.Font            = New-ThemeFont 10
    $icon = Get-ThemeIconPath
    if (Test-Path $icon) { $form.Icon = New-Object System.Drawing.Icon($icon) }
    return $form
}

function New-ThemedLabel([string]$Text, [int]$Left, [int]$Top, [int]$Width, [int]$Height, [string]$Color = 'Cream', [single]$Size = 10, [string]$Style = 'Regular') {
    $label           = New-Object System.Windows.Forms.Label
    $label.Text      = $Text
    $label.Location  = New-Object System.Drawing.Point($Left, $Top)
    $label.Size      = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = Get-ThemeColor $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.Font      = New-ThemeFont $Size $Style
    return $label
}

# Titre de section : or, gras, capitales comme le splash
function New-ThemedTitle([string]$Text, [int]$Left, [int]$Top, [int]$Width) {
    return New-ThemedLabel $Text.ToUpperInvariant() $Left $Top $Width 34 'Gold' 15 'Bold'
}

# Bouton plat à liseré or ; Primary = fond or sombre (action principale)
function New-ThemedButton([string]$Text, [int]$Left, [int]$Top, [int]$Width = 110, [int]$Height = 34, [bool]$Primary = $false) {
    $button                            = New-Object System.Windows.Forms.Button
    $button.Text                       = $Text
    $button.Location                   = New-Object System.Drawing.Point($Left, $Top)
    $button.Size                       = New-Object System.Drawing.Size($Width, $Height)
    $button.FlatStyle                  = 'Flat'
    $button.FlatAppearance.BorderColor = Get-ThemeColor 'Gold'
    $button.FlatAppearance.BorderSize  = 1
    $button.FlatAppearance.MouseOverBackColor = Get-ThemeColor 'GoldDark'
    $button.BackColor                  = if ($Primary) { Get-ThemeColor 'GoldDark' } else { Get-ThemeColor 'Panel' }
    $button.ForeColor                  = if ($Primary) { Get-ThemeColor 'Cream' } else { Get-ThemeColor 'Gold' }
    $button.Font                       = New-ThemeFont 10 'Bold'
    $button.Cursor                     = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function New-ThemedPanel([int]$Left, [int]$Top, [int]$Width, [int]$Height, [string]$Color = 'Panel') {
    $panel           = New-Object System.Windows.Forms.Panel
    $panel.Location  = New-Object System.Drawing.Point($Left, $Top)
    $panel.Size      = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = Get-ThemeColor $Color
    return $panel
}

function New-ThemedCheckedListBox([int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $list              = New-Object System.Windows.Forms.CheckedListBox
    $list.Location     = New-Object System.Drawing.Point($Left, $Top)
    $list.Size         = New-Object System.Drawing.Size($Width, $Height)
    $list.BackColor    = Get-ThemeColor 'Background'
    $list.ForeColor    = Get-ThemeColor 'Cream'
    $list.BorderStyle  = 'FixedSingle'
    $list.CheckOnClick = $true
    $list.Font         = New-ThemeFont 10
    return $list
}

# Liste à choix unique, même habillage que la liste à cocher
function New-ThemedListBox([int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $list             = New-Object System.Windows.Forms.ListBox
    $list.Location    = New-Object System.Drawing.Point($Left, $Top)
    $list.Size        = New-Object System.Drawing.Size($Width, $Height)
    $list.BackColor   = Get-ThemeColor 'Background'
    $list.ForeColor   = Get-ThemeColor 'Cream'
    $list.BorderStyle = 'FixedSingle'
    $list.Font        = New-ThemeFont 10
    return $list
}

# Aperçu d'image carré, centré dans son cadre
function New-ThemedPicture([int]$Left, [int]$Top, [int]$Size) {
    $picture           = New-Object System.Windows.Forms.PictureBox
    $picture.Location  = New-Object System.Drawing.Point($Left, $Top)
    $picture.Size      = New-Object System.Drawing.Size($Size, $Size)
    $picture.SizeMode  = 'CenterImage'
    $picture.BackColor = Get-ThemeColor 'Background'
    return $picture
}

# Liste déroulante fermée : $Items = objets Key/Label, les clés sont rangées dans Tag (même indice que les libellés)
function New-ThemedComboBox([object[]]$Items, [string]$SelectedKey, [int]$Left, [int]$Top, [int]$Width) {
    $combo               = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.FlatStyle     = 'Flat'
    $combo.Location      = New-Object System.Drawing.Point($Left, $Top)
    $combo.Size          = New-Object System.Drawing.Size($Width, 28)
    $combo.BackColor     = Get-ThemeColor 'Panel'
    $combo.ForeColor     = Get-ThemeColor 'Cream'
    $combo.Font          = New-ThemeFont 10
    foreach ($item in $Items) { [void]$combo.Items.Add($item.Label) }
    $combo.Tag           = [string[]]@($Items | ForEach-Object { $_.Key })
    $combo.SelectedIndex = [array]::IndexOf($combo.Tag, $SelectedKey)
    return $combo
}

# Clé de l'élément sélectionné, $null si aucun
function Get-ThemedComboBoxKey($Combo) {
    if ($Combo.SelectedIndex -lt 0) { return $null }
    return $Combo.Tag[$Combo.SelectedIndex]
}

# Carré natif de Windows : blanc quand la case est décochée, donc bien détaché du fond nuit. Le style Flat,
# essayé d'abord, rendait ce carré bleu terne (R95 G126 B175 mesurés) — on croyait la case cochée.
function New-ThemedCheckBox([string]$Text, [int]$Left, [int]$Top, [int]$Width) {
    $box                                      = New-Object System.Windows.Forms.CheckBox
    $box.Text                                 = $Text
    $box.Location                             = New-Object System.Drawing.Point($Left, $Top)
    $box.Size                                 = New-Object System.Drawing.Size($Width, 26)
    $box.ForeColor                            = Get-ThemeColor 'Cream'
    $box.BackColor                            = Get-ThemeColor 'Background'
    $box.FlatStyle                            = 'Standard'
    return $box
}

# Champ encadré en lecture seule (chemin, valeur) : retour à la ligne géré, texte sélectionnable pour copie
function New-ThemedField([string]$Text, [int]$Left, [int]$Top, [int]$Width, [int]$Height = 48) {
    $field             = New-Object System.Windows.Forms.TextBox
    $field.Text        = $Text
    $field.Location    = New-Object System.Drawing.Point($Left, $Top)
    $field.Size        = New-Object System.Drawing.Size($Width, $Height)
    $field.Multiline   = $true
    $field.ReadOnly    = $true
    $field.WordWrap    = $true
    $field.BackColor   = Get-ThemeColor 'Panel'
    $field.ForeColor   = Get-ThemeColor 'Cream'
    $field.BorderStyle = 'FixedSingle'
    $field.Font        = New-ThemeFont 9.5 'Regular' 'Consolas'
    return $field
}

# Journal en lecture seule (progression, résumé)
function New-ThemedLog([int]$Left, [int]$Top, [int]$Width, [int]$Height) {
    $log             = New-Object System.Windows.Forms.TextBox
    $log.Location    = New-Object System.Drawing.Point($Left, $Top)
    $log.Size        = New-Object System.Drawing.Size($Width, $Height)
    $log.Multiline   = $true
    $log.ReadOnly    = $true
    $log.ScrollBars  = 'Vertical'
    $log.BackColor   = Get-ThemeColor 'Background'
    $log.ForeColor   = Get-ThemeColor 'Muted'
    $log.BorderStyle = 'FixedSingle'
    $log.Font        = New-ThemeFont 9 'Regular' 'Consolas'
    return $log
}

function New-ThemedProgressBar([int]$Left, [int]$Top, [int]$Width) {
    $progress                       = New-Object System.Windows.Forms.ProgressBar
    $progress.Location              = New-Object System.Drawing.Point($Left, $Top)
    $progress.Size                  = New-Object System.Drawing.Size($Width, 6)
    $progress.Style                 = 'Marquee'
    $progress.MarqueeAnimationSpeed = 25
    $progress.Visible               = $false
    return $progress
}

# Ligne de séparation or sombre
function New-ThemedRule([int]$Left, [int]$Top, [int]$Width) {
    return New-ThemedPanel $Left $Top $Width 1 'Border'
}
