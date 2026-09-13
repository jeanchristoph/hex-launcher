<#
.SYNOPSIS
    Crée les raccourcis « League of Legends XX » sur le Bureau, un par langue choisie, avec les chemins de CETTE machine.

.DESCRIPTION
    Les .lnk contiennent des chemins absolus : après une copie du dossier sur un autre poste
    (ou un déplacement), il faut les régénérer.

    Les langues disponibles viennent de locales.json. Sans -Locales, une boîte de dialogue
    à cases à cocher permet de choisir. Les raccourcis des langues non retenues sont supprimés
    de la destination, pour qu'elle reflète toujours le dernier choix.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Locales ja_JP,ko_KR
    powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Destination "D:\Jeux"
#>
param(
    # Codes de langue à installer (ex. ja_JP,fr_FR). Absent → boîte de dialogue.
    [string[]]$Locales,

    # Dossier où créer les raccourcis (défaut : Bureau de l'utilisateur courant)
    [string]$Destination = [Environment]::GetFolderPath('Desktop')
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$folder      = $PSScriptRoot
$launcher    = Join-Path $folder 'launch-lol.ps1'
$configPath  = Join-Path $folder 'config.json'
$localesPath = Join-Path $folder 'locales.json'
$powershell  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$defaultIcon = Join-Path $folder 'ico\league-of-legends.ico'
$shell       = New-Object -ComObject WScript.Shell

# ---------------------------------------------------------------- Catalogue

function Read-LocaleCatalog([string]$Path) {
    if (-not (Test-Path $Path)) { throw "locales.json introuvable : $Path" }
    return @(Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# ja_JP → "League of Legends JP"
function Get-ShortcutName([string]$Code) {
    return "League of Legends $($Code.Split('_')[1])"
}

# ja_JP → ico\league-of-legends-jp.ico si présent, sinon l'icône Riot
function Resolve-IconPath([string]$Code) {
    $candidate = Join-Path $folder "ico\league-of-legends-$($Code.Split('_')[1].ToLower()).ico"
    if (Test-Path $candidate) { return $candidate }
    return $defaultIcon
}

function Test-ShortcutExists([string]$Code, [string]$Directory) {
    return Test-Path ([IO.Path]::Combine($Directory, "$(Get-ShortcutName $Code).lnk"))
}

# ---------------------------------------------------------------- Dialogue de choix

# Pré-coche les langues déjà installées dans la destination ; sinon celles marquées "default"
function Get-PreselectedCodes([object[]]$Catalog, [string]$Directory) {
    $installed = @($Catalog | Where-Object { Test-ShortcutExists $_.code $Directory } | ForEach-Object { $_.code })
    if ($installed.Count -gt 0) { return $installed }
    return @($Catalog | Where-Object { $_.default } | ForEach-Object { $_.code })
}

function Show-LocalePicker([object[]]$Catalog, [string[]]$Preselected) {
    $form               = New-Object System.Windows.Forms.Form
    $form.Text          = 'League of Legends — langues à installer'
    $form.Size          = New-Object System.Drawing.Size(400, 520)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox   = $false
    $form.MinimizeBox   = $false
    $form.Font          = New-Object System.Drawing.Font('Segoe UI', 10)

    $hint          = New-Object System.Windows.Forms.Label
    $hint.Text     = 'Un raccourci sera créé sur le Bureau pour chaque langue cochée.'
    $hint.Location = New-Object System.Drawing.Point(12, 12)
    $hint.Size     = New-Object System.Drawing.Size(360, 40)

    $list               = New-Object System.Windows.Forms.CheckedListBox
    $list.Location      = New-Object System.Drawing.Point(12, 56)
    $list.Size          = New-Object System.Drawing.Size(360, 370)
    $list.CheckOnClick  = $true
    foreach ($entry in $Catalog) {
        $index = $list.Items.Add("$($entry.code)   $($entry.label)")
        $list.SetItemChecked($index, ($Preselected -contains $entry.code))
    }

    $ok              = New-Object System.Windows.Forms.Button
    $ok.Text         = 'Installer'
    $ok.Location     = New-Object System.Drawing.Point(180, 440)
    $ok.Size         = New-Object System.Drawing.Size(90, 30)
    $ok.DialogResult = 'OK'

    $cancel              = New-Object System.Windows.Forms.Button
    $cancel.Text         = 'Annuler'
    $cancel.Location     = New-Object System.Drawing.Point(282, 440)
    $cancel.Size         = New-Object System.Drawing.Size(90, 30)
    $cancel.DialogResult = 'Cancel'

    $form.Controls.AddRange(@($hint, $list, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    if ($form.ShowDialog() -ne 'OK') { return $null }
    return @($list.CheckedIndices | ForEach-Object { $Catalog[$_].code })
}

# ---------------------------------------------------------------- Vérification config

# Signale les chemins de config.json absents de cette machine — sans bloquer, le lanceur
# ignore lui-même une appli compagnon introuvable
function Test-LaunchConfig([string]$Path) {
    if (-not (Test-Path $Path)) { throw "config.json introuvable : $Path" }
    $config = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-Path $config.riotClientPath)) {
        Write-Warning "riotClientPath introuvable : $($config.riotClientPath) — corriger config.json"
    }
    if (-not (Test-Path $config.productSettingsPath)) {
        Write-Warning "productSettingsPath introuvable : $($config.productSettingsPath) — LoL est-il installé ?"
    }
    $app = $config.companionApp
    if ($app -and $app.enabled -and -not (Test-Path $app.path)) {
        Write-Warning "Application compagnon '$($app.name)' introuvable : $($app.path) — elle sera ignorée au lancement (voir README.md)"
    }
}

# ---------------------------------------------------------------- Raccourcis

function New-LaunchShortcut([string]$Code, [string]$Directory) {
    $path = [IO.Path]::Combine($Directory, "$(Get-ShortcutName $Code).lnk")
    $shortcut                  = $shell.CreateShortcut($path)
    $shortcut.TargetPath       = $powershell
    $shortcut.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Locale $Code"
    $shortcut.WorkingDirectory = $folder
    $shortcut.IconLocation     = "$(Resolve-IconPath $Code),0"
    $shortcut.WindowStyle      = 7   # Réduite : aucune console visible
    $shortcut.Description      = "Lance League of Legends en $Code"
    $shortcut.Save()
    return $path
}

# Bureau en priorité ; si l'écriture y échoue (dossier protégé, OneDrive verrouillé, chemin absent),
# repli dans le dossier du script pour que l'installation aboutisse quand même
function New-LaunchShortcutWithFallback([string]$Code) {
    try {
        return New-LaunchShortcut $Code $Destination
    } catch {
        Write-Warning "Impossible d'écrire dans $Destination ($($_.Exception.Message)) — repli dans $folder"
        return New-LaunchShortcut $Code $folder
    }
}

function Remove-UnselectedShortcuts([object[]]$Catalog, [string[]]$Selected, [string]$Directory) {
    foreach ($entry in $Catalog) {
        if ($Selected -contains $entry.code) { continue }
        $path = [IO.Path]::Combine($Directory, "$(Get-ShortcutName $entry.code).lnk")
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
            "Retiré : $path"
        }
    }
}

# ---------------------------------------------------------------- Main

$catalog = Read-LocaleCatalog $localesPath
Test-LaunchConfig $configPath

if (-not $Locales) {
    $Locales = Show-LocalePicker $catalog (Get-PreselectedCodes $catalog $Destination)
    if ($null -eq $Locales) { "Annulé : aucun raccourci créé."; exit 2 }
}

# Lancé via -File, "ja_JP,fr_FR" arrive en une seule chaîne : on découpe nous-mêmes
$Locales = @($Locales | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })

$unknown = @($Locales | Where-Object { $_ -notin $catalog.code })
if ($unknown.Count -gt 0) { throw "Langue(s) inconnue(s) dans locales.json : $($unknown -join ', ')" }
if ($Locales.Count -eq 0) { "Aucune langue cochée : aucun raccourci créé."; exit 0 }

foreach ($code in $Locales) {
    "Créé : $(New-LaunchShortcutWithFallback $code)"
}
Remove-UnselectedShortcuts $catalog $Locales $Destination
