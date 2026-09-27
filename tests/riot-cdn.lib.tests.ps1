<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-cdn.lib.ps1 — plages de chunks, téléchargement mocké, reconstruction d'un fichier.

.DESCRIPTION
    Aucune requête réseau : Invoke-RiotCdnRangeRequest est mocké par un CDN en mémoire dont les bundles sont
    faits de trames zstd synthétiques.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')
. (Join-Path $here '..\app\lib\zstd.lib.ps1')
. (Join-Path $here '..\app\lib\riot-cdn.lib.ps1')
. (Join-Path $here 'zstd-test-helpers.ps1')
Initialize-ZstdLibrary

$BaseUrl = 'https://lol.secure.dyn.riotcdn.net/'

# CDN en mémoire : bundles (id → octets) et chunks (tels que RmanManifest.GetChunks les rend) d'un fichier
function New-FakeCdn([string[]]$Parts, [string[]]$BundleOfPart) {
    $bundles = @{}
    $chunks  = @()
    for ($i = 0; $i -lt $Parts.Count; $i++) {
        $frame  = New-ZstdRawFrame ([Text.Encoding]::ASCII.GetBytes($Parts[$i]))
        $bundle = $BundleOfPart[$i]
        if (-not $bundles.ContainsKey($bundle)) { $bundles[$bundle] = New-Object Collections.Generic.List[byte] }
        $chunks += [PSCustomObject]@{ BundleIdHex = $bundle; BundleOffset = [long]$bundles[$bundle].Count; CompressedSize = $frame.Length; UncompressedSize = $Parts[$i].Length }
        $bundles[$bundle].AddRange($frame)
    }
    return [PSCustomObject]@{ Bundles = $bundles; Chunks = $chunks; Content = ($Parts -join '') }
}

function Get-FakeCdnRange($Cdn, [string]$Url, $Range) {
    $bundle = $Cdn.Bundles[($Url -replace '^.*/([0-9A-F]+)\.bundle$', '$1')].ToArray()
    return [PSCustomObject]@{ StatusCode = 206; Bytes = (Get-RangeSlice $bundle $Range) }
}

Describe 'Get-RiotCdnBaseUrl' {
    It 'garde le schéma et l''hôte de l''URL du manifest lue dans Game.ok' {
        Get-RiotCdnBaseUrl 'https://lol.secure.dyn.riotcdn.net/channels/public/releases/5F25926EF18E78E7.manifest' |
            Should Be 'https://lol.secure.dyn.riotcdn.net/'
    }

    It 'refuse un hôte qui n''est pas le CDN Riot' {
        { Get-RiotCdnBaseUrl 'https://exemple.com/channels/public/releases/X.manifest' } | Should Throw 'hôte non reconnu'
        { Get-RiotCdnBaseUrl 'https://riotcdn.net.exemple.com/X.manifest' } | Should Throw 'hôte non reconnu'
    }

    It 'refuse le HTTP en clair et une URL invalide' {
        { Get-RiotCdnBaseUrl 'http://lol.dyn.riotcdn.net/channels/public/releases/X.manifest' } | Should Throw 'hôte non reconnu'
        { Get-RiotCdnBaseUrl 'pas une url' } | Should Throw 'invalide'
        { Get-RiotCdnBaseUrl '' } | Should Throw 'invalide'
    }
}

Describe 'Group-RiotCdnChunkRanges' {
    It 'fusionne les chunks contigus d''un même bundle en une seule plage' {
        $cdn = New-FakeCdn @('aaaa', 'bbbb', 'cccc') @('B1', 'B1', 'B1')
        $ranges = @(Group-RiotCdnChunkRanges $cdn.Chunks)
        $ranges.Count | Should Be 1
        $ranges[0].Chunks.Count | Should Be 3
        $ranges[0].Length | Should Be ($cdn.Bundles['B1'].Count)
    }

    It 'sépare les chunks de bundles différents, dans l''ordre du fichier' {
        $cdn = New-FakeCdn @('aaaa', 'bbbb', 'cccc') @('B1', 'B2', 'B1')
        @(Group-RiotCdnChunkRanges $cdn.Chunks | ForEach-Object { '{0}@{1}' -f $_.BundleIdHex, $_.Start }) -join ' ' |
            Should Be ('B1@0 B2@0 B1@{0}' -f $cdn.Chunks[2].BundleOffset)
    }

    It 'sépare deux chunks non contigus d''un même bundle' {
        $cdn = New-FakeCdn @('aaaa', 'bbbb', 'cccc') @('B1', 'B1', 'B1')
        @(Group-RiotCdnChunkRanges @($cdn.Chunks[0], $cdn.Chunks[2])).Count | Should Be 2
    }

    It 'rend une liste vide sans chunk' {
        @(Group-RiotCdnChunkRanges @()).Count | Should Be 0
    }
}

Describe 'Get-RangeSlice' {
    It 'découpe la plage demandée dans un bundle rendu en entier (réponse 200)' {
        $bytes = [byte[]](0..9)
        (Get-RangeSlice $bytes ([PSCustomObject]@{ Start = 3; Length = 4 })) -join ',' | Should Be '3,4,5,6'
    }

    It 'refuse une réponse plus courte que la plage' {
        { Get-RangeSlice ([byte[]](0..9)) ([PSCustomObject]@{ Start = 8; Length = 4 }) } | Should Throw 'plus courte'
    }
}

Describe 'Save-RiotCdnFile' {
    It 'reconstruit le fichier à partir de chunks répartis sur plusieurs bundles' {
        $cdn = New-FakeCdn @('Global ', 'fr_FR ', 'texte') @('B1', 'B1', 'B2')
        Mock Invoke-RiotCdnRangeRequest { Get-FakeCdnRange $cdn $Url $Range }
        $destination = Join-Path $TestDrive 'Global.fr_FR.wad.client'
        Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = $cdn.Content.Length; Destination = $destination })
        [IO.File]::ReadAllText($destination) | Should Be 'Global fr_FR texte'
        Assert-MockCalled Invoke-RiotCdnRangeRequest -Scope It -Exactly 2
        Assert-MockCalled Invoke-RiotCdnRangeRequest -Scope It -Exactly 1 -ParameterFilter { $Url -eq 'https://lol.secure.dyn.riotcdn.net/channels/public/bundles/B2.bundle' }
    }

    It 'rejoue une plage après une erreur réseau passagère' {
        $cdn = New-FakeCdn @('texte') @('B1')
        $script:failures = 1
        Mock Invoke-RiotCdnRangeRequest {
            if ($script:failures-- -gt 0) { throw 'délai dépassé' }
            Get-FakeCdnRange $cdn $Url $Range
        }
        $destination = Join-Path $TestDrive 'rejoue.bin'
        Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = 5; Destination = $destination })
        [IO.File]::ReadAllText($destination) | Should Be 'texte'
        Assert-MockCalled Invoke-RiotCdnRangeRequest -Scope It -Exactly 2
    }

    It 'abandonne après trois échecs sans laisser de fichier (hors ligne)' {
        $cdn = New-FakeCdn @('texte') @('B1')
        Mock Invoke-RiotCdnRangeRequest { throw 'Impossible de résoudre le nom distant' }
        $destination = Join-Path $TestDrive 'hors-ligne.bin'
        { Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = 5; Destination = $destination }) } | Should Throw 'nom distant'
        Assert-MockCalled Invoke-RiotCdnRangeRequest -Scope It -Exactly $RiotCdnMaxAttempts
        Test-Path $destination | Should Be $false
        Test-Path ($destination + '.part') | Should Be $false
    }

    It 'refuse un fichier reconstruit dont la taille diffère du manifest' {
        $cdn = New-FakeCdn @('texte') @('B1')
        Mock Invoke-RiotCdnRangeRequest { Get-FakeCdnRange $cdn $Url $Range }
        $destination = Join-Path $TestDrive 'taille.bin'
        { Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = 6; Destination = $destination }) } | Should Throw '6 attendus'
        Test-Path $destination | Should Be $false
    }

    It 'refuse une réponse tronquée' {
        $cdn = New-FakeCdn @('texte') @('B1')
        Mock Invoke-RiotCdnRangeRequest { [PSCustomObject]@{ StatusCode = 206; Bytes = [byte[]](1, 2, 3) } }
        $destination = Join-Path $TestDrive 'tronque.bin'
        { Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = 5; Destination = $destination }) } | Should Throw 'octets reçus'
        Test-Path $destination | Should Be $false
    }

    It 'refuse un chunk dont la taille décompressée diffère du manifest' {
        $cdn = New-FakeCdn @('texte') @('B1')
        $cdn.Chunks[0].UncompressedSize = 4
        Mock Invoke-RiotCdnRangeRequest { Get-FakeCdnRange $cdn $Url $Range }
        $destination = Join-Path $TestDrive 'chunk.bin'
        { Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $cdn.Chunks; Size = 4; Destination = $destination }) } | Should Throw 'zstd'
        Test-Path $destination | Should Be $false
    }
}
