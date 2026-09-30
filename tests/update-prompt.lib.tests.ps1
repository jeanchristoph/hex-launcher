<#
.SYNOPSIS
    Tests Pester 3.4 de lib\update-prompt.lib.ps1 : fenêtre « Mise à jour disponible » (construite, jamais affichée).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $here '..\app\lib\i18n.lib.ps1')
. (Join-Path $here '..\app\lib\update-prompt.lib.ps1')
Initialize-Translation 'fr' | Out-Null

$Release = [pscustomobject]@{ Version = '0.4.0'; PageUrl = 'https://github.com/jeanchristoph/hex-launcher/releases/tag/v0.4.0'; Assets = @() }

Describe 'Resolve-UpdatePromptChoice' {
    It 'installe sur « Installer », sans mémoriser de refus même case cochée' {
        $choice = Resolve-UpdatePromptChoice ([System.Windows.Forms.DialogResult]::OK) $true
        $choice.Install | Should Be $true
        $choice.SkipVersion | Should Be $false
    }

    It 'mémorise le refus sur « Plus tard » case cochée' {
        $choice = Resolve-UpdatePromptChoice ([System.Windows.Forms.DialogResult]::Cancel) $true
        $choice.Install | Should Be $false
        $choice.SkipVersion | Should Be $true
    }

    It 'ne mémorise rien sur « Plus tard » case décochée ou fenêtre fermée' {
        (Resolve-UpdatePromptChoice ([System.Windows.Forms.DialogResult]::Cancel) $false).SkipVersion | Should Be $false
        (Resolve-UpdatePromptChoice ([System.Windows.Forms.DialogResult]::None) $false).Install | Should Be $false
    }
}

Describe 'New-UpdatePromptForm' {
    $form = New-UpdatePromptForm $Release '0.3.2'
    $texts = @($form.Controls | ForEach-Object { $_.Text })

    It 'annonce la nouvelle version et la version installée' {
        $form.Text | Should Be 'Mise à jour disponible'
        ($texts -join '|') | Should Match 'Hex Launcher 0\.4\.0 est disponible \(vous avez la 0\.3\.2\)'
    }

    It 'propose Installer, Plus tard, la case de refus et le lien vers les nouveautés' {
        $texts -contains 'Installer' | Should Be $true
        $texts -contains 'Plus tard' | Should Be $true
        $texts -contains 'Ne plus me demander jusqu''à la prochaine version' | Should Be $true
        $texts -contains 'Voir les nouveautés' | Should Be $true
    }

    It 'garde la case décochée par défaut et passe au premier plan' {
        $form.Tag.Checked | Should Be $false
        $form.TopMost | Should Be $true
    }

    It 'associe Entrée à Installer et Échap à Plus tard' {
        $form.AcceptButton.Text | Should Be 'Installer'
        $form.CancelButton.Text | Should Be 'Plus tard'
    }

    $form.Dispose()
}

Describe 'Confirm-UpdateInstall' {
    It 'mémorise la version refusée quand l''utilisateur le demande' {
        $state = Join-Path $TestDrive 'update-state.json'
        Mock Show-UpdatePrompt { @{ Install = $false; SkipVersion = $true } }
        Confirm-UpdateInstall $Release '0.3.2' $state | Should Be $false
        Read-SkippedVersion $state | Should Be '0.4.0'
    }

    It 'n''écrit rien et rend vrai quand l''utilisateur installe' {
        $state = Join-Path $TestDrive 'installe.json'
        Mock Show-UpdatePrompt { @{ Install = $true; SkipVersion = $false } }
        Confirm-UpdateInstall $Release '0.3.2' $state | Should Be $true
        Test-Path $state | Should Be $false
    }
}
