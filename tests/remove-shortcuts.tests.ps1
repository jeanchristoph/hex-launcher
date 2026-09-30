<#
.SYNOPSIS
    Tests Pester 3.4 de app\remove-shortcuts.ps1 : retrait des raccourcis de ce lanceur à la désinstallation.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\remove-shortcuts.ps1')

function New-TestShortcut([string]$Directory, [string]$Name, [string]$Target, [string]$Arguments = '') {
    $path = [IO.Path]::Combine($Directory, "$Name.lnk")
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments  = $Arguments
    $shortcut.Save()
    return $path
}

function New-TestDesktop {
    $desktop = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    return $desktop
}

Describe 'Remove-OwnShortcuts' {
    It 'retire les raccourcis de jeu et « Hex Launcher » de ce lanceur' {
        $desktop = New-TestDesktop
        $game  = New-TestShortcut $desktop 'League of Legends JP' $powershell "-File `"$launcher`" -Locale ja_JP"
        $setup = New-TestShortcut $desktop 'Hex Launcher' $setupBatch
        $removed = Remove-OwnShortcuts $desktop
        $removed.Count | Should Be 2
        Test-Path $game | Should Be $false
        Test-Path $setup | Should Be $false
    }

    It 'laisse les raccourcis d''une autre copie de hex-launcher et les raccourcis étrangers' {
        $desktop = New-TestDesktop
        $otherGame  = New-TestShortcut $desktop 'League of Legends FR' $powershell '-File "D:\portable\app\launch-lol.ps1" -Locale fr_FR'
        $otherSetup = New-TestShortcut $desktop 'Hex Launcher' 'D:\portable\setup.bat'
        $foreign    = New-TestShortcut $desktop 'Notes' 'C:\Windows\notepad.exe'
        @(Remove-OwnShortcuts $desktop).Count | Should Be 0
        Test-Path $otherGame | Should Be $true
        Test-Path $otherSetup | Should Be $true
        Test-Path $foreign | Should Be $true
    }

    It 'rend une liste vide sur un Bureau vide ou absent' {
        @(Remove-OwnShortcuts (New-TestDesktop)).Count | Should Be 0
        @(Remove-OwnShortcuts (Join-Path $TestDrive 'absent')).Count | Should Be 0
    }

    It 'signale un raccourci verrouillé sans interrompre le retrait des autres' {
        $desktop = New-TestDesktop
        New-TestShortcut $desktop 'League of Legends JP' $powershell "-File `"$launcher`" -Locale ja_JP" | Out-Null
        Mock Remove-Item { throw 'verrouillé' }
        Mock Write-Warning {}
        @(Remove-OwnShortcuts $desktop).Count | Should Be 0
        Assert-MockCalled Write-Warning -Exactly 1 -Scope It
    }
}
