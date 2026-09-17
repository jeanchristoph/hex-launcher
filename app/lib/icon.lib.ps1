<#
.SYNOPSIS
    Lecture et écriture de fichiers .ico multi-tailles (entrées PNG ou DIB).

.DESCRIPTION
    Chargé par dot-sourcing depuis tools\make-flag-icons.ps1 et icon-badge.lib.ps1 :
        . (Join-Path $PSScriptRoot 'lib\icon.lib.ps1')

    Une entrée = [PSCustomObject]@{ Size = <int> ; Bitmap = <System.Drawing.Bitmap> }. Les bitmaps rendus par
    Read-IcoEntries appartiennent à l'appelant, qui les libère (Dispose) une fois utilisés.
    Write-Ico n'écrit que des entrées PNG (supportées depuis Vista) ; Read-IcoEntries accepte aussi les entrées DIB
    classiques via System.Drawing.Icon.
#>

Add-Type -AssemblyName System.Drawing

$IcoHeaderLength = 6
$IcoEntryLength  = 16
$PngSignature    = [byte[]](0x89, 0x50, 0x4E, 0x47)

# Chemin absolu au sens de PowerShell : les API .NET résolvent un chemin relatif contre le cwd du process, pas Set-Location
function Resolve-IcoPath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function ConvertTo-PngBytes([System.Drawing.Bitmap]$Bmp) {
    $ms = New-Object IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()   # la virgule évite que le pipeline déroule le byte[]
}

# .ico à entrées PNG : en-tête 6 o + 16 o par entrée, puis les données
function Write-Ico([object[]]$Entries, [string]$Path) {
    $pngs = @($Entries | ForEach-Object { [PSCustomObject]@{ Size = $_.Size; Bytes = (ConvertTo-PngBytes $_.Bitmap) } })
    $stream = [IO.File]::Create((Resolve-IcoPath $Path))
    $w = New-Object IO.BinaryWriter($stream)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$pngs.Count)
    $dataOffset = $IcoHeaderLength + $IcoEntryLength * $pngs.Count
    foreach ($p in $pngs) {
        $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$p.Bytes.Length); $w.Write([uint32]$dataOffset)
        $dataOffset += $p.Bytes.Length
    }
    foreach ($p in $pngs) { $w.Write($p.Bytes) }
    $w.Dispose(); $stream.Dispose()
}

# Répertoire des entrées : taille (0 dans l'en-tête = 256), offset et longueur des données
function Read-IcoDirectory([byte[]]$Bytes, [string]$Path) {
    if ($Bytes.Length -lt $IcoHeaderLength -or [BitConverter]::ToUInt16($Bytes, 2) -ne 1) { throw "Fichier .ico invalide : $Path" }
    $count = [BitConverter]::ToUInt16($Bytes, 4)
    if ($count -eq 0 -or $Bytes.Length -lt $IcoHeaderLength + $IcoEntryLength * $count) { throw "Fichier .ico invalide ou tronqué : $Path" }
    return @(for ($i = 0; $i -lt $count; $i++) {
        $at = $IcoHeaderLength + $IcoEntryLength * $i
        $dim = if ($Bytes[$at] -eq 0) { 256 } else { [int]$Bytes[$at] }
        [PSCustomObject]@{ Size = $dim; Length = [BitConverter]::ToUInt32($Bytes, $at + 8); Offset = [BitConverter]::ToUInt32($Bytes, $at + 12) }
    })
}

function Test-PngData([byte[]]$Bytes, [uint32]$Offset) {
    if ($Bytes.Length -lt $Offset + $PngSignature.Length) { return $false }
    for ($i = 0; $i -lt $PngSignature.Length; $i++) { if ($Bytes[$Offset + $i] -ne $PngSignature[$i]) { return $false } }
    return $true
}

# Copie indépendante du flux source : Bitmap.FromStream exige sinon que le flux reste ouvert.
# Clone (et non le constructeur Bitmap(Image)) : copie des pixels sans repasser par un rendu, qui arrondit l'alpha
function ConvertFrom-PngBytes([byte[]]$Bytes, [uint32]$Offset, [uint32]$Length) {
    $ms = New-Object IO.MemoryStream($Bytes, [int]$Offset, [int]$Length)
    $source = [System.Drawing.Bitmap]::FromStream($ms)
    $area = New-Object System.Drawing.Rectangle(0, 0, $source.Width, $source.Height)
    $copy = $source.Clone($area, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $source.Dispose(); $ms.Dispose()
    return $copy
}

# Entrée DIB classique : System.Drawing.Icon sait la décoder, à la taille demandée
function ConvertFrom-DibEntry([string]$Path, [int]$Size) {
    $icon = New-Object System.Drawing.Icon($Path, $Size, $Size)
    $bmp = $icon.ToBitmap()
    $icon.Dispose()
    return $bmp
}

# Toutes les entrées d'un .ico, dans l'ordre du fichier
function Read-IcoEntries([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Fichier .ico introuvable : $Path" }
    $Path = Resolve-IcoPath $Path
    $bytes = [IO.File]::ReadAllBytes($Path)
    return @(foreach ($entry in Read-IcoDirectory $bytes $Path) {
        if ($bytes.Length -lt $entry.Offset + $entry.Length) { throw "Fichier .ico tronqué : $Path" }
        $bitmap = if (Test-PngData $bytes $entry.Offset) { ConvertFrom-PngBytes $bytes $entry.Offset $entry.Length }
                  else { ConvertFrom-DibEntry $Path $entry.Size }
        [PSCustomObject]@{ Size = $bitmap.Width; Bitmap = $bitmap }
    })
}
