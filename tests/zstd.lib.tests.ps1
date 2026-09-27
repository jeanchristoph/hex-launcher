<#
.SYNOPSIS
    Tests Pester 3.4 de lib\zstd.lib.ps1 — libzstd.dll vérifiée puis chargée, décompression d'une trame.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\zstd.lib.ps1')
. (Join-Path $here 'zstd-test-helpers.ps1')

# « hex-launcher » × 32 (416 octets), compressé par zstd.exe 1.5.7 -19 : une vraie trame compressée
$CompressedSampleHex = '28b52ffd60a000a50000686865782d6c61756e6368657220010090a0ce2f'
$SampleText          = 'hex-launcher ' * 32

Describe 'Test-ZstdLibraryTrusted' {
    It 'accepte la DLL livrée : son empreinte est celle épinglée' {
        Test-ZstdLibraryTrusted $ZstdLibraryPath | Should Be $true
    }

    It 'refuse un fichier dont l''empreinte diffère' {
        $fake = Join-Path $TestDrive 'libzstd.dll'
        Set-Content -Path $fake -Value 'pas une dll'
        Test-ZstdLibraryTrusted $fake | Should Be $false
    }

    It 'refuse un chemin absent' {
        Test-ZstdLibraryTrusted (Join-Path $TestDrive 'absente.dll') | Should Be $false
    }

    It 'livre la licence BSD à côté de la DLL' {
        Test-Path $ZstdLicensePath | Should Be $true
    }
}

Describe 'Initialize-ZstdLibrary' {
    It 'refuse de charger une DLL dont l''empreinte diffère' {
        $script:ZstdLibraryLoaded = $false
        $ZstdLibraryPath = Join-Path $TestDrive 'libzstd.dll'
        Set-Content -Path $ZstdLibraryPath -Value 'pas une dll'
        { Initialize-ZstdLibrary } | Should Throw 'empreinte inattendue'
        $script:ZstdLibraryLoaded | Should Be $false
    }

    Context 'PowerShell 32 bits' {
        It 'refuse de charger la DLL x64' {
            $script:ZstdLibraryLoaded = $false
            Mock Test-ZstdProcessSupported { $false }
            { Initialize-ZstdLibrary } | Should Throw '64 bits'
        }
    }

    It 'charge la DLL livrée' {
        $script:ZstdLibraryLoaded = $false
        Initialize-ZstdLibrary
        $script:ZstdLibraryLoaded | Should Be $true
    }
}

Describe 'HexLauncher.Zstd.Decompress' {
    Initialize-ZstdLibrary

    It 'décompresse une trame produite par zstd.exe' {
        $frame = ConvertFrom-HexString $CompressedSampleHex
        $bytes = [HexLauncher.Zstd]::Decompress($frame, 0, $frame.Length, $SampleText.Length)
        [Text.Encoding]::ASCII.GetString($bytes) | Should Be $SampleText
    }

    It 'décompresse une trame lue au milieu d''un tampon (chunk dans une plage de bundle)' {
        $frame  = New-ZstdRawFrame ([Text.Encoding]::ASCII.GetBytes('chunk'))
        $buffer = [byte[]](@(1, 2, 3) + $frame + @(9, 9))
        $bytes  = [HexLauncher.Zstd]::Decompress($buffer, 3, $frame.Length, 5)
        [Text.Encoding]::ASCII.GetString($bytes) | Should Be 'chunk'
    }

    It 'décompresse une trame raw de plusieurs blocs' {
        $content = [byte[]](1..300000 | ForEach-Object { $_ % 251 })
        $frame   = New-ZstdRawFrame $content
        $bytes   = [HexLauncher.Zstd]::Decompress($frame, 0, $frame.Length, $content.Length)
        [Convert]::ToBase64String($bytes) | Should Be ([Convert]::ToBase64String($content))
    }

    It 'rejette une taille décompressée différente de celle attendue' {
        $frame = New-ZstdRawFrame ([Text.Encoding]::ASCII.GetBytes('chunk'))
        { [HexLauncher.Zstd]::Decompress($frame, 0, $frame.Length, 6) } | Should Throw 'attendus'
    }

    It 'rejette des octets qui ne sont pas une trame zstd' {
        $junk = [Text.Encoding]::ASCII.GetBytes('ceci n''est pas du zstd')
        { [HexLauncher.Zstd]::Decompress($junk, 0, $junk.Length, 10) } | Should Throw 'zstd'
    }

    It 'rejette une plage qui déborde du tampon' {
        $frame = New-ZstdRawFrame ([Text.Encoding]::ASCII.GetBytes('chunk'))
        { [HexLauncher.Zstd]::Decompress($frame, 1, $frame.Length, 5) } | Should Throw
    }
}
