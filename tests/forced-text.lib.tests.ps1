<#
.SYNOPSIS
    Tests Pester 3.4 de lib\forced-text.lib.ps1 — pose du texte forcé, sauvegarde par le cache, restauration.

.DESCRIPTION
    Exclusivement sur TestDrive : dossier League of Legends factice (Game.ok, Game\DATA\FINAL\…), cache et marqueur
    redirigés. Le CDN est mocké (Save-RiotCdnFile). Jamais l'installation Riot réelle.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-log.lib.ps1')
. (Join-Path $here '..\app\lib\zstd.lib.ps1')
. (Join-Path $here '..\app\lib\riot-cdn.lib.ps1')
. (Join-Path $here '..\app\lib\riot-text-files.lib.ps1')
. (Join-Path $here '..\app\lib\forced-text.lib.ps1')
. (Join-Path $here 'zstd-test-helpers.ps1')
. (Join-Path $here 'rman-test-helpers.ps1')

$ManifestUrl = 'https://lol.secure.dyn.riotcdn.net/channels/public/releases/5F25926EF18E78E7.manifest'

function Set-WadContent([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($Path, 'RW' + $Text)
}

function Get-WadContent([string]$Path) {
    return [IO.File]::ReadAllText($Path).Substring(2)
}

# Jeu factice installé en ja_JP : Game.ok, Game.manifest synthétique, Global et UI japonais
function New-TestLeagueInstall {
    $folder = Join-Path $TestDrive ('League of Legends ' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null
    Set-Content -Path (Join-Path $folder 'Game.ok') -Value "$ManifestUrl`r`nja_JP`r`nwindows" -Encoding ASCII
    [IO.File]::WriteAllBytes((Join-Path $folder 'Game.manifest'), (New-RmanManifestBytes (New-GameManifestBody)))
    Set-WadContent (Join-Path $folder 'Game\DATA\FINAL\Localized\Global.ja_JP.wad.client') 'global japonais'
    Set-WadContent (Join-Path $folder 'Game\DATA\FINAL\UI.ja_JP.wad.client') 'ui japonais'
    return $folder
}

function Get-GameText([string]$Folder) {
    return '{0} | {1}' -f (Get-WadContent (Join-Path $Folder 'Game\DATA\FINAL\Localized\Global.ja_JP.wad.client')),
                          (Get-WadContent (Join-Path $Folder 'Game\DATA\FINAL\UI.ja_JP.wad.client'))
}

# CDN mocké : le contenu reçu nomme le fichier demandé
function Write-FakeCdnWad($Download) {
    Set-WadContent $Download.Destination ('cdn ' + (Split-Path $Download.Destination -Leaf))
}

function New-ForcedTextRequest([string]$Folder, [string]$TextLocale = 'fr_FR') {
    return [PSCustomObject]@{ LeagueFolder = $Folder; VoiceLocale = 'ja_JP'; TextLocale = $TextLocale }
}

Describe 'Install-ForcedText' {
    $ForcedTextCacheRoot = Join-Path $TestDrive 'cache'
    $ForcedTextStatePath = Join-Path $TestDrive 'forced-text-state.json'
    Initialize-ZstdLibrary

    It 'pose le texte français sous les noms japonais du jeu' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        Get-GameText $game | Should Be 'cdn Global.fr_FR.wad.client | cdn UI.fr_FR.wad.client'
        Remove-Item $ForcedTextStatePath
    }

    It 'sauvegarde les fichiers japonais d''origine dans le cache de ja_JP' {
        Remove-Item (Join-Path $TestDrive 'cache') -Recurse -Force -ErrorAction SilentlyContinue
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        Install-ForcedText (New-ForcedTextRequest (New-TestLeagueInstall))
        Get-WadContent (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\ja_JP\Global.ja_JP.wad.client') | Should Be 'global japonais'
        Get-WadContent (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\ja_JP\UI.ja_JP.wad.client') | Should Be 'ui japonais'
        Remove-Item $ForcedTextStatePath
    }

    It 'écrit le marqueur de restauration avec la version et les deux locales' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        $state = Read-ForcedTextState
        '{0} {1} {2} {3}' -f $state.manifestId, $state.voiceLocale, $state.textLocale, ($state.leagueFolder -eq $game) |
            Should Be '5F25926EF18E78E7 ja_JP fr_FR True'
        Remove-Item $ForcedTextStatePath
    }

    It 'ne touche à rien si le téléchargement échoue (hors ligne)' {
        $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-hors-ligne'
        Mock Save-RiotCdnFile { throw 'Impossible de résoudre le nom distant' }
        $game = New-TestLeagueInstall
        { Install-ForcedText (New-ForcedTextRequest $game) } | Should Throw 'nom distant'
        Get-GameText $game | Should Be 'global japonais | ui japonais'
        Test-ForcedTextPending | Should Be $false
    }

    It 'refuse de poser tant qu''une restauration est en attente' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Set-Content -Path $ForcedTextStatePath -Value '{}'
        { Install-ForcedText (New-ForcedTextRequest $game) } | Should Throw 'restauration est en attente'
        Get-GameText $game | Should Be 'global japonais | ui japonais'
        Remove-Item $ForcedTextStatePath
    }

    It 'refuse de poser si la langue des voix n''est pas installée' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Remove-Item (Join-Path $game 'Game\DATA\FINAL\UI.ja_JP.wad.client')
        { Install-ForcedText (New-ForcedTextRequest $game) } | Should Throw 'absents du jeu'
        Test-ForcedTextPending | Should Be $false
    }

    It 'refuse une locale de texte absente du manifest sans rien modifier' {
        $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-ko'
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        { Install-ForcedText (New-ForcedTextRequest $game 'ko_KR') } | Should Throw 'absent du manifest'
        Get-GameText $game | Should Be 'global japonais | ui japonais'
        Test-ForcedTextPending | Should Be $false
    }
}

Describe 'Restore-ForcedText' {
    $ForcedTextCacheRoot = Join-Path $TestDrive 'cache-restauration'
    $ForcedTextStatePath = Join-Path $TestDrive 'restauration-state.json'
    Initialize-ZstdLibrary

    It 'rend false sans pose à restaurer' {
        Restore-ForcedText | Should Be $false
    }

    It 'remet les fichiers japonais d''origine depuis la sauvegarde, sans réseau, et efface le marqueur' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        Mock Save-RiotCdnFile { throw 'le réseau ne doit pas être sollicité' }
        Restore-ForcedText | Should Be $true
        Get-GameText $game | Should Be 'global japonais | ui japonais'
        Test-ForcedTextPending | Should Be $false
        Assert-MockCalled Save-RiotCdnFile -Scope It -Exactly 0 -ParameterFilter { $Download.Destination -like '*\ja_JP\*' }
    }

    It 'permet une nouvelle pose après restauration (deux lancements mixtes de suite)' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        Restore-ForcedText | Out-Null
        Install-ForcedText (New-ForcedTextRequest $game)
        Get-GameText $game | Should Be 'cdn Global.fr_FR.wad.client | cdn UI.fr_FR.wad.client'
        Restore-ForcedText | Out-Null
        Get-GameText $game | Should Be 'global japonais | ui japonais'
    }

    It 'retélécharge les fichiers japonais si un patch a changé le manifest depuis la pose' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        $patched = 'https://lol.secure.dyn.riotcdn.net/channels/public/releases/1111111111111111.manifest'
        Set-Content -Path (Join-Path $game 'Game.ok') -Value "$patched`r`nja_JP`r`nwindows" -Encoding ASCII
        $body = New-Object HexLauncher.Tests.RmanBodyBuilder
        [void]$body.AddLanguage(19, 'ja_JP').AddDirectory(10, 0, 'DATA').AddDirectory(11, 10, 'FINAL').AddDirectory(12, 11, 'Localized')
        [void]$body.AddBundle(0xB1, [uint64[]]@(0xC1, 10, 10, 0xC2, 10, 10))
        [void]$body.AddFile(12, 'Global.ja_JP.wad.client', 10, (1 -shl 18), [uint64[]]@(0xC1)).AddFile(11, 'UI.ja_JP.wad.client', 10, (1 -shl 18), [uint64[]]@(0xC2))
        [IO.File]::WriteAllBytes((Join-Path $game 'Game.manifest'), (New-RmanManifestBytes $body.Build() 2 1 0x1111111111111111))
        Restore-ForcedText | Should Be $true
        Get-GameText $game | Should Be 'cdn Global.ja_JP.wad.client | cdn UI.ja_JP.wad.client'
        Assert-MockCalled Save-RiotCdnFile -Scope It -Exactly 2 -ParameterFilter { $Download.Destination -like '*1111111111111111\ja_JP\*' }
    }

    It 'garde le marqueur si la restauration échoue, pour la retenter au lancement suivant' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        Remove-Item (Join-Path $ForcedTextCacheRoot '5F25926EF18E78E7\ja_JP') -Recurse -Force
        Mock Save-RiotCdnFile { throw 'Impossible de résoudre le nom distant' }
        { Restore-ForcedText } | Should Throw 'nom distant'
        Test-ForcedTextPending | Should Be $true
        Remove-Item $ForcedTextStatePath
    }

    It 'ne recrée pas un fichier que Riot a retiré (langue des voix désinstallée)' {
        Mock Save-RiotCdnFile { Write-FakeCdnWad $Download }
        $game = New-TestLeagueInstall
        Install-ForcedText (New-ForcedTextRequest $game)
        Remove-Item (Join-Path $game 'Game\DATA\FINAL\UI.ja_JP.wad.client')
        Restore-ForcedText | Should Be $true
        Test-Path (Join-Path $game 'Game\DATA\FINAL\UI.ja_JP.wad.client') | Should Be $false
        Get-WadContent (Join-Path $game 'Game\DATA\FINAL\Localized\Global.ja_JP.wad.client') | Should Be 'global japonais'
    }

    It 'efface le marqueur d''un jeu désinstallé sans rien copier' {
        Set-Content -Path $ForcedTextStatePath -Value ('{{ "leagueFolder": "{0}", "voiceLocale": "ja_JP" }}' -f ((Join-Path $TestDrive 'disparu') -replace '\\', '\\'))
        Restore-ForcedText | Should Be $true
        Test-ForcedTextPending | Should Be $false
    }
}
