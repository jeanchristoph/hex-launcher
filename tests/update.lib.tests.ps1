<#
.SYNOPSIS
    Tests Pester 3.4 de lib\update.lib.ps1 : versions, réponse de l'API GitHub, version refusée, décision.
    Aucun appel réseau : la requête est simulée par une tâche déjà terminée, en échec ou jamais finie.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\update.lib.ps1')

$Digest = 'a' * 64

function New-TestReleaseJson([string]$Tag = 'v0.4.0') {
    return [pscustomobject]@{
        tag_name = $Tag
        html_url = "https://github.com/jeanchristoph/hex-launcher/releases/tag/$Tag"
        assets   = @(
            [pscustomobject]@{ name = 'hex-launcher-setup-0.4.0.exe'; browser_download_url = 'https://example/setup.exe'; digest = "sha256:$Digest" },
            [pscustomobject]@{ name = 'hex-launcher-portable-0.4.0.zip'; browser_download_url = 'https://example/portable.zip'; digest = $null })
    }
}

function New-TestRequest([System.Threading.Tasks.Task]$Task) {
    return @{ Client = (New-Object System.Net.WebClient); Task = $Task; Chrono = [Diagnostics.Stopwatch]::StartNew() }
}

function New-CompletedTask([string]$Body) {
    return [System.Threading.Tasks.Task]::FromResult($Body)
}

function New-FailedTask {
    $source = New-Object 'System.Threading.Tasks.TaskCompletionSource[string]'
    $source.SetException((New-Object System.Net.WebException('réseau indisponible')))
    return $source.Task
}

function New-PendingTask {
    return (New-Object 'System.Threading.Tasks.TaskCompletionSource[string]').Task
}

Describe 'ConvertTo-ReleaseVersion / Test-NewerVersion' {
    It 'retire le v du tag' {
        ConvertTo-ReleaseVersion 'v0.4.0' | Should Be '0.4.0'
        ConvertTo-ReleaseVersion '1.2.3' | Should Be '1.2.3'
    }

    It 'rend vide pour un tag qui n''est pas une version x.y.z' {
        ConvertTo-ReleaseVersion 'nightly' | Should Be ''
        ConvertTo-ReleaseVersion '' | Should Be ''
    }

    It 'compare les versions nombre par nombre, pas comme du texte' {
        Test-NewerVersion '0.10.0' '0.9.9' | Should Be $true
        Test-NewerVersion '0.3.2' '0.3.2' | Should Be $false
        Test-NewerVersion '0.3.1' '0.3.2' | Should Be $false
    }

    It 'rend faux sur une version illisible' {
        Test-NewerVersion 'abc' '0.3.2' | Should Be $false
    }
}

Describe 'ConvertTo-LatestRelease' {
    It 'relève la version, la page et les pièces jointes avec leur empreinte SHA-256' {
        $release = ConvertTo-LatestRelease (New-TestReleaseJson)
        $release.Version | Should Be '0.4.0'
        $release.PageUrl | Should Match 'releases/tag/v0\.4\.0$'
        $release.Assets.Count | Should Be 2
        $release.Assets[0].Sha256 | Should Be $Digest
    }

    It 'laisse l''empreinte vide quand GitHub n''en publie pas' {
        (ConvertTo-LatestRelease (New-TestReleaseJson)).Assets[1].Sha256 | Should Be ''
    }

    It 'rend $null pour un tag qui n''est pas une version ou une réponse vide' {
        ConvertTo-LatestRelease (New-TestReleaseJson 'nightly') | Should BeNullOrEmpty
        ConvertTo-LatestRelease $null | Should BeNullOrEmpty
    }
}

Describe 'Receive-LatestRelease' {
    It 'rend la release quand GitHub a répondu' {
        $body = New-TestReleaseJson | ConvertTo-Json -Depth 4
        (Receive-LatestRelease (New-TestRequest (New-CompletedTask $body))).Version | Should Be '0.4.0'
    }

    It 'rend $null sans exception quand le réseau est indisponible' {
        Receive-LatestRelease (New-TestRequest (New-FailedTask)) | Should BeNullOrEmpty
    }

    It 'n''attend pas au-delà du délai imparti' {
        $chrono = [Diagnostics.Stopwatch]::StartNew()
        Receive-LatestRelease (New-TestRequest (New-PendingTask)) 200 | Should BeNullOrEmpty
        $chrono.ElapsedMilliseconds | Should BeLessThan 1500
    }

    It 'rend $null pour une réponse illisible ou une requête qui n''est pas partie' {
        Receive-LatestRelease (New-TestRequest (New-CompletedTask '<html>limite atteinte</html>')) | Should BeNullOrEmpty
        Receive-LatestRelease $null | Should BeNullOrEmpty
    }
}

Describe 'Read-SkippedVersion / Save-SkippedVersion' {
    It 'mémorise la version refusée et la relit' {
        $path = Join-Path $TestDrive 'update-state.json'
        Save-SkippedVersion $path '0.4.0'
        Read-SkippedVersion $path | Should Be '0.4.0'
    }

    It 'rend vide sans fichier ou avec un fichier illisible' {
        Read-SkippedVersion (Join-Path $TestDrive 'absent.json') | Should Be ''
        $broken = Join-Path $TestDrive 'broken.json'
        Set-Content $broken '{ pas du json'
        Read-SkippedVersion $broken | Should Be ''
    }
}

Describe 'Test-UpdateOffered' {
    $release = ConvertTo-LatestRelease (New-TestReleaseJson)

    It 'propose une version plus récente que celle installée' {
        Test-UpdateOffered $release '0.3.2' '' | Should Be $true
    }

    It 'ne propose rien quand la version installée est à jour ou plus récente' {
        Test-UpdateOffered $release '0.4.0' '' | Should Be $false
        Test-UpdateOffered $release '0.5.0' '' | Should Be $false
    }

    It 'ne repropose pas la version refusée avec « Ne plus me demander »' {
        Test-UpdateOffered $release '0.3.2' '0.4.0' | Should Be $false
    }

    It 'propose de nouveau une version plus récente que celle refusée' {
        Test-UpdateOffered $release '0.3.2' '0.3.3' | Should Be $true
    }

    It 'ne propose rien sans release' {
        Test-UpdateOffered $null '0.3.2' '' | Should Be $false
    }
}

Describe 'Get-OfferedUpdate' {
    $body = New-TestReleaseJson | ConvertTo-Json -Depth 4

    It 'rend la release à proposer' {
        $check = @{ Request = (New-TestRequest (New-CompletedTask $body)); InstalledVersion = '0.3.2'; StatePath = (Join-Path $TestDrive 'aucun.json') }
        (Get-OfferedUpdate $check).Version | Should Be '0.4.0'
    }

    It 'rend $null pour la version refusée' {
        $state = Join-Path $TestDrive 'refus.json'
        Save-SkippedVersion $state '0.4.0'
        $check = @{ Request = (New-TestRequest (New-CompletedTask $body)); InstalledVersion = '0.3.2'; StatePath = $state }
        Get-OfferedUpdate $check | Should BeNullOrEmpty
    }
}

Describe 'Get-InstalledVersion' {
    It 'lit app\version.txt' {
        Get-InstalledVersion (Join-Path $here '..\app') | Should Match '^\d+\.\d+\.\d+$'
    }
}
