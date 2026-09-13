<#
.SYNOPSIS
    Tests Pester 3.4 de lib\theme.lib.ps1 — fabriques de contrôles thématisés, sans afficher de fenêtre.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\theme.lib.ps1')

Describe 'Get-ThemeColor' {
    It 'rend la couleur or du thème' {
        (Get-ThemeColor 'Gold').ToArgb() | Should Be ([System.Drawing.ColorTranslator]::FromHtml('#C8AA6E').ToArgb())
    }
}

Describe 'New-ThemedButton' {
    It 'produit un bouton plat à liseré or' {
        $button = New-ThemedButton 'Suivant' 10 20
        $button.FlatStyle | Should Be 'Flat'
        $button.FlatAppearance.BorderColor.ToArgb() | Should Be ((Get-ThemeColor 'Gold').ToArgb())
        $button.ForeColor.ToArgb() | Should Be ((Get-ThemeColor 'Gold').ToArgb())
    }

    It 'met en avant le bouton principal (fond or sombre, texte crème)' {
        $button = New-ThemedButton 'Appliquer' 10 20 110 34 $true
        $button.BackColor.ToArgb() | Should Be ((Get-ThemeColor 'GoldDark').ToArgb())
        $button.ForeColor.ToArgb() | Should Be ((Get-ThemeColor 'Cream').ToArgb())
    }
}

Describe 'New-ThemedTitle' {
    It 'met le titre en capitales, or et gras' {
        $title = New-ThemedTitle 'Applis compagnon' 0 0 300
        $title.Text | Should Be 'APPLIS COMPAGNON'
        $title.Font.Bold | Should Be $true
        $title.ForeColor.ToArgb() | Should Be ((Get-ThemeColor 'Gold').ToArgb())
    }
}

Describe 'New-ThemedCheckedListBox' {
    It 'coche au clic sur fond nuit' {
        $list = New-ThemedCheckedListBox 0 0 200 100
        $list.CheckOnClick | Should Be $true
        $list.BackColor.ToArgb() | Should Be ((Get-ThemeColor 'Background').ToArgb())
    }
}

Describe 'New-ThemedLog' {
    It 'est un journal multi-lignes en lecture seule' {
        $log = New-ThemedLog 0 0 200 100
        $log.Multiline | Should Be $true
        $log.ReadOnly | Should Be $true
    }
}

Describe 'New-ThemedCheckBox' {
    It 'se remplit d''or sombre une fois cochée, liseré or' {
        $box = New-ThemedCheckBox 'Option' 0 0 200
        $box.FlatStyle | Should Be 'Flat'
        $box.FlatAppearance.CheckedBackColor.ToArgb() | Should Be ((Get-ThemeColor 'GoldDark').ToArgb())
        $box.FlatAppearance.BorderColor.ToArgb() | Should Be ((Get-ThemeColor 'Gold').ToArgb())
    }
}

Describe 'New-ThemedField' {
    It 'est un encadré en lecture seule avec retour à la ligne' {
        $field = New-ThemedField 'C:\chemin' 0 0 300
        $field.ReadOnly | Should Be $true
        $field.Multiline | Should Be $true
        $field.WordWrap | Should Be $true
        $field.Text | Should Be 'C:\chemin'
    }
}

Describe 'New-ThemedForm' {
    It 'produit une fenêtre fixe au fond nuit avec l''icône du projet' {
        $form = New-ThemedForm 'Test' 300 200
        $form.FormBorderStyle | Should Be 'FixedSingle'
        $form.BackColor.ToArgb() | Should Be ((Get-ThemeColor 'Background').ToArgb())
        $form.Icon | Should Not BeNullOrEmpty
        $form.Dispose()
    }
}
