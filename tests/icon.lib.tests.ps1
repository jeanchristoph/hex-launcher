<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon.lib.ps1 — écriture et relecture de .ico (entrées PNG et DIB).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon.lib.ps1')
$ProjectIcoPath  = Join-Path $here '..\app\ico\flat\hex-launcher-fr.ico'
$FlagIconsScript = Join-Path $here '..\tools\make-flag-icons.ps1'

# Bitmap unie d'une couleur, un pixel témoin distinct en (1,1)
function New-TestBitmap([int]$Size, [string]$Fill = '#FF102030', [string]$Witness = '#FFFF8800') {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml($Fill)); $g.Dispose()
    $bmp.SetPixel(1, 1, [System.Drawing.ColorTranslator]::FromHtml($Witness))
    return $bmp
}

function New-TestEntries([int[]]$Sizes) {
    return @($Sizes | ForEach-Object { [PSCustomObject]@{ Size = $_; Bitmap = (New-TestBitmap $_) } })
}

function Remove-Entries([object[]]$Entries) { $Entries | ForEach-Object { $_.Bitmap.Dispose() } }

Describe 'Write-Ico / Read-IcoEntries' {
    $sizes = @(256, 128, 64, 48, 32, 16)

    It 'relit les six tailles écrites, dans l''ordre, y compris 256 codée 0 dans l''en-tête' {
        $path = Join-Path $TestDrive 'roundtrip.ico'
        $written = New-TestEntries $sizes
        Write-Ico $written $path
        Remove-Entries $written
        $read = Read-IcoEntries $path
        ($read | ForEach-Object { $_.Size }) -join ',' | Should Be ($sizes -join ',')
        Remove-Entries $read
    }

    It 'conserve les pixels et le format 32 bits avec alpha' {
        $path = Join-Path $TestDrive 'pixels.ico'
        $written = New-TestEntries @(32)
        Write-Ico $written $path
        Remove-Entries $written
        $read = Read-IcoEntries $path
        $read[0].Bitmap.GetPixel(1, 1).ToArgb() | Should Be ([System.Drawing.ColorTranslator]::FromHtml('#FFFF8800').ToArgb())
        $read[0].Bitmap.GetPixel(5, 5).ToArgb() | Should Be ([System.Drawing.ColorTranslator]::FromHtml('#FF102030').ToArgb())
        $read[0].Bitmap.PixelFormat | Should Be ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        Remove-Entries $read
    }

    It 'lit une icône du projet avec ses six tailles' {
        $read = Read-IcoEntries $ProjectIcoPath
        ($read | ForEach-Object { $_.Size } | Sort-Object -Descending) -join ',' | Should Be '256,128,64,48,32,16'
        Remove-Entries $read
    }

    It 'lit une icône à entrées DIB écrite par System.Drawing.Icon' {
        $path = Join-Path $TestDrive 'dib.ico'
        $stream = [IO.File]::Create($path)
        [System.Drawing.SystemIcons]::Information.Save($stream)
        $stream.Dispose()
        $read = Read-IcoEntries $path
        @($read).Count | Should BeGreaterThan 0
        $read[0].Bitmap.Width | Should Be $read[0].Size
        Remove-Entries $read
    }

    It 'refuse un fichier tronqué' {
        $path = Join-Path $TestDrive 'full.ico'
        $written = New-TestEntries @(16)
        Write-Ico $written $path
        Remove-Entries $written
        $bytes = [IO.File]::ReadAllBytes($path)
        $truncated = Join-Path $TestDrive 'truncated.ico'
        [IO.File]::WriteAllBytes($truncated, $bytes[0..($bytes.Length - 20)])
        { Read-IcoEntries $truncated } | Should Throw
    }

    It 'refuse un fichier qui n''est pas un .ico' {
        $path = Join-Path $TestDrive 'not-an-icon.ico'
        [IO.File]::WriteAllBytes($path, [byte[]](1..40))
        { Read-IcoEntries $path } | Should Throw
    }

    It 'accepte un chemin relatif au dossier courant PowerShell' {
        Push-Location $TestDrive
        try {
            $written = New-TestEntries @(16)
            Write-Ico $written 'relative.ico'
            Remove-Entries $written
            $read = Read-IcoEntries 'relative.ico'
            $read[0].Size | Should Be 16
            Remove-Entries $read
        }
        finally { Pop-Location }
    }

    It 'refuse un fichier introuvable' {
        { Read-IcoEntries (Join-Path $TestDrive 'absent.ico') } | Should Throw
    }
}

Describe 'make-flag-icons.ps1 avec la lib .ico' {
    It 'génère toujours une icône drapeau relisible en six tailles' {
        $out = Join-Path $TestDrive 'ico'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        & $FlagIconsScript -Locales fr_FR -OutDir $out | Out-Null
        $read = Read-IcoEntries (Join-Path $out 'hex-launcher-fr.ico')
        @($read).Count | Should Be 6
        Remove-Entries $read
    }
}
