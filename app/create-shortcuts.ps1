<#
.SYNOPSIS
    Crée les raccourcis « League of Legends XX » sur le Bureau — un par langue × appli compagnon choisies — avec les chemins de CETTE machine.

.DESCRIPTION
    Les .lnk contiennent des chemins absolus : après une copie du dossier sur un autre poste
    (ou un déplacement), il faut les régénérer.

    Les langues viennent de locales.json, les applis compagnon de la liste companionApps de config.json
    (remplie par detect-config.ps1 et manage-companion-app.ps1). Sans -Locales, une boîte de dialogue à
    cases à cocher permet de choisir langues et compagnons. Un raccourci est créé par combinaison :
    « League of Legends JP - Blitz » ; sans compagnon coché : « League of Legends JP ».
    Les raccourcis obsolètes (combinaisons décochées) sont retirés de la destination, pour qu'elle
    reflète toujours le dernier choix.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Locales ja_JP,ko_KR
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Locales ja_JP -Companions blitz,opgg
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Destination "D:\Jeux"
#>
param(
    # Codes de langue à installer (ex. ja_JP,fr_FR). Absent → boîte de dialogue.
    [string[]]$Locales,

    # Identifiants des applis compagnon (ex. blitz,opgg) parmi companionApps de config.json. Vide → sans compagnon.
    [string[]]$Companions,

    # Dossier où créer les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop')
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'lib\launch-config.lib.ps1')

$folder      = $PSScriptRoot
$launcher    = Join-Path $folder 'launch-lol.ps1'
$configPath  = Join-Path $folder 'config.json'
$localesPath = Join-Path $folder 'locales.json'
$powershell  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$defaultIcon = Join-Path $folder 'ico\hex-launcher.ico'
$shell       = New-Object -ComObject WScript.Shell

# ---------------------------------------------------------------- Catalogue

function Read-LocaleCatalog([string]$Path) {
    if (-not (Test-Path $Path)) { throw "locales.json introuvable : $Path" }
    return Read-JsonCatalog $Path
}

# ja_JP → "League of Legends JP" ; ja_JP + Blitz → "League of Legends JP - Blitz"
function Get-ShortcutName([string]$Code, $Companion) {
    $name = "League of Legends $($Code.Split('_')[1])"
    if ($Companion) { $name += " - $($Companion.name)" }
    return $name
}

# ja_JP → ico\hex-launcher-jp.ico (même convention que make-flag-icons.ps1)
function Get-FlagIconPath([string]$Code) {
    return Join-Path $folder "ico\hex-launcher-$($Code.Split('_')[1].ToLower()).ico"
}

# Icône drapeau de la langue si présente, sinon l'icône de base du projet
function Resolve-IconPath([string]$Code) {
    $flagIcon = Get-FlagIconPath $Code
    if (Test-Path $flagIcon) { return $flagIcon }
    return $defaultIcon
}

# Une combinaison = une langue et, optionnellement, une appli compagnon
function New-ShortcutCombination([string]$Code, $Companion) {
    return [pscustomobject]@{ Code = $Code; Companion = $Companion; Name = (Get-ShortcutName $Code $Companion) }
}

function Get-ShortcutCombinations([string[]]$Codes, [object[]]$CompanionApps) {
    $combinations = foreach ($code in $Codes) {
        if ($CompanionApps.Count -eq 0) { New-ShortcutCombination $code $null }
        foreach ($companion in $CompanionApps) { New-ShortcutCombination $code $companion }
    }
    return @($combinations | Where-Object { $null -ne $_ })
}

# ---------------------------------------------------------------- Raccourcis existants

# Raccourcis de la destination qui pointent sur notre lanceur, avec la langue et le compagnon lus dans leurs arguments
function Get-ExistingLaunchShortcuts([string]$Directory) {
    if (-not (Test-Path $Directory)) { return @() }
    $found = foreach ($file in Get-ChildItem -Path $Directory -Filter 'League of Legends*.lnk' -File -ErrorAction SilentlyContinue) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        if ($shortcut.Arguments -notmatch [regex]::Escape($launcher)) { continue }
        $code      = if ($shortcut.Arguments -match '-Locale\s+([a-z]{2}_[A-Z]{2})') { $Matches[1] } else { '' }
        $companion = if ($shortcut.Arguments -match '-Companion\s+(\S+)') { $Matches[1] } else { '' }
        [pscustomobject]@{ Path = $file.FullName; Code = $code; CompanionId = $companion }
    }
    return @($found | Where-Object { $null -ne $_ })
}

# ---------------------------------------------------------------- Dialogue de choix

# Pré-coche les langues déjà installées dans la destination ; sinon celles marquées "default"
function Get-PreselectedCodes([object[]]$Catalog, [object[]]$Existing) {
    $installed = @($Catalog | Where-Object { $code = $_.code; $Existing | Where-Object { $_.Code -eq $code } } | ForEach-Object { $_.code })
    if ($installed.Count -gt 0) { return $installed }
    return @($Catalog | Where-Object { $_.default } | ForEach-Object { $_.code })
}

# Pré-coche les compagnons déjà présents dans des raccourcis ; sinon toutes les applis de config.json
function Get-PreselectedShortcutCompanionIds([object[]]$CompanionApps, [object[]]$Existing) {
    $used = @($CompanionApps | Where-Object { $id = $_.id; $Existing | Where-Object { $_.CompanionId -eq $id } } | ForEach-Object { $_.id })
    if ($used.Count -gt 0 -or $Existing.Count -gt 0) { return $used }
    return @($CompanionApps | ForEach-Object { $_.id })
}

function New-PickerList([string]$Title, [int]$Top, [int]$Height, [object[]]$Items, [string[]]$Labels, [string[]]$Preselected) {
    $label          = New-Object System.Windows.Forms.Label
    $label.Text     = $Title
    $label.Location = New-Object System.Drawing.Point(12, $Top)
    $label.Size     = New-Object System.Drawing.Size(360, 22)

    $list              = New-Object System.Windows.Forms.CheckedListBox
    $list.Location     = New-Object System.Drawing.Point(12, ($Top + 24))
    $list.Size         = New-Object System.Drawing.Size(360, $Height)
    $list.CheckOnClick = $true
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $index = $list.Items.Add($Labels[$i])
        $list.SetItemChecked($index, ($Preselected -contains $Items[$i]))
    }
    return @{ Label = $label; List = $list }
}

function New-PickerButton([string]$Text, [int]$Left, [int]$Top, [string]$DialogResult) {
    $button              = New-Object System.Windows.Forms.Button
    $button.Text         = $Text
    $button.Location     = New-Object System.Drawing.Point($Left, $Top)
    $button.Size         = New-Object System.Drawing.Size(90, 30)
    $button.DialogResult = $DialogResult
    return $button
}

# Retourne @{ Codes = [langues cochées]; CompanionIds = [compagnons cochés] } ou $null si annulé
function Show-ShortcutPicker([object[]]$Catalog, [string[]]$PreselectedCodes, [object[]]$CompanionApps, [string[]]$PreselectedCompanionIds) {
    $companionRows = [Math]::Max(1, $CompanionApps.Count)
    $companionsTop = 56 + 24 + 300 + 12
    $buttonsTop    = $companionsTop + 24 + 24 * $companionRows + 20

    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = 'League of Legends — raccourcis à installer'
    $form.Size            = New-Object System.Drawing.Size(400, ($buttonsTop + 80))
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)

    $hint          = New-Object System.Windows.Forms.Label
    $hint.Text     = 'Un raccourci sera créé sur le Bureau par langue cochée, et par appli compagnon cochée.'
    $hint.Location = New-Object System.Drawing.Point(12, 12)
    $hint.Size     = New-Object System.Drawing.Size(360, 40)

    $locales    = New-PickerList 'Langues' 56 300 @($Catalog | ForEach-Object { $_.code }) @($Catalog | ForEach-Object { "$($_.code)   $($_.label)" }) $PreselectedCodes
    $companions = New-PickerList 'Applis compagnon (aucune cochée = raccourci sans compagnon)' $companionsTop (24 * $companionRows) @($CompanionApps | ForEach-Object { $_.id }) @($CompanionApps | ForEach-Object { $_.name }) $PreselectedCompanionIds
    $ok     = New-PickerButton 'Installer' 180 $buttonsTop 'OK'
    $cancel = New-PickerButton 'Annuler'   282 $buttonsTop 'Cancel'

    $form.Controls.AddRange(@($hint, $locales.Label, $locales.List, $companions.Label, $companions.List, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    if ($form.ShowDialog() -ne 'OK') { return $null }
    return @{
        Codes        = @($locales.List.CheckedIndices    | ForEach-Object { $Catalog[$_].code })
        CompanionIds = @($companions.List.CheckedIndices | ForEach-Object { $CompanionApps[$_].id })
    }
}

# ---------------------------------------------------------------- Vérification config

# Signale les chemins de config.json absents de cette machine — sans bloquer, le lanceur
# ignore lui-même une appli compagnon introuvable
function Test-LaunchConfig($Config) {
    if (-not (Test-Path $Config.riotClientPath)) {
        Write-Warning "riotClientPath introuvable : $($Config.riotClientPath) — corriger config.json"
    }
    if (-not (Test-Path $Config.productSettingsPath)) {
        Write-Warning "productSettingsPath introuvable : $($Config.productSettingsPath) — LoL est-il installé ?"
    }
    foreach ($app in @($Config.companionApps)) {
        if (-not (Test-Path $app.path)) {
            Write-Warning "Application compagnon '$($app.name)' introuvable : $($app.path) — elle sera ignorée au lancement (voir README.md)"
        }
    }
}

# ---------------------------------------------------------------- Raccourcis

function Get-LauncherArguments($Combination) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Locale $($Combination.Code)"
    if ($Combination.Companion) { $arguments += " -Companion $($Combination.Companion.id)" }
    return $arguments
}

function New-LaunchShortcut($Combination, [string]$Directory) {
    $path = [IO.Path]::Combine($Directory, "$($Combination.Name).lnk")
    $shortcut                  = $shell.CreateShortcut($path)
    $shortcut.TargetPath       = $powershell
    $shortcut.Arguments        = Get-LauncherArguments $Combination
    $shortcut.WorkingDirectory = $folder
    $shortcut.IconLocation     = "$(Resolve-IconPath $Combination.Code),0"
    $shortcut.WindowStyle      = 7   # Réduite : aucune console visible
    $shortcut.Description      = "Lance League of Legends en $($Combination.Code)$(if ($Combination.Companion) { " avec $($Combination.Companion.name)" })"
    $shortcut.Save()
    return $path
}

# Bureau en priorité ; si l'écriture y échoue (dossier protégé, OneDrive verrouillé, chemin absent),
# repli dans le dossier du script pour que l'installation aboutisse quand même
function New-LaunchShortcutWithFallback($Combination) {
    try {
        return New-LaunchShortcut $Combination $Destination
    } catch {
        Write-Warning "Impossible d'écrire dans $Destination ($($_.Exception.Message)) — repli dans $folder"
        return New-LaunchShortcut $Combination $folder
    }
}

# Retire les raccourcis de notre lanceur dont la combinaison n'est plus retenue
function Remove-ObsoleteShortcuts([object[]]$Existing, [object[]]$Wanted) {
    $wantedNames = @($Wanted | ForEach-Object { "$($_.Name).lnk" })
    foreach ($shortcut in $Existing) {
        if ($wantedNames -contains (Split-Path $shortcut.Path -Leaf)) { continue }
        Remove-Item -Path $shortcut.Path -Force
        "Retiré : $($shortcut.Path)"
    }
}

# Lancé via -File, "ja_JP,fr_FR" arrive en une seule chaîne : on découpe nous-mêmes
function Split-ListArgument([string[]]$Values) {
    return @($Values | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par install.ps1 ou les tests)

if ($MyInvocation.InvocationName -ne '.') {
    $catalog = Read-LocaleCatalog $localesPath
    $config  = Read-LaunchConfig $configPath
    Test-LaunchConfig $config
    $companionApps = @($config.companionApps)
    $existing      = Get-ExistingLaunchShortcuts $Destination

    if (-not $Locales) {
        $choice = Show-ShortcutPicker $catalog (Get-PreselectedCodes $catalog $existing) $companionApps (Get-PreselectedShortcutCompanionIds $companionApps $existing)
        if ($null -eq $choice) { "Annulé : aucun raccourci créé."; exit 2 }
        $Locales    = $choice.Codes
        $Companions = $choice.CompanionIds
    }

    $Locales    = Split-ListArgument $Locales
    $Companions = Split-ListArgument $Companions

    $unknown = @($Locales | Where-Object { $_ -notin $catalog.code })
    if ($unknown.Count -gt 0) { throw "Langue(s) inconnue(s) dans locales.json : $($unknown -join ', ')" }
    $unknownCompanions = @($Companions | Where-Object { -not (Find-LaunchCompanion $config $_) })
    if ($unknownCompanions.Count -gt 0) { throw "Appli(s) compagnon absente(s) de config.json : $($unknownCompanions -join ', ') — relancer install.bat" }
    if ($Locales.Count -eq 0) { "Aucune langue cochée : aucun raccourci créé."; exit 0 }

    $selectedCompanions = @($Companions | ForEach-Object { Find-LaunchCompanion $config $_ })
    $combinations = Get-ShortcutCombinations $Locales $selectedCompanions
    foreach ($combination in $combinations) {
        "Créé : $(New-LaunchShortcutWithFallback $combination)"
    }
    Remove-ObsoleteShortcuts $existing $combinations
}
