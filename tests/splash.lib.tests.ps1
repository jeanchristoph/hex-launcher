<#
.SYNOPSIS
    Tests Pester 3.4 de lib\splash.lib.ps1 — sans afficher de fenêtre.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\splash.lib.ps1')

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

Describe 'New-SplashRule' {
    It 'produit un filet doré de deux pixels ancré en haut' {
        $rule = New-SplashRule
        $rule.Height    | Should Be 2
        $rule.Dock      | Should Be 'Top'
        $rule.BackColor | Should Be (Get-ThemeColor 'Gold')
    }
}

Describe 'Add-SplashControls' {
    It 'pose le titre, le sous-titre, la barre et la ligne de statut — tous des contrôles réels, pas des textes' {
        $form = New-Object System.Windows.Forms.Form
        Add-SplashControls $form '日本語' 'LEAGUE OF LEGENDS'
        $labels = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })
        $labels.Count | Should Be 3
        @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] }).Count | Should Be 1
        ($labels | Where-Object { $_.Text -eq 'LEAGUE OF LEGENDS' }).Dock | Should Be 'Top'
        ($labels | Where-Object { $_.Text -eq '日本語' }).Dock          | Should Be 'Top'
    }

    It 'range la ligne de statut dans Tag, vide au départ' {
        $form = New-Object System.Windows.Forms.Form
        Add-SplashControls $form 'x' 'y'
        $form.Tag -is [System.Windows.Forms.Label] | Should Be $true
        $form.Tag.Text | Should Be ''
        $form.Tag.Dock | Should Be 'Fill'
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

Describe 'Add-SplashAction' {
    Mock Invoke-SplashTick {}

    function New-HiddenForm { $f = New-Object System.Windows.Forms.Form; $f.Size = New-Object System.Drawing.Size(420, 170); return $f }

    It 'pose un bouton caché, ancré en bas, avec le texte demandé' {
        $form = New-HiddenForm
        $button = Add-SplashAction $form 'Forcer en démarrage manuel' { }
        Test-SplashActionShown $form | Should Be $false
        $button.Dock | Should Be 'Bottom'
        $button.Text | Should Be 'Forcer en démarrage manuel'
        (Get-SplashAction $form) | Should Be $button
    }

    It 'ignore un splash absent' {
        Add-SplashAction $null 'x' { } | Should BeNullOrEmpty
        Get-SplashAction $null        | Should BeNullOrEmpty
    }
}

Describe 'Show-SplashAction et Hide-SplashAction' {
    Mock Invoke-SplashTick {}

    function New-FormWithAction { $f = New-Object System.Windows.Forms.Form; $f.Size = New-Object System.Drawing.Size(420, 170); Add-SplashAction $f 'x' { } | Out-Null; return $f }

    It 'fait apparaître le bouton et agrandit la fenêtre d''autant' {
        $form = New-FormWithAction
        Show-SplashAction $form | Should Be $true
        Test-SplashActionShown $form | Should Be $true
        $form.Height | Should Be (170 + $SplashActionHeight)
    }

    It 'n''agrandit qu''une fois, même demandé à chaque tick' {
        $form = New-FormWithAction
        Show-SplashAction $form | Out-Null
        Show-SplashAction $form | Should Be $false
        $form.Height | Should Be (170 + $SplashActionHeight)
    }

    It 'cache le bouton et rend à la fenêtre sa taille' {
        $form = New-FormWithAction
        Show-SplashAction $form | Out-Null
        Hide-SplashAction $form | Should Be $true
        Test-SplashActionShown $form | Should Be $false
        $form.Height | Should Be 170
    }

    It 'ne fait rien sans bouton, ni sur un bouton déjà caché' {
        $form = New-Object System.Windows.Forms.Form
        Show-SplashAction $form | Should Be $false
        Test-SplashActionShown $form | Should Be $false
        Hide-SplashAction (New-FormWithAction) | Should Be $false
        { Show-SplashAction $null } | Should Not Throw
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
