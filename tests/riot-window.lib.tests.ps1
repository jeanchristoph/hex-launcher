<#
.SYNOPSIS
    Tests Pester 3.4 de lib\riot-window.lib.ps1 : repérage et masquage de la fenêtre du Riot Client.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\riot-window.lib.ps1')

Describe 'Constantes de repérage' {
    It 'vise le process « Riot Client », pas RiotClientServices qui n''a jamais de fenêtre' {
        $RiotClientWindowProcessName | Should Be 'Riot Client'
    }

    It 'vise la fenêtre Chromium du client, relevée par énumération' {
        $RiotClientWindowClassName | Should Be 'Chrome_WidgetWin_1'
    }
}

Describe 'Find-RiotClientWindow' {
    It 'rend un handle nul quand aucune fenêtre ne correspond' {
        Mock Get-WindowClassName { return 'UneAutreClasse' }
        Mock Get-WindowProcessName { return 'explorer' }
        Find-RiotClientWindow | Should Be ([IntPtr]::Zero)
    }

    It 'ignore les fenêtres de la bonne classe portées par un autre programme' {
        Mock Get-WindowClassName { return 'Chrome_WidgetWin_1' }
        Mock Get-WindowProcessName { return 'chrome' }
        Find-RiotClientWindow | Should Be ([IntPtr]::Zero)
    }
}

Describe 'Close-RiotClientWindow' {
    It 'ne fait rien et ne se plaint pas quand aucune fenêtre n''est ouverte' {
        Mock Find-RiotClientWindow { return [IntPtr]::Zero }
        Close-RiotClientWindow | Should Be $false
    }

    It 'demande la fermeture de la fenêtre trouvée' {
        Mock Find-RiotClientWindow { return [IntPtr]4242 }
        Close-RiotClientWindow | Should Be $true
    }

    It 'rend faux sans lever d''exception quand Windows refuse' {
        Mock Find-RiotClientWindow { throw 'refus de l''API Windows' }
        { Close-RiotClientWindow } | Should Not Throw
        Close-RiotClientWindow | Should Be $false
    }
}
