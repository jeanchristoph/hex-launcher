<#
.SYNOPSIS
    Tests Pester 3.4 de tools\make-logo-icon.ps1 — icône de base du jeu logo-badges (logo HL seul, agrandi).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\tools\make-logo-icon.ps1')

$TestSvg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <g id="frame">
    <path d="M 0 0"/>
    <g clip-path="url(#frame-clip)">
      <path d="M 1 1"/>
    </g>
  </g>
  <g id="logo"><path d="M 2 2"/></g>
  <g id="gem"><circle cx="1" cy="1" r="1"/></g>
</svg>
'@

Describe 'Remove-SvgFrame' {
    It 'retire le cadre et garde le logo et la gemme' {
        $svg = Remove-SvgFrame $TestSvg
        $svg | Should Not Match 'id="frame"'
        $svg | Should Not Match 'frame-clip'
        $svg | Should Match 'id="logo"'
        $svg | Should Match 'id="gem"'
    }

    It 'refuse un SVG sans cadre (format du logo changé)' {
        { Remove-SvgFrame '<svg viewBox="0 0 256 256"><g id="logo"/></svg>' } | Should Throw 'frame'
    }
}

Describe 'Set-SvgViewBox' {
    It 'remplace le viewBox de la racine, en notation invariante' {
        Set-SvgViewBox $TestSvg ([pscustomobject]@{ X = 10.5; Y = -3.25; Side = 200 }) | Should Match 'viewBox="10.5 -3.25 200 200"'
    }
}

Describe 'Get-LogoViewBox' {
    # Logo plus large que haut, comme le HL : 200 × 100 à partir de (28, 78)
    $bounds = [pscustomobject]@{ X = 28; Y = 78; Width = 200; Height = 100 }

    It 'fait un carré dont le logo occupe la part -LogoFill de la largeur, centré' {
        $box = Get-LogoViewBox $bounds 'centered'
        [Math]::Round($box.Side, 3) | Should Be ([Math]::Round(200 / $LogoFill, 3))
        [Math]::Round($box.X + $box.Side / 2, 3) | Should Be 128
    }

    It 'centre le logo en hauteur' {
        $box = Get-LogoViewBox $bounds 'centered'
        [Math]::Round($box.Y + $box.Side / 2, 3) | Should Be 128
    }

    It 'cale le logo en bas, avec la même marge qu''à gauche et à droite' {
        $box = Get-LogoViewBox $bounds 'bottom'
        $margin = ($box.Side - 200) / 2
        [Math]::Round($box.Y + $box.Side, 3) | Should Be ([Math]::Round(178 + $margin, 3))
    }
}

Describe 'Get-OpaqueBounds' {
    It 'rend le rectangle des pixels opaques' {
        $bmp = New-Object System.Drawing.Bitmap(32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.FillRectangle([System.Drawing.Brushes]::Gold, 4, 10, 20, 6)
        $g.Dispose()
        $bounds = Get-OpaqueBounds $bmp
        "$($bounds.X),$($bounds.Y),$($bounds.Width),$($bounds.Height)" | Should Be '4,10,20,6'
    }

    It 'rend null pour une image vide' {
        Get-OpaqueBounds (New-Object System.Drawing.Bitmap(8, 8, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)) | Should BeNullOrEmpty
    }
}

Describe 'ConvertTo-SvgBounds' {
    It 'ramène une emprise mesurée à 1024 px aux unités du viewBox 256' {
        $bounds = ConvertTo-SvgBounds ([pscustomobject]@{ X = 136; Y = 326; Width = 760; Height = 544 }) 1024
        "$($bounds.X),$($bounds.Y),$($bounds.Width),$($bounds.Height)" | Should Be '34,81.5,190,136'
    }
}

Describe 'Icônes du logo livrées' {
    $root = Split-Path $here -Parent

    It 'donne au jeu logo la même icône que le .exe de l''installeur' {
        $set       = [IO.File]::ReadAllBytes((Join-Path $root 'app\ico\logo\hex-launcher.ico'))
        $installer = [IO.File]::ReadAllBytes((Join-Path $root 'tools\installer\installer-logo.ico'))
        [Convert]::ToBase64String($set) | Should Be ([Convert]::ToBase64String($installer))
    }
}
