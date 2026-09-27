<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-text-files.lib.ps1 — Game.ok, Game.manifest, cache des fichiers texte d'une locale.

.DESCRIPTION
    Dossier League of Legends factice sous TestDrive (Game.ok + Game.manifest synthétique) ; le CDN est mocké
    (Save-RiotCdnFile). Jamais l'installation Riot réelle, jamais le réseau.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')
. (Join-Path $here '..\app\lib\zstd.lib.ps1')
. (Join-Path $here '..\app\lib\riot-cdn.lib.ps1')
. (Join-Path $here '..\app\lib\riot-text-files.lib.ps1')
. (Join-Path $here 'zstd-test-helpers.ps1')
. (Join-Path $here 'rman-test-helpers.ps1')

$ManifestUrl = 'https://lol.secure.dyn.riotcdn.net/channels/public/releases/5F25926EF18E78E7.manifest'

# Dossier de jeu factice ; $GameOk remplace le contenu de Game.ok, $ManifestId l'id écrit dans Game.manifest
function New-TestLeagueFolder([string]$GameOk = "$ManifestUrl`r`nja_JP`r`nwindows", [uint64]$ManifestId = 0x5F25926EF18E78E7) {
    $folder = Join-Path $TestDrive ('League of Legends ' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null
    Set-Content -Path (Join-Path $folder 'Game.ok') -Value $GameOk -Encoding ASCII
    [IO.File]::WriteAllBytes((Join-Path $folder 'Game.manifest'), (New-RmanManifestBytes (New-GameManifestBody) 2 1 $ManifestId))
    return $folder
}

# CDN mocké : écrit un WAD factice de la taille annoncée
function Write-FakeWad($Download) {
    $content = New-Object byte[] $Download.Size
    $content[0] = [byte][char]'R'; $content[1] = [byte][char]'W'
    [IO.File]::WriteAllBytes($Download.Destination, $content)
}

Describe 'Read-InstalledGameRelease' {
    It 'lit l''URL, l''id du manifest installé et la locale active dans Game.ok' {
        $release = Read-InstalledGameRelease (New-TestLeagueFolder)
        $release.ManifestUrl | Should Be $ManifestUrl
        $release.ManifestIdHex | Should Be '5F25926EF18E78E7'
        $release.Locale | Should Be 'ja_JP'
    }

    It 'échoue sans Game.ok (jeu absent ou jamais installé)' {
        { Read-InstalledGameRelease (Join-Path $TestDrive 'absent') } | Should Throw 'introuvable'
    }

    It 'échoue sur un Game.ok dont la première ligne n''est pas une URL de manifest' {
        { Read-InstalledGameRelease (New-TestLeagueFolder "n'importe quoi`r`nja_JP") } | Should Throw 'illisible'
        { Read-InstalledGameRelease (New-TestLeagueFolder $ManifestUrl) } | Should Throw 'illisible'
    }
}

Describe 'Read-InstalledGameManifest' {
    Initialize-ZstdLibrary

    It 'lit le manifest local quand son id est celui de Game.ok' {
        $folder = New-TestLeagueFolder
        $manifest = Read-InstalledGameManifest $folder (Read-InstalledGameRelease $folder)
        $manifest.FindFile('DATA/FINAL/UI.fr_FR.wad.client').Size | Should Be 130
    }

    It 'refuse un Game.manifest d''une autre version que Game.ok (patch en cours)' {
        $folder = New-TestLeagueFolder -ManifestId 0x1111111111111111
        { Read-InstalledGameManifest $folder (Read-InstalledGameRelease $folder) } | Should Throw 'ne correspond pas'
    }
}

Describe 'Test-WadFile' {
    It 'reconnaît un fichier commençant par RW' {
        $path = Join-Path $TestDrive 'ok.wad.client'
        [IO.File]::WriteAllBytes($path, [byte[]](0x52, 0x57, 3, 1))
        Test-WadFile $path | Should Be $true
    }

    It 'refuse un autre contenu, un fichier trop court ou absent' {
        $path = Join-Path $TestDrive 'html.wad.client'
        Set-Content -Path $path -Value '<html>' -Encoding ASCII
        Test-WadFile $path | Should Be $false
        $short = Join-Path $TestDrive 'court.wad.client'
        [IO.File]::WriteAllBytes($short, [byte[]](0x52))
        Test-WadFile $short | Should Be $false
        Test-WadFile (Join-Path $TestDrive 'absent.wad.client') | Should Be $false
    }
}

Describe 'Get-ForcedTextFiles' {
    $ForcedTextCacheRoot = Join-Path $TestDrive 'cache'

    It 'télécharge Global et UI de la locale demandée dans le cache de la version installée' {
        Mock Save-RiotCdnFile { Write-FakeWad $Download }
        $folder = Get-ForcedTextFiles (New-TestLeagueFolder) 'fr_FR'
        $folder | Should Be (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\fr_FR')
        (Get-Item (Join-Path $folder 'Global.fr_FR.wad.client')).Length | Should Be 380
        (Get-Item (Join-Path $folder 'UI.fr_FR.wad.client')).Length | Should Be 130
        Assert-MockCalled Save-RiotCdnFile -Scope It -Exactly 2 -ParameterFilter { $Download.BaseUrl -eq 'https://lol.secure.dyn.riotcdn.net/' }
    }

    It 'réutilise le cache sans rien télécharger' {
        Mock Save-RiotCdnFile { throw 'le réseau ne doit pas être sollicité' }
        Get-ForcedTextFiles (New-TestLeagueFolder) 'fr_FR' | Should Be (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\fr_FR')
        Assert-MockCalled Save-RiotCdnFile -Scope It -Exactly 0
    }

    It 'purge le cache des versions précédentes après un téléchargement' {
        $stale = New-Item -ItemType Directory -Path (Join-Path $ForcedTextCacheRoot 'AAAAAAAAAAAAAAAA\fr_FR') -Force
        Remove-Item -LiteralPath (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7') -Recurse -Force
        Mock Save-RiotCdnFile { Write-FakeWad $Download }
        Get-ForcedTextFiles (New-TestLeagueFolder) 'fr_FR' | Out-Null
        Test-Path $stale.FullName | Should Be $false
        Test-Path (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\fr_FR\UI.fr_FR.wad.client') | Should Be $true
    }

    It 'échoue sur une locale absente du manifest' {
        Mock Save-RiotCdnFile { Write-FakeWad $Download }
        { Get-ForcedTextFiles (New-TestLeagueFolder) 'ko_KR' } | Should Throw 'absent du manifest'
    }

    It 'échoue si un des deux fichiers manque pour la locale (UI.ja_JP)' {
        Mock Save-RiotCdnFile { Write-FakeWad $Download }
        { Get-ForcedTextFiles (New-TestLeagueFolder) 'ja_JP' } | Should Throw 'UI.ja_JP.wad.client absent du manifest'
    }

    It 'refuse et efface un fichier reçu qui n''est pas un WAD' {
        $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-pas-wad'
        Mock Save-RiotCdnFile { Set-Content -Path $Download.Destination -Value '<html>' -Encoding ASCII }
        { Get-ForcedTextFiles (New-TestLeagueFolder) 'fr_FR' } | Should Throw 'pas un fichier WAD'
        Test-Path (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\fr_FR\Global.fr_FR.wad.client') | Should Be $false
    }

    It 'échoue hors ligne et laisse le cache incomplet pour le prochain lancement' {
        $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-hors-ligne'
        Mock Save-RiotCdnFile { throw 'Impossible de résoudre le nom distant' }
        { Get-ForcedTextFiles (New-TestLeagueFolder) 'fr_FR' } | Should Throw 'nom distant'
        Test-ForcedTextCacheComplete (Get-ForcedTextCacheFolder '5F25926EF18E78E7' 'fr_FR') 'fr_FR' | Should Be $false
    }

    It 'refuse un Game.ok qui désigne un autre hôte que le CDN Riot' {
        $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-hote'
        Mock Save-RiotCdnFile { Write-FakeWad $Download }
        { Get-ForcedTextFiles (New-TestLeagueFolder "https://exemple.com/releases/5F25926EF18E78E7.manifest`r`nja_JP") 'fr_FR' } | Should Throw 'hôte non reconnu'
        Assert-MockCalled Save-RiotCdnFile -Scope It -Exactly 0
    }
}
