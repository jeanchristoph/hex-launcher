<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon-badge.lib.ps1 — pastille compagnon composée sur une icône drapeau du projet.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon-badge.lib.ps1')
$SourceIco = Join-Path $here '..\app\ico\flat\hex-launcher-fr.ico'
$TestBadge = [pscustomobject]@{ glyph = 'I'; color = '#E0432B' }   # « I » : son centre est toujours encré

function Get-Argb([string]$Hex) { return ([System.Drawing.ColorTranslator]::FromHtml($Hex)).ToArgb() }
$VeiledStyle  = @{ NightVeil = $true; ReducedPalette = $false }
$ReducedStyle = @{ NightVeil = $false; ReducedPalette = $true }

function Get-EntryOfSize([object[]]$Entries, [int]$Size) { return $Entries | Where-Object { $_.Size -eq $Size } | Select-Object -First 1 }

# Ecart maximal par canal entre un pixel et une couleur attendue : le drapeau reduit en bicubique arrondit d'une unite
function Get-ChannelGap([System.Drawing.Color]$Pixel, [string]$Hex) {
    $wanted = [System.Drawing.ColorTranslator]::FromHtml($Hex)
    return [Math]::Max([Math]::Abs($Pixel.R - $wanted.R), [Math]::Max([Math]::Abs($Pixel.G - $wanted.G), [Math]::Abs($Pixel.B - $wanted.B)))
}

# A 16 px la pastille pays fait 5 px : le disque japonais n'y couvre plus un pixel entier, on verifie une dominante rouge
function Test-Reddish([System.Drawing.Color]$Pixel) {
    return ($Pixel.A -eq 255 -and $Pixel.R -gt 150 -and $Pixel.R -gt $Pixel.G + 80 -and $Pixel.R -gt $Pixel.B + 80)
}

function Remove-Entries([object[]]$Entries) { $Entries | ForEach-Object { $_.Bitmap.Dispose() } }

# Point à l'intérieur du disque, à droite de la lettre : toujours de la couleur de la pastille
function Get-DiscProbe([int]$Size, [int]$Slot = 0) {
    $m = Get-BadgeMetrics $Size $Slot
    return @{ X = [int][Math]::Round($m.Cx + $m.Diameter * 0.40); Y = [int][Math]::Round($m.Cy) }
}

Describe 'Get-BadgeMetrics' {
    It 'place le disque en haut à droite, sans sortir de l''icône' {
        $m = Get-BadgeMetrics 256
        $m.Cx | Should BeGreaterThan 128
        $m.Cy | Should BeLessThan 128
        ($m.Cx + $m.Diameter / 2 + $m.Ring) | Should BeLessThan 256
        ($m.Cy - $m.Diameter / 2 - $m.Ring) | Should BeGreaterThan 0
    }

    It 'garde un anneau d''au moins un pixel aux petites tailles' {
        (Get-BadgeMetrics 16).Ring | Should Be 1
    }

    It 'épaissit la lettre d''un contour proportionnel au diamètre' {
        (Get-BadgeMetrics 256).GlyphStroke | Should BeGreaterThan 1
        (Get-BadgeMetrics 256).GlyphStroke | Should BeLessThan 3
    }

    It 'omet la lettre sous 32 px' {
        (Get-BadgeMetrics 32).HasGlyph | Should Be $true
        (Get-BadgeMetrics 16).HasGlyph | Should Be $false
    }

    It 'empile le second emplacement sous le premier, même colonne, sans chevauchement ni sortie de l''icône' {
        $top = Get-BadgeMetrics 256 0; $below = Get-BadgeMetrics 256 1
        $below.Cx | Should Be $top.Cx
        ($below.Cy - $below.Diameter / 2 - $below.Ring) | Should BeGreaterThan ($top.Cy + $top.Diameter / 2 + $top.Ring)
        ($below.Cy + $below.Diameter / 2 + $below.Ring) | Should BeLessThan 256
    }
}

Describe 'New-FlagBadgeBitmap' {
    It 'rend un carré du diamètre demandé, aux couleurs brutes du drapeau' {
        $flag = New-FlagBadgeBitmap 'ja_JP' 40
        try {
            $flag.Width | Should Be 40
            $flag.Height | Should Be 40
            $flag.GetPixel(20, 20).ToArgb() | Should Be (Get-Argb '#BC002D')
            $flag.GetPixel(2, 2).ToArgb() | Should Be (Get-Argb '#FFFFFF')
        } finally { $flag.Dispose() }
    }

    It 'refuse une langue sans dessin' {
        { New-FlagBadgeBitmap 'xx_XX' 40 } | Should Throw
    }
}

Describe 'Add-CountryBadgeToBitmap' {
    function New-BlankBitmap([int]$Size) {
        $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(255, 5, 40, 62)); $g.Dispose()
        return $bmp
    }

    It 'peint le disque rouge du Japon au centre de la pastille à 256, 48 et 32 px (à une unité près)' {
        foreach ($size in 256, 48, 32) {
            $bmp = New-BlankBitmap $size
            try {
                Add-CountryBadgeToBitmap $bmp 'ja_JP'
                $m = Get-BadgeMetrics $size
                (Get-ChannelGap $bmp.GetPixel([int]$m.Cx, [int]$m.Cy) '#BC002D') | Should BeLessThan 2
            } finally { $bmp.Dispose() }
        }
    }

    It 'laisse une dominante rouge au centre de la pastille de 5 px à 16 px' {
        $bmp = New-BlankBitmap 16
        try {
            Add-CountryBadgeToBitmap $bmp 'ja_JP'
            $m = Get-BadgeMetrics 16
            Test-Reddish $bmp.GetPixel([int]$m.Cx, [int]$m.Cy) | Should Be $true
        } finally { $bmp.Dispose() }
    }

    It 'garde les trois bandes de la France visibles : disque inscrit dans le carré, pas de recadrage' {
        $bmp = New-BlankBitmap 256
        try {
            Add-CountryBadgeToBitmap $bmp 'fr_FR'
            $m = Get-BadgeMetrics 256; $r = $m.Diameter / 2
            $bmp.GetPixel([int]($m.Cx - $r * 0.75), [int]$m.Cy).ToArgb() | Should Be (Get-Argb '#000091')
            $bmp.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb()                | Should Be (Get-Argb '#FFFFFF')
            $bmp.GetPixel([int]($m.Cx + $r * 0.75), [int]$m.Cy).ToArgb() | Should Be (Get-Argb '#E1000F')
        } finally { $bmp.Dispose() }
    }

    It 'perd les coins du carré : le fond reste visible en diagonale hors du disque' {
        $bmp = New-BlankBitmap 256
        try {
            Add-CountryBadgeToBitmap $bmp 'fr_FR'
            $m = Get-BadgeMetrics 256; $r = $m.Diameter / 2 + $m.Ring
            $bmp.GetPixel([int]($m.Cx - $r * 0.9), [int]($m.Cy - $r * 0.9)).ToArgb() | Should Be ([System.Drawing.Color]::FromArgb(255, 5, 40, 62).ToArgb())
        } finally { $bmp.Dispose() }
    }

    It 'ne touche pas au fond hors de la pastille' {
        $bmp = New-BlankBitmap 256
        try {
            Add-CountryBadgeToBitmap $bmp 'ja_JP'
            $bmp.GetPixel(128, 200).ToArgb() | Should Be ([System.Drawing.Color]::FromArgb(255, 5, 40, 62).ToArgb())
        } finally { $bmp.Dispose() }
    }
}

Describe 'Add-StackedBadgesToBitmap' {
    function New-BlankBitmap([int]$Size) {
        $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(255, 5, 40, 62)); $g.Dispose()
        return $bmp
    }
    $background = [System.Drawing.Color]::FromArgb(255, 5, 40, 62).ToArgb()

    It 'met le pays en haut et le compagnon en dessous à 256 et 32 px' {
        foreach ($size in 256, 32) {
            $bmp = New-BlankBitmap $size
            try {
                Add-StackedBadgesToBitmap $bmp 'ja_JP' $TestBadge
                $country = Get-BadgeMetrics $size 0; $companion = Get-DiscProbe $size 1
                (Get-ChannelGap $bmp.GetPixel([int]$country.Cx, [int]$country.Cy) '#BC002D') | Should BeLessThan 2
                $bmp.GetPixel($companion.X, $companion.Y).ToArgb() | Should Be (Get-Argb $TestBadge.color)
            } finally { $bmp.Dispose() }
        }
    }

    It 'ne garde que le pays sous 32 px' {
        $bmp = New-BlankBitmap 16
        try {
            Add-StackedBadgesToBitmap $bmp 'ja_JP' $TestBadge
            $country = Get-BadgeMetrics 16 0; $companion = Get-BadgeMetrics 16 1
            Test-Reddish $bmp.GetPixel([int]$country.Cx, [int]$country.Cy) | Should Be $true
            $bmp.GetPixel([int]$companion.Cx, [int]$companion.Cy).ToArgb() | Should Be $background
        } finally { $bmp.Dispose() }
    }

    It 'ne dessine que le pays sans pastille compagnon' {
        $bmp = New-BlankBitmap 256
        try {
            Add-StackedBadgesToBitmap $bmp 'ja_JP' $null
            $companion = Get-BadgeMetrics 256 1
            $bmp.GetPixel([int]$companion.Cx, [int]$companion.Cy).ToArgb() | Should Be $background
        } finally { $bmp.Dispose() }
    }
}

Describe 'Get-StackedBadgeSignature' {
    It 'rend 8 caractères hexadécimaux, stables pour une même pile' {
        Get-StackedBadgeSignature 'ja_JP' $TestBadge | Should Match '^[0-9a-f]{8}$'
        Get-StackedBadgeSignature 'ja_JP' $TestBadge | Should Be (Get-StackedBadgeSignature 'ja_JP' $TestBadge)
    }

    It 'change avec le pays, la pastille compagnon, son absence et le style' {
        $reference = Get-StackedBadgeSignature 'ja_JP' $TestBadge
        Get-StackedBadgeSignature 'fr_FR' $TestBadge | Should Not Be $reference
        Get-StackedBadgeSignature 'ja_JP' ([pscustomobject]@{ glyph = 'B'; color = '#E4103F' }) | Should Not Be $reference
        Get-StackedBadgeSignature 'ja_JP' $null | Should Not Be $reference
        Get-StackedBadgeSignature 'ja_JP' $TestBadge $VeiledStyle | Should Not Be $reference
    }

    It 'change quand le dessin du drapeau change' {
        $saved = $FlagDrawings['ja_JP']
        $before = Get-StackedBadgeSignature 'ja_JP' $null
        $FlagDrawings['ja_JP'] = { param($G, $R) $G.Clear((Get-FlagColor '#FFFFFF')) }
        try { Get-StackedBadgeSignature 'ja_JP' $null | Should Not Be $before }
        finally { $FlagDrawings['ja_JP'] = $saved }
    }
}

Describe 'Add-StackedBadgesToExecutableIcon' {
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $destination = Join-Path $TestDrive 'hex-launcher-jp-stacked.ico'
    Add-StackedBadgesToExecutableIcon $powershellExe 'ja_JP' $TestBadge $destination | Out-Null
    $result = Read-IcoEntries $destination

    It 'écrit les six tailles de l''icône du binaire' {
        ($result | ForEach-Object { $_.Size } | Sort-Object -Descending) -join ',' | Should Be '256,128,64,48,32,16'
    }

    It 'porte la pastille pays et la pastille compagnon à 256 px, le pays seul à 16 px' {
        $country = Get-BadgeMetrics 256 0; $companion = Get-DiscProbe 256 1
        (Get-ChannelGap (Get-EntryOfSize $result 256).Bitmap.GetPixel([int]$country.Cx, [int]$country.Cy) '#BC002D') | Should BeLessThan 2
        (Get-EntryOfSize $result 256).Bitmap.GetPixel($companion.X, $companion.Y).ToArgb() | Should Be (Get-Argb $TestBadge.color)
        $small = Get-BadgeMetrics 16 0
        Test-Reddish (Get-EntryOfSize $result 16).Bitmap.GetPixel([int]$small.Cx, [int]$small.Cy) | Should Be $true
    }

    It 'compose le pays seul sans pastille compagnon' {
        $alone = Join-Path $TestDrive 'hex-launcher-jp-alone.ico'
        Add-StackedBadgesToExecutableIcon $powershellExe 'ja_JP' $null $alone | Should Be $alone
        $entries = Read-IcoEntries $alone
        $country = Get-BadgeMetrics 256 0
        (Get-ChannelGap (Get-EntryOfSize $entries 256).Bitmap.GetPixel([int]$country.Cx, [int]$country.Cy) '#BC002D') | Should BeLessThan 2
        Remove-Entries $entries
    }

    It 'refuse un binaire introuvable et une pastille sans couleur' {
        { Add-StackedBadgesToExecutableIcon (Join-Path $TestDrive 'absent.exe') 'ja_JP' $null (Join-Path $TestDrive 'x.ico') } | Should Throw
        { Add-StackedBadgesToExecutableIcon $powershellExe 'ja_JP' ([pscustomobject]@{ glyph = 'B'; color = '' }) (Join-Path $TestDrive 'x.ico') } | Should Throw
    }

    Remove-Entries $result
}

Describe 'Get-BadgeGlyphColor' {
    It 'écrit en blanc sur une pastille sombre' {
        Get-BadgeGlyphColor ([pscustomobject]@{ color = '#E4103F' }) | Should Be '#FFFFFF'
        Get-BadgeGlyphColor ([pscustomobject]@{ color = '#3D3A69' }) | Should Be '#FFFFFF'
    }

    It 'écrit en bleu nuit sur une pastille claire' {
        Get-BadgeGlyphColor ([pscustomobject]@{ color = '#ECEAE4' }) | Should Be '#0A0E14'
    }

    It 'respecte la couleur de lettre du catalogue quand elle est donnée' {
        Get-BadgeGlyphColor ([pscustomobject]@{ color = '#ECEAE4'; glyphColor = '#172636' }) | Should Be '#172636'
    }
}

Describe 'Get-BadgeSignature' {
    $badge = [pscustomobject]@{ glyph = 'P'; color = '#ECEAE4'; glyphColor = '#E36A62' }

    It 'rend 8 caractères hexadécimaux, stables pour une même pastille' {
        Get-BadgeSignature $badge | Should Match '^[0-9a-f]{8}$'
        Get-BadgeSignature $badge | Should Be (Get-BadgeSignature $badge)
    }

    It 'change avec la lettre, la couleur du disque ou celle de la lettre' {
        Get-BadgeSignature ([pscustomobject]@{ glyph = 'B'; color = '#ECEAE4'; glyphColor = '#E36A62' }) | Should Not Be (Get-BadgeSignature $badge)
        Get-BadgeSignature ([pscustomobject]@{ glyph = 'P'; color = '#E4103F'; glyphColor = '#E36A62' }) | Should Not Be (Get-BadgeSignature $badge)
        Get-BadgeSignature ([pscustomobject]@{ glyph = 'P'; color = '#ECEAE4' }) | Should Not Be (Get-BadgeSignature $badge)
    }

    It 'change avec le style de pastille' {
        Get-BadgeSignature $badge $VeiledStyle | Should Not Be (Get-BadgeSignature $badge)
        Get-BadgeSignature $badge $ReducedStyle | Should Not Be (Get-BadgeSignature $badge)
    }

    It 'change avec les métriques de dessin' {
        $before = Get-BadgeSignature $badge
        $saved = $BadgeShape.GlyphStroke
        $BadgeShape.GlyphStroke = $saved + 0.01
        $after = Get-BadgeSignature $badge
        $BadgeShape.GlyphStroke = $saved
        $after | Should Not Be $before
    }
}

Describe 'Add-CompanionBadge' {
    $destination = Join-Path $TestDrive 'hex-launcher-fr-test.ico'
    Add-CompanionBadge $SourceIco $TestBadge $destination | Out-Null
    $source = Read-IcoEntries $SourceIco
    $result = Read-IcoEntries $destination

    It 'conserve les six tailles de l''icône source' {
        ($result | ForEach-Object { $_.Size } | Sort-Object -Descending) -join ',' | Should Be '256,128,64,48,32,16'
    }

    It 'peint le disque de la couleur de la pastille à 256, 48, 32 et 16 px' {
        foreach ($size in 256, 48, 32, 16) {
            $probe = Get-DiscProbe $size
            (Get-EntryOfSize $result $size).Bitmap.GetPixel($probe.X, $probe.Y).ToArgb() | Should Be (Get-Argb $TestBadge.color)
        }
    }

    It 'écrit la lettre en blanc au centre du disque à 256 px' {
        $m = Get-BadgeMetrics 256
        (Get-EntryOfSize $result 256).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (Get-Argb '#FFFFFF')
    }

    It 'écrit la lettre en bleu nuit au centre d''une pastille claire' {
        $light = Join-Path $TestDrive 'light.ico'
        Add-CompanionBadge $SourceIco ([pscustomobject]@{ glyph = 'I'; color = '#ECEAE4' }) $light | Out-Null
        $entries = Read-IcoEntries $light
        $m = Get-BadgeMetrics 256
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (Get-Argb '#0A0E14')
        Remove-Entries $entries
    }

    It 'écrit la lettre dans la couleur explicite du catalogue' {
        $custom = Join-Path $TestDrive 'custom.ico'
        Add-CompanionBadge $SourceIco ([pscustomobject]@{ glyph = 'I'; color = '#ECEAE4'; glyphColor = '#172636' }) $custom | Out-Null
        $entries = Read-IcoEntries $custom
        $m = Get-BadgeMetrics 256
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (Get-Argb '#172636')
        Remove-Entries $entries
    }

    It 'laisse le disque plein, sans lettre, à 16 px' {
        $m = Get-BadgeMetrics 16
        (Get-EntryOfSize $result 16).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (Get-Argb $TestBadge.color)
    }

    It 'ne touche pas au drapeau hors de la pastille' {
        foreach ($size in 256, 16) {
            $x = [int]($size / 2); $y = [int]($size * 0.8)
            (Get-EntryOfSize $result $size).Bitmap.GetPixel($x, $y).ToArgb() | Should Be ((Get-EntryOfSize $source $size).Bitmap.GetPixel($x, $y).ToArgb())
        }
    }

    It 'renvoie le chemin de l''icône composée' {
        Add-CompanionBadge $SourceIco $TestBadge (Join-Path $TestDrive 'again.ico') | Should Be (Join-Path $TestDrive 'again.ico')
    }

    It 'passe disque et lettre sous le voile nuit quand le style le demande' {
        $veiled = Join-Path $TestDrive 'veiled.ico'
        Add-CompanionBadge $SourceIco ([pscustomobject]@{ glyph = 'I'; color = '#ECEAE4'; glyphColor = '#E36A62' }) $veiled $VeiledStyle | Out-Null
        $entries = Read-IcoEntries $veiled
        $m = Get-BadgeMetrics 256; $probe = Get-DiscProbe 256
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel($probe.X, $probe.Y).ToArgb() | Should Be (ConvertTo-VeiledColor (ConvertFrom-HexColor '#ECEAE4')).ToArgb()
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (ConvertTo-VeiledColor (ConvertFrom-HexColor '#E36A62')).ToArgb()
        Remove-Entries $entries
    }

    It 'ramène disque et lettre à la palette réduite quand le style le demande' {
        $reduced = Join-Path $TestDrive 'reduced.ico'
        Add-CompanionBadge $SourceIco ([pscustomobject]@{ glyph = 'I'; color = '#ECEAE4'; glyphColor = '#E36A62' }) $reduced $ReducedStyle | Out-Null
        $entries = Read-IcoEntries $reduced
        $m = Get-BadgeMetrics 256; $probe = Get-DiscProbe 256
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel($probe.X, $probe.Y).ToArgb() | Should Be (Get-Argb $FlagPalette.White)
        (Get-EntryOfSize $entries 256).Bitmap.GetPixel([int]$m.Cx, [int]$m.Cy).ToArgb() | Should Be (Get-Argb $FlagPalette.Red)
        Remove-Entries $entries
    }

    It 'refuse une pastille sans couleur' {
        { Add-CompanionBadge $SourceIco ([pscustomobject]@{ glyph = 'B'; color = '' }) (Join-Path $TestDrive 'x.ico') } | Should Throw
        { Add-CompanionBadge $SourceIco $null (Join-Path $TestDrive 'x.ico') } | Should Throw
    }

    It 'refuse une icône source introuvable' {
        { Add-CompanionBadge (Join-Path $TestDrive 'absent.ico') $TestBadge (Join-Path $TestDrive 'x.ico') } | Should Throw
    }

    Remove-Entries $source
    Remove-Entries $result
}
