<#
.SYNOPSIS
    Reconstruit à plat une icône HL : logo extrait du modèle haute définition et réduit à des aplats,
    cadre et drapeau redessinés en vectoriel à chaque taille. Aucun pixel de fond source conservé.

.DESCRIPTION
    1. Logo (modèle HD, ex. 1254 px) : la matière chaude (or, or ombré) de la zone intérieure, trous compris
       (gemme, ornements), donne la silhouette ; les petites composantes isolées sont écartées, le bord lissé.
       Faces → or plat ; épaisseur (or sombre, nettoyé par ouverture morphologique) → or ombré ; gemme → disque
       vectoriel ; contour sombre d'épaisseur constante régénéré par distance. Reflets, dégradés et ombre portée disparaissent.
    2. Le calque logo est ramené dans l'espace icône (512 px) par le rectangle du cadre, puis réduit par moitiés
       successives : 256, 128, 64, 32, 16 (48 depuis 128).
    3. Cadre : carré arrondi tracé en GDI+ à chaque taille — liseré sombre, or plat, liseré sombre intérieur.
    4. Drapeau : dessin plat (scriptblock) découpé au carré arrondi intérieur ; couleurs lues sur le .ico source.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File 20260916-flatten-icon.ps1 -Source app\ico\hex-launcher-fr.ico -Model "tmp\proposals\modele\ChatGPT Image 14 sept. 2026, 02_40_47.png" -OutDir tmp\flat_icons
#>
param(
    # .ico d'origine : nom de sortie et couleurs du drapeau
    [Parameter(Mandatory)] [string]$Source,

    # Image haute définition du modèle (même logo, même cadre) : source du calque logo. Défaut : entrée 256 px du .ico
    [string]$Model,

    [Parameter(Mandatory)] [string]$OutDir,

    # Aplats du logo et du cadre (#RRGGBB) ; défaut : mesurés sur le modèle
    [string]$Gold,
    [string]$Dark,
    [string]$Gem,

    # Couleurs plates du drapeau, dans l'ordre des bandes ; défaut : bleu / blanc / rouge du fond du .ico (rang 0,8)
    [string[]]$FlagColors,

    # Dossier app\lib (défaut : ..\..\..\..\app\lib depuis ce script, ou app\lib sous le dossier courant)
    [string]$LibDir
)

Add-Type -AssemblyName System.Drawing

$libDir = if ($LibDir) { $LibDir } else {
    $candidate = Join-Path $PSScriptRoot '..\..\..\..\app\lib'
    if (Test-Path (Join-Path $candidate 'icon.lib.ps1')) { $candidate } else { Join-Path (Get-Location) 'app\lib' }
}
. (Join-Path $libDir 'icon.lib.ps1')

# ---------------------------------------------------------------- Géométrie, en fraction du côté de l'icône (mesurée sur le .ico à 256 px)

$FrameShape = @{
    Margin        = 7 / 256     # marge transparente autour du carré
    CornerRadius  = 40 / 256    # rayon des coins extérieurs
    Thickness     = 13 / 256    # cadre complet, liserés compris
    OuterDark     = 1 / 256     # liseré sombre extérieur
    InnerDark     = 2 / 256     # liseré sombre intérieur
    DarkLinesMin  = 48          # en dessous, le cadre est or plat sans liserés (trop fins)
    RingOfFrame   = 14 / 242    # cadre (liserés compris, marge exclue) en fraction du côté du cadre — segmentation des sources
}
# Traitement du logo, en fraction du côté du cadre (indépendant de la définition du modèle)
$LogoShape = @{
    OutlineWidth  = 2.5 / 242   # contour sombre régénéré autour de la silhouette
    CrackClosing  = 1 / 242     # rayon de fermeture morphologique des fissures sombres de la silhouette
    GemRing       = 1.5 / 242   # anneau sombre autour de la gemme
    MinComponent  = 0.003       # composante conservée si elle couvre au moins cette fraction du cadre²
    EdgeSmoothing = 0.25         # passes de lissage majoritaire 3×3 du bord (par tranche de 256 px de cadre)
}
$IconSizes = @(256, 128, 64, 48, 32, 16)
$LogoSpace = 512                # calque logo ramené dans l'espace icône à cette taille, puis réduit par moitiés

# ---------------------------------------------------------------- Segmentation et aplats (C# : boucles pixel)

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class HexLogoExtractor
{
    public static int[] ReadArgb(Bitmap bmp)
    {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var argb = new int[bmp.Width * bmp.Height];
        Marshal.Copy(data.Scan0, argb, 0, argb.Length);
        bmp.UnlockBits(data);
        return argb;
    }

    public static Bitmap ToBitmap(int[] argb, int w, int h)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(argb, 0, data.Scan0, argb.Length);
        bmp.UnlockBits(data);
        return bmp;
    }

    static int A(int c) { return (c >> 24) & 0xFF; }
    static int R(int c) { return (c >> 16) & 0xFF; }
    static int G(int c) { return (c >> 8) & 0xFF; }
    static int B(int c) { return c & 0xFF; }
    static int MaxChannel(int c) { return Math.Max(R(c), Math.Max(G(c), B(c))); }
    static int Rgb(Color c) { return c.ToArgb() & 0x00FFFFFF; }

    // Chaud (or, or ombré brun) : matière du logo et du cadre — le rouge des drapeaux (vert faible) en est exclu
    public static bool IsWarm(int c) { return A(c) > 0 && R(c) > B(c) + 50 && G(c) > B(c) + 10 && R(c) >= G(c); }
    public static bool IsGoldFace(int c) { return IsWarm(c) && R(c) >= 175; }   // face éclairée ; en dessous : épaisseur ombrée
    public static bool IsGoldShade(int c) { return IsWarm(c) && R(c) < 175 && MaxChannel(c) >= 70; }
    public static bool IsDark(int c) { return MaxChannel(c) < 70; }
    public static bool IsOutside(int c) { return A(c) < 128 || MaxChannel(c) < 24; }   // transparent, ou fond noir d'un modèle sans alpha
    public static bool IsBlueLike(int c)  { return B(c) > R(c) + 40 && B(c) > G(c) + 40; }
    public static bool IsRedLike(int c)   { return R(c) > G(c) + 60 && R(c) > B(c) + 60; }
    public static bool IsWhiteLike(int c) { int min = Math.Min(R(c), Math.Min(G(c), B(c))); return min > 120 && MaxChannel(c) - min < 40; }

    static readonly int[] DX = { 1, -1, 0, 0 };
    static readonly int[] DY = { 0, 0, 1, -1 };

    static void Flood(Queue<int> queue, bool[] mask, int w, int h, Func<int, bool> canEnter)
    {
        while (queue.Count > 0)
        {
            int i = queue.Dequeue();
            int x = i % w, y = i / w;
            for (int d = 0; d < 4; d++)
            {
                int nx = x + DX[d], ny = y + DY[d];
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                int n = ny * w + nx;
                if (mask[n] || !canEnter(n)) continue;
                mask[n] = true; queue.Enqueue(n);
            }
        }
    }

    // Extérieur : pixels transparents ou noirs joignables depuis le bord de l'image
    public static bool[] OutsideMask(int[] argb, int w, int h)
    {
        var mask = new bool[argb.Length];
        var queue = new Queue<int>();
        for (int i = 0; i < argb.Length; i++)
        {
            int x = i % w, y = i / w;
            bool onBorder = x == 0 || y == 0 || x == w - 1 || y == h - 1;
            if (onBorder && IsOutside(argb[i])) { mask[i] = true; queue.Enqueue(i); }
        }
        Flood(queue, mask, w, h, i => IsOutside(argb[i]));
        return mask;
    }

    // Distance de chanfrein 3-4 (3 = 1 px orthogonal) aux pixels du masque source
    public static int[] ChamferDistance(bool[] source, int w, int h)
    {
        const int INF = int.MaxValue / 2;
        var dist = new int[source.Length];
        for (int i = 0; i < dist.Length; i++) dist[i] = source[i] ? 0 : INF;
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) Relax(dist, w, h, x, y, -1);
        for (int y = h - 1; y >= 0; y--) for (int x = w - 1; x >= 0; x--) Relax(dist, w, h, x, y, 1);
        return dist;
    }

    static void Relax(int[] dist, int w, int h, int x, int y, int dir)
    {
        int i = y * w + x, best = dist[i];
        int[] ox = { dir, dir, 0, -dir };
        int[] oy = { 0, dir, dir, dir };
        int[] cost = { 3, 4, 3, 4 };
        for (int k = 0; k < 4; k++)
        {
            int nx = x + ox[k], ny = y + oy[k];
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            int candidate = dist[ny * w + nx] + cost[k];
            if (candidate < best) best = candidate;
        }
        dist[i] = best;
    }

    public static bool[] RingMask(int[] dist, bool[] outside, int thickness)
    {
        var mask = new bool[dist.Length];
        for (int i = 0; i < dist.Length; i++) mask[i] = !outside[i] && dist[i] <= thickness * 3;
        return mask;
    }

    // Logo : matière chaude de la zone intérieure, plus tout ce qu'elle enferme (gemme, ornements, traits sombres) —
    // le fond est ce qui reste joignable depuis le cadre sans traverser de matière chaude
    public static bool[] LogoMask(int[] argb, bool[] outside, bool[] ring, int[] dist, int thickness, int w, int h)
    {
        var warm = new bool[argb.Length];
        for (int i = 0; i < argb.Length; i++) warm[i] = !outside[i] && !ring[i] && IsWarm(argb[i]);

        var background = new bool[argb.Length];
        var queue = new Queue<int>();
        int seedLimit = (thickness + 2) * 3;
        Func<int, bool> isFree = i => !outside[i] && !ring[i] && !warm[i];
        for (int i = 0; i < argb.Length; i++)
        {
            if (dist[i] > seedLimit || !isFree(i)) continue;
            background[i] = true; queue.Enqueue(i);
        }
        Flood(queue, background, w, h, isFree);

        var logo = new bool[argb.Length];
        for (int i = 0; i < argb.Length; i++) logo[i] = !outside[i] && !ring[i] && !background[i];
        return logo;
    }

    public static bool[] BackgroundMask(bool[] outside, bool[] ring, bool[] logo)
    {
        var mask = new bool[outside.Length];
        for (int i = 0; i < mask.Length; i++) mask[i] = !outside[i] && !ring[i] && !logo[i];
        return mask;
    }

    // Supprime les composantes connexes de moins de minPixels (taches chaudes isolées dans l'ombre)
    public static bool[] RemoveSmallComponents(bool[] mask, int minPixels, int w, int h)
    {
        var result = new bool[mask.Length];
        var seen = new bool[mask.Length];
        for (int start = 0; start < mask.Length; start++)
        {
            if (!mask[start] || seen[start]) continue;
            var component = new List<int>();
            var queue = new Queue<int>();
            seen[start] = true; queue.Enqueue(start);
            while (queue.Count > 0)
            {
                int i = queue.Dequeue(); component.Add(i);
                int x = i % w, y = i / w;
                for (int d = 0; d < 4; d++)
                {
                    int nx = x + DX[d], ny = y + DY[d];
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                    int n = ny * w + nx;
                    if (seen[n] || !mask[n]) continue;
                    seen[n] = true; queue.Enqueue(n);
                }
            }
            if (component.Count >= minPixels) foreach (int i in component) result[i] = true;
        }
        return result;
    }

    // Lissage du bord : un pixel suit la majorité de son voisinage 3×3 (gomme bosses et encoches de 1 px)
    public static bool[] Majority3x3(bool[] mask, int w, int h)
    {
        var result = new bool[mask.Length];
        for (int i = 0; i < mask.Length; i++)
        {
            int x = i % w, y = i / w, count = 0;
            for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
            {
                int nx = x + dx, ny = y + dy;
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                if (mask[ny * w + nx]) count++;
            }
            result[i] = count >= 5;
        }
        return result;
    }

    public static bool[] MaskWhere(int[] argb, bool[] within, Func<int, bool> predicate)
    {
        var mask = new bool[argb.Length];
        for (int i = 0; i < mask.Length; i++) mask[i] = within[i] && predicate(argb[i]);
        return mask;
    }

    public static bool[] Invert(bool[] mask) { var r = new bool[mask.Length]; for (int i = 0; i < r.Length; i++) r[i] = !mask[i]; return r; }

    public static bool[] Dilate(bool[] mask, double radiusPx, int w, int h)
    {
        var dist = ChamferDistance(mask, w, h);
        var r = new bool[mask.Length];
        for (int i = 0; i < r.Length; i++) r[i] = dist[i] <= radiusPx * 3;
        return r;
    }

    public static bool[] Erode(bool[] mask, double radiusPx, int w, int h) { return Invert(Dilate(Invert(mask), radiusPx, w, h)); }

    // Ouverture : supprime traits fins et taches plus étroits que 2 × rayon
    public static bool[] Open(bool[] mask, double radiusPx, int w, int h) { return Dilate(Erode(mask, radiusPx, w, h), radiusPx, w, h); }

    // Boîte englobante d'un masque (vide si masque vide)
    public static Rectangle BoundingBox(bool[] mask, int w, int h)
    {
        int minX = w, minY = h, maxX = -1, maxY = -1;
        for (int i = 0; i < mask.Length; i++)
        {
            if (!mask[i]) continue;
            int x = i % w, y = i / w;
            if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
        return maxX < 0 ? Rectangle.Empty : new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }

    // Fermeture : referme fissures et trous plus étroits que 2 × rayon
    public static bool[] Close(bool[] mask, double radiusPx, int w, int h) { return Erode(Dilate(mask, radiusPx, w, h), radiusPx, w, h); }

    // Calque du logo : silhouette en or plat, posée sur un contour sombre d'épaisseur outlineWidth
    // généré par distance (bord anticrénelé)
    public static int[] BuildLogoLayer(bool[] logo, int[] logoDist, double outlineWidth, Color gold, Color outline)
    {
        var layer = new int[logo.Length];
        for (int i = 0; i < layer.Length; i++)
        {
            if (logo[i]) { layer[i] = unchecked((int)0xFF000000) | Rgb(gold); continue; }
            double coverage = Math.Max(0.0, Math.Min(1.0, outlineWidth + 0.5 - logoDist[i] / 3.0));
            int alpha = (int)Math.Round(coverage * 255);
            layer[i] = alpha == 0 ? 0 : (alpha << 24) | Rgb(outline);
        }
        return layer;
    }

    // Couleur par canal au rang donné (0,5 = médiane) parmi les pixels du masque retenus par le filtre
    public static Color PercentileColor(int[] argb, bool[] mask, Func<int, bool> filter, double fraction)
    {
        var rs = new List<int>(); var gs = new List<int>(); var bs = new List<int>();
        for (int i = 0; i < argb.Length; i++)
        {
            if (!mask[i] || !filter(argb[i])) continue;
            rs.Add(R(argb[i])); gs.Add(G(argb[i])); bs.Add(B(argb[i]));
        }
        if (rs.Count == 0) return Color.Empty;
        rs.Sort(); gs.Sort(); bs.Sort();
        int m = Math.Min(rs.Count - 1, (int)(rs.Count * fraction));
        return Color.FromArgb(rs[m], gs[m], bs[m]);
    }

    // Planche de contrôle : noir extérieur, or cadre, gris logo, bleu fond
    public static Bitmap MaskPreview(bool[] outside, bool[] ring, bool[] logo, int w, int h)
    {
        var argb = new int[outside.Length];
        for (int i = 0; i < argb.Length; i++)
            argb[i] = outside[i] ? unchecked((int)0xFF000000) : ring[i] ? unchecked((int)0xFFFFC800) : logo[i] ? unchecked((int)0xFFC0C0C0) : unchecked((int)0xFF3C3CC8);
        return ToBitmap(argb, w, h);
    }
}
'@

# ---------------------------------------------------------------- Couleurs

function Get-Color([string]$Hex) { return [System.Drawing.ColorTranslator]::FromHtml($Hex) }
function Format-Hex([System.Drawing.Color]$C) { return ('#{0:X2}{1:X2}{2:X2}' -f $C.R, $C.G, $C.B) }

function Get-ClassColor([int[]]$Argb, [bool[]]$Mask, [string]$Predicate, [double]$Rank) {
    $filter = [Func[int, bool]] { param($c) [HexLogoExtractor]::$Predicate($c) }.GetNewClosure()
    return [HexLogoExtractor]::PercentileColor($Argb, $Mask, $filter, $Rank)
}

function Resolve-Color([string]$Override, [scriptblock]$Measure) {
    if ($Override) { return Get-Color $Override }
    return & $Measure
}

# ---------------------------------------------------------------- Segmentation d'une image (modèle ou entrée du .ico)

function Get-Segmentation([System.Drawing.Bitmap]$Bitmap) {
    $w = $Bitmap.Width; $h = $Bitmap.Height
    $argb    = [HexLogoExtractor]::ReadArgb($Bitmap)
    $outside = [HexLogoExtractor]::OutsideMask($argb, $w, $h)
    $dist    = [HexLogoExtractor]::ChamferDistance($outside, $w, $h)
    # Rectangle extérieur du cadre : emprise de tout ce qui n'est pas extérieur ; le cadre en est une fraction fixe
    $frameBox = [HexLogoExtractor]::BoundingBox([HexLogoExtractor]::Invert($outside), $w, $h)
    $thick   = [int][Math]::Ceiling($frameBox.Width * $FrameShape.RingOfFrame)
    $ring    = [HexLogoExtractor]::RingMask($dist, $outside, $thick)
    $logo    = [HexLogoExtractor]::LogoMask($argb, $outside, $ring, $dist, $thick, $w, $h)
    return @{ Width = $w; Height = $h; Argb = $argb; Outside = $outside; Ring = $ring; Logo = $logo; Frame = $frameBox
              Background = [HexLogoExtractor]::BackgroundMask($outside, $ring, $logo) }
}

# Les pliures assombrissent surtout : couleur plate au rang 0,8 de chaque classe du fond
function Get-FlagColors($Segmentation) {
    if ($FlagColors) { return @($FlagColors | ForEach-Object { Get-Color $_ }) }
    return @('IsBlueLike', 'IsWhiteLike', 'IsRedLike' | ForEach-Object { Get-ClassColor $Segmentation.Argb $Segmentation.Background $_ 0.8 })
}

# Sombre des liserés et du contour : celui du contour du logo dans le .ico (bleu nuit), pris dans son fond
function Get-DarkColor($Segmentation) {
    return Resolve-Color $Dark { Get-ClassColor $Segmentation.Argb $Segmentation.Background 'IsDark' 0.5 }
}

# Aplats du logo et du cadre — un seul or, mesuré sur le modèle
function Get-LogoPalette($S) {
    return @{
        Gold = Resolve-Color $Gold { Get-ClassColor $S.Argb $S.Logo 'IsGoldFace' 0.6 }
        Gem  = Resolve-Color $Gem  { Get-ClassColor $S.Argb $S.Logo 'IsBlueLike' 0.7 }
    }
}

# ---------------------------------------------------------------- Calque logo (à la définition du modèle)

# Gemme : disque vectoriel sur l'emprise des pixels bleus du logo — anneau sombre puis aplat
function Draw-Gem([System.Drawing.Bitmap]$Layer, [System.Drawing.Rectangle]$Box, $Palette, [double]$RingWidth) {
    if ($Box.IsEmpty) { return }
    $g = [System.Drawing.Graphics]::FromImage($Layer)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $d = [Math]::Min($Box.Width, $Box.Height); $cx = $Box.X + $Box.Width / 2; $cy = $Box.Y + $Box.Height / 2
    $ring = New-Object System.Drawing.SolidBrush($Palette.Dark); $gem = New-Object System.Drawing.SolidBrush($Palette.Gem)
    $g.FillEllipse($ring, [float]($cx - $d / 2 - $RingWidth), [float]($cy - $d / 2 - $RingWidth), [float]($d + 2 * $RingWidth), [float]($d + 2 * $RingWidth))
    $g.FillEllipse($gem,  [float]($cx - $d / 2), [float]($cy - $d / 2), [float]$d, [float]$d)
    $ring.Dispose(); $gem.Dispose(); $g.Dispose()
}

# Silhouette nettoyée : composantes isolées écartées, fissures sombres refermées (fermeture), bord lissé
function Get-CleanLogoMask($S) {
    $side = $S.Frame.Width
    $logo = [HexLogoExtractor]::RemoveSmallComponents($S.Logo, [int]($side * $side * $LogoShape.MinComponent), $S.Width, $S.Height)
    $logo = [HexLogoExtractor]::Close($logo, ($side * $LogoShape.CrackClosing), $S.Width, $S.Height)
    $passes = [int][Math]::Round($LogoShape.EdgeSmoothing * $side / 256)
    for ($pass = 0; $pass -lt $passes; $pass++) { $logo = [HexLogoExtractor]::Majority3x3($logo, $S.Width, $S.Height) }
    return $logo
}

# Calque : silhouette en or plat, contour sombre, gemme vectorielle
function New-LogoLayer($S, [bool[]]$CleanLogo, $Palette) {
    $side = $S.Frame.Width
    $gemBox   = [HexLogoExtractor]::BoundingBox([HexLogoExtractor]::MaskWhere($S.Argb, $CleanLogo, [Func[int, bool]]{ param($c) [HexLogoExtractor]::IsBlueLike($c) }), $S.Width, $S.Height)
    $logoDist = [HexLogoExtractor]::ChamferDistance($CleanLogo, $S.Width, $S.Height)
    $layer = [HexLogoExtractor]::BuildLogoLayer($CleanLogo, $logoDist, ($side * $LogoShape.OutlineWidth), $Palette.Gold, $Palette.Dark)
    $bitmap = [HexLogoExtractor]::ToBitmap($layer, $S.Width, $S.Height)
    Draw-Gem $bitmap $gemBox $Palette ($side * $LogoShape.GemRing)
    return $bitmap
}

# ---------------------------------------------------------------- Espace icône : cadre vectoriel, drapeau, pyramide du logo

function New-RoundedSquarePath([double]$Offset, [double]$Side, [double]$Radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = [Math]::Max(0.0, [Math]::Min($Radius, $Side / 2)); $d = 2 * $r
    if ($d -le 0) { $path.AddRectangle((New-Object System.Drawing.RectangleF($Offset, $Offset, $Side, $Side))); return $path }
    $x = $Offset; $y = $Offset; $right = $Offset + $Side - $d; $bottom = $Offset + $Side - $d
    $path.AddArc([float]$x, [float]$y, [float]$d, [float]$d, 180, 90)
    $path.AddArc([float]$right, [float]$y, [float]$d, [float]$d, 270, 90)
    $path.AddArc([float]$right, [float]$bottom, [float]$d, [float]$d, 0, 90)
    $path.AddArc([float]$x, [float]$bottom, [float]$d, [float]$d, 90, 90)
    $path.CloseFigure()
    return $path
}

# Carrés arrondis emboîtés : Outer (liseré), Gold, Inner (liseré), Flag (zone du drapeau)
function Get-FrameMetrics([int]$Size) {
    $hasDarkLines = $Size -ge $FrameShape.DarkLinesMin
    $margin    = $Size * $FrameShape.Margin
    $radius    = $Size * $FrameShape.CornerRadius
    $thickness = [Math]::Max(1.0, $Size * $FrameShape.Thickness)
    $outerDark = if ($hasDarkLines) { [Math]::Max(1.0, $Size * $FrameShape.OuterDark) } else { 0 }
    $innerDark = if ($hasDarkLines) { [Math]::Max(1.0, $Size * $FrameShape.InnerDark) } else { 0 }
    $ring = { param($Inset) @{ Offset = $margin + $Inset; Radius = $radius - $Inset } }
    return @{
        Outer = & $ring 0
        Gold  = & $ring $outerDark
        Inner = & $ring ($thickness - $innerDark)
        Flag  = & $ring $thickness
    }
}

function Fill-RoundedSquare($G, [int]$Size, $Ring, [System.Drawing.Color]$Color) {
    $path = New-RoundedSquarePath $Ring.Offset ($Size - 2 * $Ring.Offset) $Ring.Radius
    $brush = New-Object System.Drawing.SolidBrush($Color)
    $G.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
}

# Bandes verticales égales sur la zone intérieure
function Draw-VerticalStripes($G, $Region, [System.Drawing.Color[]]$Colors) {
    $bandWidth = $Region.Width / $Colors.Count
    for ($i = 0; $i -lt $Colors.Count; $i++) {
        $brush = New-Object System.Drawing.SolidBrush($Colors[$i])
        $G.FillRectangle($brush, [float]($Region.Left + $bandWidth * $i), [float]$Region.Top, [float]($bandWidth + 1), [float]$Region.Height)
        $brush.Dispose()
    }
}

# Drapeau plat découpé au carré arrondi intérieur (remplissage par texture : bord anticrénelé)
function Draw-FlagLayer($G, [int]$Size, $M, [scriptblock]$Drawing) {
    $offset = $M.Flag.Offset; $side = $Size - 2 * $offset
    $region = @{ Left = $offset; Top = $offset; Width = $side; Height = $side }
    $flag = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($flag)
    & $Drawing $fg $region
    $fg.Dispose()
    $texture = New-Object System.Drawing.TextureBrush($flag); $texture.WrapMode = 'Clamp'
    $path = New-RoundedSquarePath $offset $side $M.Flag.Radius
    $G.FillPath($texture, $path)
    $path.Dispose(); $texture.Dispose(); $flag.Dispose()
}

function New-HighQualityGraphics([System.Drawing.Bitmap]$Bitmap) {
    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
    return $g
}

# Emprise du logo en fraction du cadre de sa source
function Get-RelativeBox([System.Drawing.Rectangle]$Box, [System.Drawing.Rectangle]$Frame) {
    return @{ X = ($Box.X - $Frame.X) / $Frame.Width; Y = ($Box.Y - $Frame.Y) / $Frame.Height
              Width = $Box.Width / $Frame.Width; Height = $Box.Height / $Frame.Height }
}

# Le calque logo (définition du modèle) ramené dans l'espace icône : l'emprise du logo du modèle est posée
# sur l'emprise du logo du .ico (taille et position de l'icône déposée conservées), à l'échelle uniforme
function ConvertTo-IconSpace([System.Drawing.Bitmap]$Layer, [System.Drawing.Rectangle]$ModelBox, $TargetBox, [int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-HighQualityGraphics $bmp
    $frameSide = $Size * (1 - 2 * $FrameShape.Margin); $margin = $Size * $FrameShape.Margin
    $scale = $frameSide * $TargetBox.Width / $ModelBox.Width
    $centerX = $margin + $frameSide * ($TargetBox.X + $TargetBox.Width / 2)
    $centerY = $margin + $frameSide * ($TargetBox.Y + $TargetBox.Height / 2)
    $destW = $ModelBox.Width * $scale; $destH = $ModelBox.Height * $scale
    $dest = New-Object System.Drawing.RectangleF(($centerX - $destW / 2), ($centerY - $destH / 2), $destW, $destH)
    $src  = New-Object System.Drawing.RectangleF($ModelBox.X, $ModelBox.Y, $ModelBox.Width, $ModelBox.Height)
    $g.DrawImage($Layer, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    return $bmp
}

function New-ResizedBitmap([System.Drawing.Bitmap]$Source, [int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-HighQualityGraphics $bmp
    $g.DrawImage($Source, 0, 0, $Size, $Size)
    $g.Dispose()
    return $bmp
}

# Pyramide du logo par moitiés successives depuis $LogoSpace (limite le moiré) ; les tailles hors puissance de 2
# sont tirées de la première taille de la pyramide au moins double
function New-LogoPyramid([System.Drawing.Bitmap]$LogoAtSpace) {
    $pyramid = @{ $LogoSpace = $LogoAtSpace }
    $current = $LogoAtSpace
    for ($size = $LogoSpace / 2; $size -ge 16; $size = $size / 2) {
        $current = New-ResizedBitmap $current $size; $pyramid[$size] = $current
    }
    foreach ($size in $IconSizes) {
        if ($pyramid.ContainsKey($size)) { continue }
        $from = ($pyramid.Keys | Where-Object { $_ -ge 2 * $size } | Sort-Object | Select-Object -First 1)
        $pyramid[$size] = New-ResizedBitmap $pyramid[$from] $size
    }
    return $pyramid
}

function New-FlatIconBitmap([int]$Size, $Palette, [System.Drawing.Bitmap]$LogoAtSize, [scriptblock]$FlagDrawing) {
    $m = Get-FrameMetrics $Size
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-HighQualityGraphics $bmp
    Fill-RoundedSquare $g $Size $m.Outer $Palette.Dark
    Fill-RoundedSquare $g $Size $m.Gold  $Palette.Gold
    Fill-RoundedSquare $g $Size $m.Inner $Palette.Dark
    Draw-FlagLayer $g $Size $m $FlagDrawing
    $g.DrawImage($LogoAtSize, 0, 0, $Size, $Size)
    $g.Dispose()
    return $bmp
}

# ---------------------------------------------------------------- Sorties

# Planche : source et résultat à 256, puis les petites tailles du résultat
function Export-ContactSheet([System.Drawing.Bitmap]$Source, [object[]]$Entries, [string]$Path) {
    $sheet = New-Object System.Drawing.Bitmap(560, 340, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 32, 32, 36))
    $g.InterpolationMode = 'NearestNeighbor'
    $g.DrawImage($Source, 16, 16, 256, 256)
    $g.DrawImage(($Entries | Where-Object Size -eq 256).Bitmap, 288, 16, 256, 256)
    $x = 288
    foreach ($e in ($Entries | Where-Object Size -lt 256 | Sort-Object Size -Descending)) {
        $g.DrawImage($e.Bitmap, $x, 288, $e.Size, $e.Size); $x += $e.Size + 12
    }
    $g.Dispose()
    $sheet.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
}

function Resolve-FullPath([string]$Path) { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }

$resolvedSource = Resolve-FullPath $Source
$resolvedOut    = Resolve-FullPath $OutDir
New-Item -ItemType Directory -Force $resolvedOut | Out-Null
$name = [IO.Path]::GetFileNameWithoutExtension($resolvedSource)

$entries = Read-IcoEntries $resolvedSource
$largest = $entries | Sort-Object Size -Descending | Select-Object -First 1
$modelBitmap = if ($Model) { New-Object System.Drawing.Bitmap((Resolve-FullPath $Model)) } else { $largest.Bitmap }

$iconSeg  = Get-Segmentation $largest.Bitmap
$modelSeg = if ($Model) { Get-Segmentation $modelBitmap } else { $iconSeg }
$palette  = Get-LogoPalette $modelSeg
$palette.Dark = Get-DarkColor $iconSeg
$palette.Flag = Get-FlagColors $iconSeg
Write-Host ("Modèle {0}x{0}, cadre {1} px - or {2} - sombre {3} - gemme {4} - drapeau {5}" -f $modelSeg.Width, $modelSeg.Frame.Width,
    (Format-Hex $palette.Gold), (Format-Hex $palette.Dark), (Format-Hex $palette.Gem), (($palette.Flag | ForEach-Object { Format-Hex $_ }) -join ' / '))

$modelLogo = Get-CleanLogoMask $modelSeg
$iconLogo  = if ($Model) { Get-CleanLogoMask $iconSeg } else { $modelLogo }
$modelBox  = [HexLogoExtractor]::BoundingBox($modelLogo, $modelSeg.Width, $modelSeg.Height)
$targetBox = Get-RelativeBox ([HexLogoExtractor]::BoundingBox($iconLogo, $iconSeg.Width, $iconSeg.Height)) $iconSeg.Frame
Write-Host ("Logo : {0:P1} du cadre dans le .ico, {1:P1} dans le modèle" -f $targetBox.Width, ((Get-RelativeBox $modelBox $modelSeg.Frame).Width))

$preview = [HexLogoExtractor]::MaskPreview($modelSeg.Outside, $modelSeg.Ring, $modelLogo, $modelSeg.Width, $modelSeg.Height)
$preview.Save((Join-Path $resolvedOut "$name-masks.png"), [System.Drawing.Imaging.ImageFormat]::Png); $preview.Dispose()

$layer = New-LogoLayer $modelSeg $modelLogo $palette
$layer.Save((Join-Path $resolvedOut "$name-logo-model.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$pyramid = New-LogoPyramid (ConvertTo-IconSpace $layer $modelBox $targetBox $LogoSpace)

$flagDrawing = { param($G, $R) Draw-VerticalStripes $G $R $palette.Flag }
$flatEntries = @(foreach ($size in $IconSizes) {
    [PSCustomObject]@{ Size = $size; Bitmap = (New-FlatIconBitmap $size $palette $pyramid[$size] $flagDrawing) }
})
($flatEntries | Where-Object Size -eq 256).Bitmap.Save((Join-Path $resolvedOut "$name-flat-256.png"), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Ico $flatEntries (Join-Path $resolvedOut "$name.ico")
Export-ContactSheet $largest.Bitmap $flatEntries (Join-Path $resolvedOut "$name-sheet.png")

$flatEntries | ForEach-Object { $_.Bitmap.Dispose() }
$pyramid.Values | ForEach-Object { $_.Dispose() }
$layer.Dispose()
if ($Model) { $modelBitmap.Dispose() }
$entries | ForEach-Object { $_.Bitmap.Dispose() }
"OK : $(Join-Path $resolvedOut "$name.ico")"
