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

Describe 'New-ThemedComboBox' {
    $items = @([pscustomobject]@{ Key = 'fr'; Label = 'Français' }, [pscustomobject]@{ Key = 'ja'; Label = '日本語' })

    It 'présélectionne la clé demandée et la retrouve sans fenêtre' {
        $combo = New-ThemedComboBox $items 'ja' 0 0 190
        $combo.DropDownStyle | Should Be 'DropDownList'
        $combo.Items.Count | Should Be 2
        $combo.SelectedIndex | Should Be 1
        Get-ThemedComboBoxKey $combo | Should Be 'ja'
    }

    It 'ne sélectionne rien pour une clé inconnue' {
        $combo = New-ThemedComboBox $items 'xx' 0 0 190
        $combo.SelectedIndex | Should Be -1
        Get-ThemedComboBoxKey $combo | Should BeNullOrEmpty
    }
}

Describe 'New-ThemedCheckBox' {
    It 'garde le carré natif de Windows, pour qu''une case décochée reste blanche' {
        $box = New-ThemedCheckBox 'Option' 0 0 200
        $box.FlatStyle | Should Be 'Standard'
    }

    It 'dessine un carré blanc tant que la case n''est pas cochée' {
        $box = New-ThemedCheckBox 'Option' 0 0 200
        $bitmap = New-Object Drawing.Bitmap(200, 26)
        try {
            $box.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, 200, 26)))
            $pixel = $bitmap.GetPixel(6, 13)
            "$($pixel.R),$($pixel.G),$($pixel.B)" | Should Be '255,255,255'
        } finally { $bitmap.Dispose() }
    }

    It 'garde le texte crème sur le fond nuit' {
        $box = New-ThemedCheckBox 'Option' 0 0 200
        $box.ForeColor.ToArgb() | Should Be ((Get-ThemeColor 'Cream').ToArgb())
        $box.BackColor.ToArgb() | Should Be ((Get-ThemeColor 'Background').ToArgb())
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
