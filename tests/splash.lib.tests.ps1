<#
.SYNOPSIS
    Tests Pester 3.4 de lib\splash.lib.ps1 — sans afficher de fenêtre.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\lib\splash.lib.ps1')

function New-FakeSplash { return [pscustomobject]@{ Tag = [pscustomobject]@{ Text = '' }; Visible = $true } }

Describe 'New-SplashLabel' {
    It 'centre le texte et applique couleur, police et hauteur' {
        $label = New-SplashLabel 'Titre' (New-Object System.Drawing.Font('Segoe UI', 12)) 'Gold' 'Top' 40
        $label.Text | Should Be 'Titre'
        $label.TextAlign | Should Be 'MiddleCenter'
        $label.Height | Should Be 40
        $label.ForeColor.ToArgb() | Should Be ([System.Drawing.ColorTranslator]::FromHtml('#C8AA6E').ToArgb())
    }

    It 'laisse la hauteur par défaut quand elle vaut 0 (Dock Fill)' {
        $label = New-SplashLabel '' (New-Object System.Drawing.Font('Segoe UI', 9)) 'Muted' 'Fill' 0
        $label.Dock | Should Be 'Fill'
    }
}

Describe 'New-SplashProgressBar' {
    It 'produit une barre marquee fine ancrée en haut' {
        $bar = New-SplashProgressBar
        $bar.Style | Should Be 'Marquee'
        $bar.Height | Should Be 6
        $bar.Dock | Should Be 'Top'
    }
}

Describe 'Update-SplashStatus' {
    Mock Invoke-SplashTick {}

    It 'écrit le texte dans la ligne de statut' {
        $splash = New-FakeSplash
        Update-SplashStatus $splash 'Lancement…'
        $splash.Tag.Text | Should Be 'Lancement…'
    }

    It 'ignore un splash absent' {
        { Update-SplashStatus $null 'x' } | Should Not Throw
    }
}

Describe 'Set-SplashVisible' {
    Mock Invoke-SplashTick {}

    It 'masque puis réaffiche' {
        $splash = New-FakeSplash
        Set-SplashVisible $splash $false
        $splash.Visible | Should Be $false
        Set-SplashVisible $splash $true
        $splash.Visible | Should Be $true
    }

    It 'ignore un splash absent' {
        { Set-SplashVisible $null $false } | Should Not Throw
    }
}

Describe 'Set-SplashTopMost' {
    Mock Invoke-SplashTick {}

    It 'commute le premier plan' {
        $splash = [pscustomobject]@{ Tag = $null; Visible = $true; TopMost = $true }
        Set-SplashTopMost $splash $false
        $splash.TopMost | Should Be $false
    }

    It 'ignore un splash absent' {
        { Set-SplashTopMost $null $false } | Should Not Throw
    }
}

Describe 'Close-SplashWindow' {
    It 'ignore un splash absent' {
        { Close-SplashWindow $null } | Should Not Throw
    }
}

Describe 'Wait-WithAnimation' {
    Mock Start-Sleep {}
    Mock Invoke-SplashTick {}

    It 'pompe les messages pendant l''attente' {
        Wait-WithAnimation 0.2
        Assert-MockCalled -Scope It Invoke-SplashTick
    }

    It 'rend la main immédiatement pour une durée nulle' {
        Wait-WithAnimation 0
        Assert-MockCalled -Scope It Invoke-SplashTick -Times 0
    }
}
