<#
.SYNOPSIS
    Splash partagé : fenêtre sombre sans bordure, titre doré, sous-titre, filet doré, ligne de statut.

.DESCRIPTION
    Chargé par dot-sourcing depuis launch-lol.ps1 (lancement du jeu) et manage-companion-app.ps1
    (installation de l'appli compagnon) :
        . (Join-Path $PSScriptRoot 'lib\splash.lib.ps1')

    Toute attente pendant que le splash est affiché doit pomper les messages Windows
    (Wait-WithAnimation, ou Invoke-SplashTick depuis un callback) : un Start-Sleep bloquant fige la barre.

    Un bouton d'action facultatif (Add-SplashAction) peut être posé en bas, caché : l'appelant décide quand il a
    un sens (Show-SplashAction) et ce que fait le clic. Le splash ne sait rien de ce qu'il déclenche.
    Une croix facultative (Add-SplashCloseButton) peut être posée en haut à droite, visible d'emblée — le splash
    n'a pas de barre de titre, c'est sa seule prise pour l'utilisateur qui veut s'arrêter là.
#>

. (Join-Path $PSScriptRoot 'theme.lib.ps1')

function New-SplashLabel([string]$Text, [System.Drawing.Font]$Font, [string]$ColorName, [string]$Dock, [int]$Height) {
    $label           = New-Object System.Windows.Forms.Label
    $label.Text      = $Text
    $label.Font      = $Font
    $label.ForeColor = Get-ThemeColor $ColorName
    $label.AutoSize  = $false
    $label.TextAlign = 'MiddleCenter'
    $label.Dock      = $Dock
    if ($Height -gt 0) { $label.Height = $Height }
    return $label
}

# Filet doré fixe entre le sous-titre et le statut : une barre marquee y avait été essayée, son défilement
# donnait l'impression d'un affichage cassé (retour utilisateur du 2026-09-20)
function New-SplashRule {
    $rule           = New-ThemedPanel 0 0 0 2 'Gold'
    $rule.Dock      = 'Top'
    $rule.Margin    = New-Object System.Windows.Forms.Padding(0)
    return $rule
}

# Bande du titre : 60 px. Avec un avertissement, le titre en prend le haut et la ligne jaune s'y colle dessous —
# la hauteur du splash ne change pas
$SplashTitleBandHeight = 60
$SplashWarningHeight   = 24

# Titre, sous-titre, filet et ligne de statut, du bas vers le haut : Dock 'Top' empile dans l'ordre inverse d'ajout.
# Les variables locales ne reprennent jamais le nom d'un paramètre : PowerShell ignore la casse, et assigner un Label
# à $Title ([string]) le convertirait en texte — c'est ce qui a privé le splash de son titre jusqu'en 0.2.0.
# La ligne de statut est rangée dans Tag pour qu'Update-SplashStatus la retrouve sans variable globale.
# $Texts = { Title, Subtitle, Warning } — Warning facultatif : ligne jaune sous le titre, absente si vide.
function Add-SplashControls($Form, $Texts) {
    $controls = New-Object Collections.Generic.List[System.Windows.Forms.Control]
    $controls.Add((New-SplashLabel '' (New-ThemeFont 9) 'Muted' 'Fill' 0))
    $controls.Add((New-SplashRule))
    $controls.Add((New-SplashLabel $Texts.Subtitle (New-ThemeFont 12) 'Cream' 'Top' 30))
    if (-not $Texts.Warning) { $controls.Add((New-SplashLabel $Texts.Title (New-ThemeFont 16 'Bold') 'Gold' 'Top' $SplashTitleBandHeight)) }
    else { $controls.AddRange([System.Windows.Forms.Control[]]@(New-SplashTitleWithWarning $Texts)) }
    $Form.Controls.AddRange($controls.ToArray())
    $Form.Tag = $controls[0]
}

# Rend { ligne jaune, titre } dans l'ordre d'ajout de Add-SplashControls : titre ancré en bas de sa part de bande,
# ligne jaune ancrée en haut de la sienne, pour qu'ils se touchent
function New-SplashTitleWithWarning($Texts) {
    $warningLabel = New-SplashLabel $Texts.Warning (New-ThemeFont 11 'Bold') 'Warning' 'Top' $SplashWarningHeight
    $warningLabel.TextAlign = 'TopCenter'
    $titleLabel = New-SplashLabel $Texts.Title (New-ThemeFont 16 'Bold') 'Gold' 'Top' ($SplashTitleBandHeight - $SplashWarningHeight)
    $titleLabel.TextAlign = 'BottomCenter'
    return @($warningLabel, $titleLabel)
}

function New-SplashWindow([string]$Subtitle, [string]$Title = 'LEAGUE OF LEGENDS', [string]$Warning = '') {
    $form                 = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition   = 'CenterScreen'
    $form.Size            = New-Object System.Drawing.Size(420, 170)
    $form.BackColor       = Get-ThemeColor 'Background'
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false

    Add-SplashControls $form ([pscustomobject]@{ Title = $Title; Subtitle = $Subtitle; Warning = $Warning })
    $form.Show()
    Invoke-SplashTick
    return $form
}

function Invoke-SplashTick {
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-SplashStatus($Splash, [string]$Text) {
    if ($null -eq $Splash) { return }
    $Splash.Tag.Text = $Text
    Invoke-SplashTick
}

# Masquer pendant qu'un dialogue tiers (menu Overwolf…) doit rester visible : le splash est TopMost
function Set-SplashVisible($Splash, [bool]$Visible) {
    if ($null -eq $Splash) { return }
    $Splash.Visible = $Visible
    Invoke-SplashTick
}

# Pendant qu'un installeur tiers peut afficher sa propre fenêtre, le splash reste visible mais ne la recouvre plus
function Set-SplashTopMost($Splash, [bool]$TopMost) {
    if ($null -eq $Splash) { return }
    $Splash.TopMost = $TopMost
    Invoke-SplashTick
}

# ---------------------------------------------------------------- Bouton d'action

$SplashActionControlName = 'SplashAction'
$SplashActionHeight      = 34

# Bouton caché à la création, retrouvé par son nom dans les contrôles : le Tag du splash reste la ligne de statut.
# Le Tag du bouton porte l'état demandé (montré ou non) : Control.Visible ne dit que la visibilité effective,
# fausse tant que la fenêtre n'est pas affichée. Le clic est pompé par les ticks de l'attente en cours (DoEvents).
function Add-SplashAction($Splash, [string]$Text, [scriptblock]$OnClick) {
    if ($null -eq $Splash) { return $null }
    $button         = New-ThemedButton $Text 0 0 $Splash.Width $SplashActionHeight
    $button.Name    = $SplashActionControlName
    $button.Dock    = 'Bottom'
    $button.Visible = $false
    $button.Tag     = $false
    $button.Add_Click($OnClick)
    $Splash.Controls.Add($button)
    return $button
}

# Croix en haut à droite : une étiquette, pas un bouton — pas de bordure, pas de fond, juste le signe, doré au survol.
# Posée par-dessus les contrôles ancrés (BringToFront), elle ne bouge pas quand le bouton du bas apparaît
$SplashCloseControlName = 'SplashClose'
$SplashCloseSize        = 22
$SplashCloseMargin      = 6

function Add-SplashCloseButton($Splash, [scriptblock]$OnClick) {
    if ($null -eq $Splash) { return $null }
    $cross           = New-SplashLabel ([string][char]0x2715) (New-ThemeFont 10 'Bold') 'Muted' 'None' $SplashCloseSize
    $cross.Name      = $SplashCloseControlName
    $cross.Width     = $SplashCloseSize
    $cross.Location  = New-Object System.Drawing.Point(($Splash.ClientSize.Width - $SplashCloseSize - $SplashCloseMargin), $SplashCloseMargin)
    $cross.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $cross.Add_MouseEnter({ $this.ForeColor = Get-ThemeColor 'Gold' })
    $cross.Add_MouseLeave({ $this.ForeColor = Get-ThemeColor 'Muted' })
    $cross.Add_Click($OnClick)
    $Splash.Controls.Add($cross)
    $cross.BringToFront()
    return $cross
}

function Get-SplashCloseButton($Splash) {
    if ($null -eq $Splash) { return $null }
    return $Splash.Controls[$SplashCloseControlName]
}

function Get-SplashAction($Splash) {
    if ($null -eq $Splash) { return $null }
    return $Splash.Controls[$SplashActionControlName]
}

function Test-SplashActionShown($Splash) {
    $button = Get-SplashAction $Splash
    return ($null -ne $button) -and [bool]$button.Tag
}

# La fenêtre grandit de la hauteur du bouton : le reste du splash ne bouge pas. Rend vrai si le bouton vient
# d'apparaître — les appels suivants ne font rien, l'appelant peut le demander à chaque tick sans se soucier
function Show-SplashAction($Splash) {
    $button = Get-SplashAction $Splash
    if ($null -eq $button -or $button.Tag) { return $false }
    $Splash.Height += $button.Height
    $button.Tag     = $true
    $button.Visible = $true
    Invoke-SplashTick
    return $true
}

function Hide-SplashAction($Splash) {
    $button = Get-SplashAction $Splash
    if ($null -eq $button -or -not $button.Tag) { return $false }
    $button.Visible = $false
    $button.Tag     = $false
    $Splash.Height -= $button.Height
    Invoke-SplashTick
    return $true
}

function Close-SplashWindow($Splash) {
    if ($null -eq $Splash) { return }
    $Splash.Close()
    $Splash.Dispose()
}

# Un Start-Sleep bloquant figerait la barre : on pompe les messages Windows par petits pas
function Wait-WithAnimation([double]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        Invoke-SplashTick
        Start-Sleep -Milliseconds 50
    }
}
