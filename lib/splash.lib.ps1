<#
.SYNOPSIS
    Splash animé partagé : fenêtre sombre sans bordure, titre doré, sous-titre, barre marquee, ligne de statut.

.DESCRIPTION
    Chargé par dot-sourcing depuis launch-lol.ps1 (lancement du jeu) et manage-companion-app.ps1
    (installation de l'appli compagnon) :
        . (Join-Path $PSScriptRoot 'lib\splash.lib.ps1')

    Toute attente pendant que le splash est affiché doit pomper les messages Windows
    (Wait-WithAnimation, ou Invoke-SplashTick depuis un callback) : un Start-Sleep bloquant fige la barre.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SplashColors = @{ Background = '#0A0E14'; Title = '#C8AA6E'; Text = '#FFFFFF'; Status = '#A09B8C' }

function New-SplashLabel([string]$Text, [System.Drawing.Font]$Font, [string]$ColorHex, [string]$Dock, [int]$Height) {
    $label           = New-Object System.Windows.Forms.Label
    $label.Text      = $Text
    $label.Font      = $Font
    $label.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($ColorHex)
    $label.AutoSize  = $false
    $label.TextAlign = 'MiddleCenter'
    $label.Dock      = $Dock
    if ($Height -gt 0) { $label.Height = $Height }
    return $label
}

function New-SplashProgressBar {
    $progress                       = New-Object System.Windows.Forms.ProgressBar
    $progress.Style                 = 'Marquee'
    $progress.MarqueeAnimationSpeed = 25
    $progress.Dock                  = 'Top'
    $progress.Height                = 6
    return $progress
}

# La ligne de statut est rangée dans Tag pour qu'Update-SplashStatus la retrouve sans variable globale
function New-SplashWindow([string]$Subtitle, [string]$Title = 'LEAGUE OF LEGENDS') {
    $form                 = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition   = 'CenterScreen'
    $form.Size            = New-Object System.Drawing.Size(420, 170)
    $form.BackColor       = [System.Drawing.ColorTranslator]::FromHtml($SplashColors.Background)
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false

    $title    = New-SplashLabel $Title    (New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)) $SplashColors.Title  'Top'  60
    $subtitle = New-SplashLabel $Subtitle (New-Object System.Drawing.Font('Segoe UI', 12)) $SplashColors.Text   'Top'  30
    $status   = New-SplashLabel ''        (New-Object System.Drawing.Font('Segoe UI', 9))  $SplashColors.Status 'Fill' 0

    # Dock 'Top' empile dans l'ordre inverse d'ajout : on ajoute donc de bas en haut
    $form.Controls.AddRange(@($status, (New-SplashProgressBar), $subtitle, $title))
    $form.Tag = $status
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
