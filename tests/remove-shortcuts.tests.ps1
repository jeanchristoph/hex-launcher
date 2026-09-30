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

    It 'retire du menu Démarrer le raccourci « Hex Launcher » posé par l''installeur vers ce setup.bat' {
        $startMenu = New-TestDesktop
        $setup = New-TestShortcut $startMenu 'Hex Launcher' $setupBatch
        @(Remove-OwnShortcuts $startMenu).Count | Should Be 1
        Test-Path $setup | Should Be $false
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

Describe 'Remove-AllOwnShortcuts' {
    It 'nettoie le Bureau et le menu Démarrer, puis retire le dossier du menu devenu vide' {
        $Destination          = New-TestDesktop
        $StartMenuDestination = New-TestDesktop
        New-TestShortcut $Destination 'League of Legends JP' $powershell "-File `"$launcher`" -Locale ja_JP" | Out-Null
        New-TestShortcut $StartMenuDestination 'League of Legends JP' $powershell "-File `"$launcher`" -Locale ja_JP" | Out-Null
        New-TestShortcut $StartMenuDestination 'Hex Launcher' $setupBatch | Out-Null
        @(Remove-AllOwnShortcuts).Count | Should Be 3
        Test-Path $StartMenuDestination | Should Be $false
        Test-Path $Destination | Should Be $true
    }

    It 'garde le dossier du menu Démarrer quand un raccourci d''une autre copie y reste' {
        $Destination          = New-TestDesktop
        $StartMenuDestination = New-TestDesktop
        New-TestShortcut $StartMenuDestination 'League of Legends FR' $powershell '-File "D:\portable\app\launch-lol.ps1" -Locale fr_FR' | Out-Null
        @(Remove-AllOwnShortcuts).Count | Should Be 0
        Test-Path $StartMenuDestination | Should Be $true
    }
}

Describe 'Remove-EmptyShortcutFolder' {
    It 'retire un dossier vide et laisse un dossier qui contient encore un fichier' {
        $empty = New-TestDesktop
        $full  = New-TestDesktop
        New-Item -ItemType File -Path (Join-Path $full 'autre.lnk') | Out-Null
        Remove-EmptyShortcutFolder $empty | Should Be $true
        Remove-EmptyShortcutFolder $full | Should Be $false
        Test-Path $empty | Should Be $false
        Test-Path $full | Should Be $true
    }

    It 'ne fait rien sur un dossier absent' {
        Remove-EmptyShortcutFolder (Join-Path $TestDrive 'absent') | Should Be $false
    }
}
