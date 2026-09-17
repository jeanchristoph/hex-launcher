<#
.SYNOPSIS
    Palette réduite des drapeaux : toute couleur dessinée par le générateur d'icônes est ramenée à la teinte la plus proche.

.DESCRIPTION
    Chargé par dot-sourcing (tools\make-flag-icons.ps1, icon-badge.lib.ps1) :
        . (Join-Path $PSScriptRoot 'palette.lib.ps1')

    Huit teintes, choisies pour rester lisibles sous le logo or ; les dessins gardent leurs couleurs d'origine,
    seule la restitution change (distance RVB euclidienne, ex æquo → première teinte de la liste).
    La restitution est ensuite atténuée (saturation réduite, voile bleu nuit) pour que le logo or se détache.
    Les pastilles compagnon gardent leurs couleurs de catalogue et ne reçoivent que le voile nuit (ConvertTo-VeiledColor).
#>

Add-Type -AssemblyName System.Drawing

$FlagPalette = [ordered]@{
    Red     = '#C6202A'
    Blue    = '#1F4E9C'
    Navy    = '#1E2A5A'
    SkyBlue = '#74ACDF'
    Green   = '#1F7A3A'
    Yellow  = '#F2C230'
    White   = '#FFFFFF'
    Black   = '#141414'
}

function ConvertFrom-HexColor([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function ConvertTo-HexColor([System.Drawing.Color]$Color) {
    return ('#{0:X2}{1:X2}{2:X2}' -f $Color.R, $Color.G, $Color.B)
}

$script:PaletteColors = @($FlagPalette.Values | ForEach-Object { ConvertFrom-HexColor $_ })

function Get-ColorDistance([System.Drawing.Color]$A, [System.Drawing.Color]$B) {
    return [Math]::Pow($A.R - $B.R, 2) + [Math]::Pow($A.G - $B.G, 2) + [Math]::Pow($A.B - $B.B, 2)
}

# Teinte de la palette la plus proche d'une couleur #RRGGBB
function ConvertTo-PaletteColor([string]$Hex) {
    $wanted = ConvertFrom-HexColor $Hex
    $best = $null; $bestDistance = [double]::MaxValue
    foreach ($candidate in $script:PaletteColors) {
        $distance = Get-ColorDistance $wanted $candidate
        if ($distance -lt $bestDistance) { $best = $candidate; $bestDistance = $distance }
    }
    return $best
}

function ConvertTo-PaletteHex([string]$Hex) {
    return ConvertTo-HexColor (ConvertTo-PaletteColor $Hex)
}

# Atténuation des couleurs restituées : saturation réduite (luminance Rec. 601), puis voile bleu nuit
$PaletteMuting = @{
    Saturation = 0.72          # 1 = teinte pleine, 0 = gris
    VeilColor  = '#0A0E14'
    VeilAlpha  = 60            # 0-255
}

# sRGB ↔ lumière linéaire : le voile est mêlé en lumière linéaire, comme le fait GDI+ en CompositingQuality HighQuality
# dans le générateur d'icônes — une pastille et un drapeau blancs donnent ainsi le même gris
function ConvertTo-LinearLight([double]$Channel) {
    $c = $Channel / 255
    if ($c -le 0.04045) { return $c / 12.92 }
    return [Math]::Pow(($c + 0.055) / 1.055, 2.4)
}

function ConvertFrom-LinearLight([double]$Linear) {
    $c = if ($Linear -le 0.0031308) { 12.92 * $Linear } else { 1.055 * [Math]::Pow($Linear, 1 / 2.4) - 0.055 }
    return [int][Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $c)) * 255)
}

# Voile bleu nuit seul, mêlé en lumière linéaire
function ConvertTo-VeiledColor([System.Drawing.Color]$Color) {
    $veil = ConvertFrom-HexColor $PaletteMuting.VeilColor
    $a = $PaletteMuting.VeilAlpha / 255
    $veilChannels = @($veil.R, $veil.G, $veil.B); $channels = @($Color.R, $Color.G, $Color.B)
    $result = @(for ($i = 0; $i -lt 3; $i++) {
        ConvertFrom-LinearLight ((ConvertTo-LinearLight $channels[$i]) * (1 - $a) + (ConvertTo-LinearLight $veilChannels[$i]) * $a)
    })
    return [System.Drawing.Color]::FromArgb(255, $result[0], $result[1], $result[2])
}

# Saturation réduite puis voile : l'atténuation complète des drapeaux
function ConvertTo-MutedColor([System.Drawing.Color]$Color) {
    $s = $PaletteMuting.Saturation
    $luminance = 0.299 * $Color.R + 0.587 * $Color.G + 0.114 * $Color.B
    $desaturated = @(foreach ($value in @($Color.R, $Color.G, $Color.B)) { [int][Math]::Round($luminance + ($value - $luminance) * $s) })
    return ConvertTo-VeiledColor ([System.Drawing.Color]::FromArgb(255, $desaturated[0], $desaturated[1], $desaturated[2]))
}

# Couleur telle qu'elle apparaît sur une icône : palette puis atténuation
function ConvertTo-MutedPaletteColor([string]$Hex) {
    return ConvertTo-MutedColor (ConvertTo-PaletteColor $Hex)
}
