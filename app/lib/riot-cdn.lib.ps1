<#
.SYNOPSIS
    CDN public du patcher Riot : reconstruit un fichier du jeu à partir de ses chunks, téléchargés par plages HTTP.

.DESCRIPTION
    Chargé par dot-sourcing, après lib\launch-log.lib.ps1 et lib\zstd.lib.ps1 (Initialize-ZstdLibrary appelé) :
        . (Join-Path $PSScriptRoot 'lib\riot-cdn.lib.ps1')

    Un fichier du jeu est une suite de chunks zstd rangés dans des bundles
    (https://<hôte>/channels/public/bundles/<ID>.bundle). Les chunks contigus d'un même bundle sont demandés en
    une seule requête « Range » ; chaque chunk est décompressé et contrôlé à sa taille annoncée par le manifest.

    INVARIANT : seul un hôte HTTPS en *.riotcdn.net est contacté — l'URL vient de Game.ok, fichier que ce lanceur
    ne contrôle pas. INVARIANT : le fichier de destination n'apparaît qu'une fois complet et à la bonne taille ;
    tout échec lève une exception et ne laisse rien derrière lui.
#>

$RiotCdnHostSuffix       = '.riotcdn.net'
$RiotCdnBundlesPath      = 'channels/public/bundles/'
$RiotCdnMaxAttempts      = 3
$RiotCdnTimeoutMs        = 20000
$RiotCdnPartialContent   = 206

# https://lol.secure.dyn.riotcdn.net/channels/public/releases/X.manifest → https://lol.secure.dyn.riotcdn.net/
function Get-RiotCdnBaseUrl([string]$ManifestUrl) {
    $uri = $null
    if (-not [Uri]::TryCreate($ManifestUrl, [UriKind]::Absolute, [ref]$uri)) { throw "CDN : URL de manifest invalide « $ManifestUrl »" }
    if ($uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith($RiotCdnHostSuffix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CDN : hôte non reconnu « $($uri.Host) »"
    }
    return '{0}://{1}/' -f $uri.Scheme, $uri.Host
}

function Get-RiotCdnBundleUrl([string]$BaseUrl, [string]$BundleIdHex) {
    return '{0}{1}{2}.bundle' -f $BaseUrl, $RiotCdnBundlesPath, $BundleIdHex
}

# Plages à demander : une par suite de chunks contigus d'un même bundle, dans l'ordre du fichier
function Group-RiotCdnChunkRanges([object[]]$Chunks) {
    $ranges = New-Object Collections.Generic.List[object]
    $current = $null
    foreach ($chunk in $Chunks) {
        $isContiguous = $current -and $current.BundleIdHex -eq $chunk.BundleIdHex -and ($current.Start + $current.Length) -eq $chunk.BundleOffset
        if ($isContiguous) {
            $current.Length += $chunk.CompressedSize
            $current.Chunks.Add($chunk)
            continue
        }
        $current = [PSCustomObject]@{ BundleIdHex = $chunk.BundleIdHex; Start = [long]$chunk.BundleOffset; Length = [long]$chunk.CompressedSize; Chunks = (New-Object Collections.Generic.List[object]) }
        $current.Chunks.Add($chunk)
        $ranges.Add($current)
    }
    return $ranges.ToArray()   # @() sur une List[object] de PSCustomObject lève « types ne correspondent pas » en 5.1
}

# Une requête GET avec Range ; un serveur qui ignore la plage (200) rend le bundle entier, découpé ici
function Invoke-RiotCdnRangeRequest([string]$Url, $Range) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Timeout = $RiotCdnTimeoutMs
    $request.ReadWriteTimeout = $RiotCdnTimeoutMs
    $request.AddRange($Range.Start, $Range.Start + $Range.Length - 1)
    $response = $request.GetResponse()
    try {
        $buffer = New-Object IO.MemoryStream
        $response.GetResponseStream().CopyTo($buffer)
        $bytes = $buffer.ToArray()
        $isWholeBundle = [int]$response.StatusCode -ne $RiotCdnPartialContent
        if ($isWholeBundle) { $bytes = Get-RangeSlice $bytes $Range }
        return [PSCustomObject]@{ StatusCode = [int]$response.StatusCode; Bytes = $bytes }
    }
    finally { $response.Close() }
}

function Get-RangeSlice([byte[]]$Bytes, $Range) {
    if ($Range.Start + $Range.Length -gt $Bytes.Length) { throw 'CDN : réponse plus courte que la plage demandée' }
    $slice = New-Object byte[] $Range.Length
    [Array]::Copy($Bytes, $Range.Start, $slice, 0, $Range.Length)
    return , $slice
}

# Octets compressés d'une plage, $RiotCdnMaxAttempts essais ; la dernière erreur remonte telle quelle
function Receive-RiotCdnRange([string]$BaseUrl, $Range) {
    $url = Get-RiotCdnBundleUrl $BaseUrl $Range.BundleIdHex
    $logged = '{0}{1}.bundle [{2}+{3}]' -f $RiotCdnBundlesPath, $Range.BundleIdHex, $Range.Start, $Range.Length
    for ($attempt = 1; ; $attempt++) {
        $chrono = [Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-RiotCdnRangeRequest $url $Range
            if ($response.Bytes.Length -ne $Range.Length) { throw ('CDN : {0} octets reçus, {1} attendus' -f $response.Bytes.Length, $Range.Length) }
            Write-LaunchLogLine 'CDN' ('GET {0} -> {1} en {2}' -f $logged, $response.StatusCode, (Format-LaunchLogDuration $chrono)) | Out-Null
            return , $response.Bytes
        }
        catch {
            Write-LaunchLogLine 'CDN' ('GET {0} -> échec {1}/{2} : {3}' -f $logged, $attempt, $RiotCdnMaxAttempts, $_.Exception.Message) | Out-Null
            if ($attempt -ge $RiotCdnMaxAttempts) { throw }
        }
    }
}

# Chunks d'une plage décompressés, écrits à la suite dans le flux
function Write-RiotCdnRangeContent([IO.Stream]$Stream, [byte[]]$Compressed, $Range) {
    $offset = 0
    foreach ($chunk in $Range.Chunks) {
        $content = [HexLauncher.Zstd]::Decompress($Compressed, $offset, $chunk.CompressedSize, $chunk.UncompressedSize)
        $Stream.Write($content, 0, $content.Length)
        $offset += $chunk.CompressedSize
    }
}

<#
    Reconstruit un fichier : $Download = { BaseUrl, Chunks (RmanChunk, ordre du fichier), Size, Destination }.
    Écrit dans <Destination>.part puis renomme : un fichier interrompu n'est jamais pris pour un fichier complet.
#>
function Save-RiotCdnFile($Download) {
    $partial = $Download.Destination + '.part'
    try {
        $stream = [IO.File]::Create($partial)
        try {
            foreach ($range in @(Group-RiotCdnChunkRanges $Download.Chunks)) {
                Write-RiotCdnRangeContent $stream (Receive-RiotCdnRange $Download.BaseUrl $range) $range
            }
            if ($stream.Length -ne $Download.Size) { throw ('CDN : fichier reconstruit de {0} octets, {1} attendus' -f $stream.Length, $Download.Size) }
        }
        finally { $stream.Dispose() }
        Move-Item -LiteralPath $partial -Destination $Download.Destination -Force
    }
    catch {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        throw
    }
}
