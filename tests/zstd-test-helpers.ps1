<#
.SYNOPSIS
    Aides de test : trames zstd fabriquées sans compresseur.

.DESCRIPTION
    Une trame zstd peut porter ses données sans compression (blocs « raw ») : libzstd la décompresse comme
    n'importe quelle autre. Les tests fabriquent ainsi manifests et chunks synthétiques à partir d'octets clairs.
#>

$ZstdRawBlockMaxSize = 128KB

# Trame zstd valide : magic, en-tête (segment unique, taille de contenu sur 4 octets), blocs raw, sans checksum
function New-ZstdRawFrame([byte[]]$Content) {
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    $writer.Write([byte[]](0x28, 0xB5, 0x2F, 0xFD))
    $writer.Write([byte]0xA0)
    $writer.Write([uint32]$Content.Length)
    $offset = 0
    do {
        $size   = [Math]::Min($ZstdRawBlockMaxSize, $Content.Length - $offset)
        $isLast = ($offset + $size) -ge $Content.Length
        $header = ($size -shl 3) -bor [int]$isLast
        $writer.Write([byte]($header -band 0xFF)); $writer.Write([byte](($header -shr 8) -band 0xFF)); $writer.Write([byte](($header -shr 16) -band 0xFF))
        $writer.Write($Content, $offset, $size)
        $offset += $size
    } while (-not $isLast)
    $writer.Flush()
    return , $stream.ToArray()
}

function ConvertFrom-HexString([string]$Hex) {
    return , [byte[]]@(for ($i = 0; $i -lt $Hex.Length; $i += 2) { [Convert]::ToByte($Hex.Substring($i, 2), 16) })
}
