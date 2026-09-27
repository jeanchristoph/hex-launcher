<#
.SYNOPSIS
    Aides de test : manifests RMAN synthétiques (corps FlatBuffers + en-tête + trame zstd).

.DESCRIPTION
    Suppose tests\zstd-test-helpers.ps1 déjà dot-sourcé. Charge lib\rman-reader.cs et tests\rman-test-builder.cs.
#>
$rmanHelpersFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not ([Management.Automation.PSTypeName]'HexLauncher.RmanManifest').Type) { Add-Type -Path (Join-Path $rmanHelpersFolder '..\app\lib\rman-reader.cs') }
if (-not ([Management.Automation.PSTypeName]'HexLauncher.Tests.RmanBodyBuilder').Type) { Add-Type -Path (Join-Path $rmanHelpersFolder 'rman-test-builder.cs') }

# Fichier .manifest complet : en-tête 28 octets + corps en trame zstd
function New-RmanManifestBytes([byte[]]$Body, [byte]$Major = 2, [byte]$Minor = 1, [uint64]$ManifestId = 0x5F25926EF18E78E7) {
    $frame  = New-ZstdRawFrame $Body
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RMAN')); $writer.Write($Major); $writer.Write($Minor)
    $writer.Write([uint16]0x0200); $writer.Write([uint32]28); $writer.Write([uint32]$frame.Length)
    $writer.Write($ManifestId); $writer.Write([uint32]$Body.Length)
    $writer.Write($frame)
    $writer.Flush()
    return , $stream.ToArray()
}

# Arborescence d'un jeu réduit à l'essentiel : DATA/FINAL/{Localized/Global, UI} en fr_FR, Global seul en ja_JP
function New-GameManifestBody {
    $builder = New-Object HexLauncher.Tests.RmanBodyBuilder
    [void]$builder.AddLanguage(16, 'fr_FR').AddLanguage(19, 'ja_JP')
    [void]$builder.AddDirectory(0, 0, '').AddDirectory(10, 0, 'DATA').AddDirectory(11, 10, 'FINAL').AddDirectory(12, 11, 'Localized')
    [void]$builder.AddBundle(0xB1, [uint64[]]@(0xC1, 100, 300, 0xC2, 50, 80, 0xC3, 20, 40))
    [void]$builder.AddBundle(0xB2, [uint64[]]@(0xC4, 70, 90))
    [void]$builder.AddFile(12, 'Global.fr_FR.wad.client', 380, (1 -shl 15), [uint64[]]@(0xC1, 0xC2))
    [void]$builder.AddFile(11, 'UI.fr_FR.wad.client', 130, (1 -shl 15), [uint64[]]@(0xC4, 0xC3))
    [void]$builder.AddFile(12, 'Global.ja_JP.wad.client', 40, (1 -shl 18), [uint64[]]@(0xC3))
    [void]$builder.SetHashType(4)
    return , $builder.Build()
}
