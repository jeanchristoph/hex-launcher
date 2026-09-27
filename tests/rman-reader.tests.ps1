<#
.SYNOPSIS
    Tests Pester 3.4 de lib\rman-reader.cs — en-tête RMAN, corps FlatBuffers, recherche d'un fichier et de ses chunks.

.DESCRIPTION
    Manifests synthétiques fabriqués par tests\rman-test-builder.cs ; jamais le Game.manifest de l'installation Riot.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\zstd.lib.ps1')
. (Join-Path $here 'zstd-test-helpers.ps1')
. (Join-Path $here 'rman-test-helpers.ps1')

Describe 'RmanHeader.Parse' {
    It 'lit version, id du manifest et emplacement du corps' {
        $bytes  = New-RmanManifestBytes (New-GameManifestBody)
        $header = [HexLauncher.RmanHeader]::Parse($bytes)
        "$($header.Major).$($header.Minor)" | Should Be '2.1'
        $header.ManifestIdHex | Should Be '5F25926EF18E78E7'
        $header.BodyOffset | Should Be 28
        ($header.BodyOffset + $header.BodyCompressedLength) | Should Be $bytes.Length
    }

    It 'accepte la version 2.0' {
        [HexLauncher.RmanHeader]::Parse((New-RmanManifestBytes (New-GameManifestBody) 2 0)).Minor | Should Be 0
    }

    It 'refuse une version dont la structure est inconnue (2.2, 3.0)' {
        { [HexLauncher.RmanHeader]::Parse((New-RmanManifestBytes (New-GameManifestBody) 2 2)) } | Should Throw 'version 2.2'
        { [HexLauncher.RmanHeader]::Parse((New-RmanManifestBytes (New-GameManifestBody) 3 0)) } | Should Throw 'version 3.0'
    }

    It 'refuse un fichier qui ne commence pas par RMAN' {
        { [HexLauncher.RmanHeader]::Parse([Text.Encoding]::ASCII.GetBytes('PAS UN MANIFEST RIOT, 28 octets et plus')) } | Should Throw 'en-tête absent'
    }

    It 'refuse un fichier vide ou tronqué avant la fin de l''en-tête' {
        { [HexLauncher.RmanHeader]::Parse([byte[]]@()) } | Should Throw 'en-tête absent'
        { [HexLauncher.RmanHeader]::Parse([Text.Encoding]::ASCII.GetBytes('RMAN')) } | Should Throw 'en-tête absent'
    }

    It 'refuse un corps annoncé au-delà de la fin du fichier' {
        $bytes = New-RmanManifestBytes (New-GameManifestBody)
        { [HexLauncher.RmanHeader]::Parse($bytes[0..($bytes.Length - 2)]) } | Should Throw 'hors du fichier'
    }
}

Describe 'RmanManifest.Parse' {
    $manifest = [HexLauncher.RmanManifest]::Parse((New-GameManifestBody))

    It 'reconstruit le chemin complet d''un fichier à partir de ses répertoires' {
        $file = $manifest.FindFile('DATA/FINAL/Localized/Global.fr_FR.wad.client')
        $file.Path | Should Be 'DATA/FINAL/Localized/Global.fr_FR.wad.client'
        $file.Size | Should Be 380
        $manifest.FindFile('DATA/FINAL/UI.fr_FR.wad.client').Size | Should Be 130
        $manifest.FileCount | Should Be 3
    }

    It 'trouve un fichier sans tenir compte de la casse ni du séparateur Windows' {
        $manifest.FindFile('data\final\localized\GLOBAL.FR_FR.wad.client').Size | Should Be 380
    }

    It 'rend null pour un fichier absent du manifest' {
        $manifest.FindFile('DATA/FINAL/Localized/Global.ko_KR.wad.client') | Should BeNullOrEmpty
    }

    It 'rattache chaque fichier à sa langue par le masque' {
        $file = $manifest.FindFile('DATA/FINAL/Localized/Global.fr_FR.wad.client')
        $manifest.HasLanguage($file, 'fr_FR') | Should Be $true
        $manifest.HasLanguage($file, 'ja_JP') | Should Be $false
        $manifest.HasLanguage($file, 'xx_XX') | Should Be $false
        $manifest.Languages[[byte]19] | Should Be 'ja_JP'
    }

    It 'place chaque chunk dans son bundle à la somme des tailles compressées qui le précèdent' {
        $chunks = $manifest.GetChunks($manifest.FindFile('DATA/FINAL/UI.fr_FR.wad.client'))
        @($chunks | ForEach-Object { '{0}@{1}+{2}>{3}' -f $_.BundleIdHex, $_.BundleOffset, $_.CompressedSize, $_.UncompressedSize }) -join ' ' |
            Should Be '00000000000000B2@0+70>90 00000000000000B1@150+20>40'
    }

    It 'rend les chunks dans l''ordre de reconstruction du fichier' {
        $chunks = $manifest.GetChunks($manifest.FindFile('DATA/FINAL/Localized/Global.fr_FR.wad.client'))
        @($chunks | ForEach-Object { $_.ChunkId }) -join ',' | Should Be '193,194'
        ($chunks | Measure-Object UncompressedSize -Sum).Sum | Should Be 380
    }

    It 'lit le type de hash des chunks (4 = BLAKE3)' {
        $manifest.HashType | Should Be 4
    }

    It 'rend un type de hash 0 sans table de paramètres' {
        $builder = New-Object HexLauncher.Tests.RmanBodyBuilder
        [HexLauncher.RmanManifest]::Parse($builder.AddLanguage(1, 'windows').Build()).HashType | Should Be 0
    }

    It 'refuse un fichier dont un chunk n''appartient à aucun bundle' {
        $builder = New-Object HexLauncher.Tests.RmanBodyBuilder
        $body = $builder.AddFile(0, 'orphelin.bin', 10, 0, [uint64[]]@(0xDEAD)).Build()
        $orphan = [HexLauncher.RmanManifest]::Parse($body)
        { $orphan.GetChunks($orphan.FindFile('orphelin.bin')) } | Should Throw 'sans bundle'
    }

    It 'refuse un corps tronqué' {
        $body = New-GameManifestBody
        { [HexLauncher.RmanManifest]::Parse($body[0..200]) } | Should Throw 'illisible'
    }

    It 'refuse un fichier rattaché à un répertoire inconnu' {
        $builder = New-Object HexLauncher.Tests.RmanBodyBuilder
        { [HexLauncher.RmanManifest]::Parse($builder.AddFile(99, 'perdu.bin', 1, 0, [uint64[]]@()).Build()) } | Should Throw 'illisible'
    }

    It 'refuse une arborescence cyclique au lieu de boucler' {
        $builder = New-Object HexLauncher.Tests.RmanBodyBuilder
        [void]$builder.AddDirectory(1, 2, 'a').AddDirectory(2, 1, 'b').AddFile(1, 'boucle.bin', 1, 0, [uint64[]]@())
        { [HexLauncher.RmanManifest]::Parse($builder.Build()) } | Should Throw 'cyclique'
    }
}

Describe 'Manifest complet : en-tête, zstd, FlatBuffers' {
    It 'retrouve un fichier texte à partir des octets du .manifest' {
        Initialize-ZstdLibrary
        $bytes    = New-RmanManifestBytes (New-GameManifestBody)
        $header   = [HexLauncher.RmanHeader]::Parse($bytes)
        $body     = [HexLauncher.Zstd]::Decompress($bytes, $header.BodyOffset, $header.BodyCompressedLength, $header.BodyUncompressedLength)
        $manifest = [HexLauncher.RmanManifest]::Parse($body)
        $manifest.FindFile('DATA/FINAL/Localized/Global.ja_JP.wad.client').Size | Should Be 40
    }
}
