<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon-badge.lib.ps1 — pastille compagnon composée sur une icône drapeau du projet.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon-badge.lib.ps1')
$SourceIco = Join-Path $here '..\app\ico\hex-launcher-fr.ico'
$TestBadge = [pscustomobject]@{ glyph = 'I'; color = '#E0432B' }   # « I » : son centre est toujours encré

function Get-Argb([string]$Hex) { return ([System.Drawing.ColorTranslator]::FromHtml($Hex)).ToArgb() }

function Get-EntryOfSize([object[]]$Entries, [int]$Size) { return $Entries | Where-Object { $_.Size -eq $Size } | Select-Object -First 1 }

function Remove-Entries([object[]]$Entries) { $Entries | ForEach-Object { $_.Bitmap.Dispose() } }

# Point à l'intérieur du disque, à droite de la lettre : toujours de la couleur de la pastille
function Get-DiscProbe([int]$Size) {
    $m = Get-BadgeMetrics $Size
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
