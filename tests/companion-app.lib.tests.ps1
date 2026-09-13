<#
.SYNOPSIS
    Tests Pester 3.4 (livré avec Windows PowerShell 5.1) de lib\companion-app.lib.ps1.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path tests"
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\lib\companion-app.lib.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')
$ProjectCatalogPath = Join-Path $here '..\companion-apps.json'

# ---------------------------------------------------------------- Catalogue

Describe 'Read-CompanionCatalog' {
    AfterEach { Remove-TestTempFiles }

    It 'charge le catalogue du projet avec ses quatre applications dans l''ordre de priorité' {
        $catalog = Read-CompanionCatalog $ProjectCatalogPath
        ($catalog | ForEach-Object { $_.id }) -join ',' | Should Be 'porofessor,blitz,opgg,mobalytics'
    }

    It 'valide chaque entrée du catalogue du projet' {
        Read-CompanionCatalog $ProjectCatalogPath | ForEach-Object { Test-CompanionCatalogEntry $_ | Should Be $true }
    }

    It 'échoue si le fichier est absent' {
        { Read-CompanionCatalog 'C:\introuvable\companion-apps.json' } | Should Throw
    }

    It 'retourne un tableau vide pour un catalogue vide' {
        @(Read-CompanionCatalog (New-TempCatalog '[]')).Count | Should Be 0
    }

    It 'accepte une entrée complète' {
        @(Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson))).Count | Should Be 1
    }

    It 'rejette une stratégie d''installation inconnue' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ install = @{ strategy = 'ftp'; timeoutSeconds = 30 } })) } | Should Throw
    }

    It 'rejette une entrée sans identifiant' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ id = '' })) } | Should Throw
    }

    It 'rejette un mode de désinstallation inconnu' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ uninstall = @{ mode = 'force' } })) } | Should Throw
    }

    It 'rejette une stratégie winget sans identifiant de paquet' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ install = @{ strategy = 'winget'; timeoutSeconds = 30 } })) } | Should Throw
    }

    It 'rejette un téléchargement qui ne passe pas par https' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ install = @{ strategy = 'download'; url = 'http://example.test/a.exe'; arguments = '/S'; timeoutSeconds = 30 } })) } | Should Throw
    }

    It 'rejette une entrée sans éditeur signataire' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ signer = @{ organization = ''; country = 'US' } })) } | Should Throw
    }

    It 'rejette un motif de détection qui n''est pas une regex valide' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ detect = @{ registryDisplayNamePattern = '^(Blitz'; path = '' } })) } | Should Throw
    }

    It 'rejette un délai d''installation absent ou nul' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ install = @{ strategy = 'winget'; wingetId = 'V.X' } })) } | Should Throw
    }

    It 'rejette un repli dont les champs manquent' {
        { Read-CompanionCatalog (New-TempCatalog (New-CatalogEntryJson @{ install = @{ strategy = 'winget'; wingetId = 'V.X'; timeoutSeconds = 30; fallback = 'download' } })) } | Should Throw
    }
}

Describe 'Find-CompanionCatalogEntry' {
    $catalog = @((New-TestCompanionApp -Id 'a'), (New-TestCompanionApp -Id 'b'))

    It 'retrouve une entrée par identifiant' {
        (Find-CompanionCatalogEntry $catalog 'b').id | Should Be 'b'
    }

    It 'retourne null pour un identifiant inconnu' {
        Find-CompanionCatalogEntry $catalog 'z' | Should BeNullOrEmpty
    }
}

Describe 'Expand-CompanionPath' {
    It 'résout %LOCALAPPDATA%' {
        Expand-CompanionPath '%LOCALAPPDATA%\Programs\X\X.exe' | Should Be "$env:LOCALAPPDATA\Programs\X\X.exe"
    }

    It 'résout %ProgramFiles(x86)% malgré les parenthèses' {
        Expand-CompanionPath '%ProgramFiles(x86)%\Overwolf\OverwolfLauncher.exe' | Should Be "${env:ProgramFiles(x86)}\Overwolf\OverwolfLauncher.exe"
    }

    It 'laisse un chemin vide inchangé' {
        Expand-CompanionPath '' | Should Be ''
    }
}

# ---------------------------------------------------------------- Détection

Describe 'Get-InstalledCompanionApps' {
    It 'reconnaît OP.GG par motif malgré la version dans DisplayName' {
        Mock Get-UninstallRegistryEntries { @(New-RegistryEntry 'OP.GG 2.5.5' '"u.exe" /currentuser' '"u.exe" /currentuser /S' '2.5.5') }
        $found = @(Get-InstalledCompanionApps @(New-TestCompanionApp -Id 'opgg' -Pattern '^OP\.GG'))
        $found.Count | Should Be 1
        $found[0].Registry.DisplayVersion | Should Be '2.5.5'
    }

    It 'ignore une application sans clé ni chemin de détection' {
        Mock Get-UninstallRegistryEntries { @(New-RegistryEntry 'Autre chose' 'x.exe') }
        @(Get-InstalledCompanionApps @(New-TestCompanionApp -Pattern '^Blitz$' -DetectPath 'C:\introuvable\blitz.exe')).Count | Should Be 0
    }

    It 'respecte l''ordre du catalogue quand plusieurs applications sont présentes' {
        Mock Get-UninstallRegistryEntries { @((New-RegistryEntry 'Blitz' 'b.exe'), (New-RegistryEntry 'Porofessor.gg' 'p.exe')) }
        $catalog = @((New-TestCompanionApp -Id 'porofessor' -Pattern '^Porofessor'), (New-TestCompanionApp -Id 'blitz' -Pattern '^Blitz$'))
        ((Get-InstalledCompanionApps $catalog) | ForEach-Object { $_.App.id }) -join ',' | Should Be 'porofessor,blitz'
    }

    It 'détecte par chemin quand la clé de registre est absente' {
        Mock Get-UninstallRegistryEntries { @() }
        $found = @(Get-InstalledCompanionApps @(New-TestCompanionApp -DetectPath '%SystemRoot%\notepad.exe'))
        $found.Count | Should Be 1
        $found[0].Registry | Should BeNullOrEmpty
    }

    It 'ne rend aucun élément, pas même un null, sur une machine sans aucune application' {
        Mock Get-UninstallRegistryEntries { @() }
        $result = @(Get-InstalledCompanionApps @((New-TestCompanionApp -Id 'a'), (New-TestCompanionApp -Id 'b')))
        $result.Count | Should Be 0
        @($result | Where-Object { $null -eq $_ }).Count | Should Be 0
    }
}

# ---------------------------------------------------------------- Désinstallation

Describe 'Resolve-CompanionUninstallCommand' {
    It 'préfère QuietUninstallString en mode silencieux' {
        $entry = New-RegistryEntry 'Blitz' '"u.exe" /currentuser' '"u.exe" /currentuser /S'
        Resolve-CompanionUninstallCommand (New-TestCompanionApp -Mode 'silent') $entry | Should Be '"u.exe" /currentuser /S'
    }

    It 'ajoute /S à UninstallString quand QuietUninstallString est absente' {
        $entry = New-RegistryEntry 'Blitz' '"u.exe" /currentuser'
        Resolve-CompanionUninstallCommand (New-TestCompanionApp -Mode 'silent') $entry | Should Be '"u.exe" /currentuser /S'
    }

    It 'garde UninstallString brute en mode interactif même si une commande silencieuse existe' {
        $entry = New-RegistryEntry 'Porofessor.gg' 'OWUninstaller.exe --uninstall-app=abc' 'OWUninstaller.exe /S'
        Resolve-CompanionUninstallCommand (New-TestCompanionApp -Mode 'interactive') $entry | Should Be 'OWUninstaller.exe --uninstall-app=abc'
    }

    It 'retourne null sans entrée de registre' {
        Resolve-CompanionUninstallCommand (New-TestCompanionApp) $null | Should BeNullOrEmpty
    }

    It 'retourne null si UninstallString est vide' {
        Resolve-CompanionUninstallCommand (New-TestCompanionApp) (New-RegistryEntry 'X' '') | Should BeNullOrEmpty
    }
}

Describe 'Split-CompanionCommandLine' {
    It 'sépare un exécutable entre guillemets de ses arguments' {
        $command = Split-CompanionCommandLine '"C:\Users\x\AppData\Local\Programs\OP.GG\Uninstall OP.GG.exe" /currentuser /S'
        $command.Path | Should Be 'C:\Users\x\AppData\Local\Programs\OP.GG\Uninstall OP.GG.exe'
        $command.Arguments | Should Be '/currentuser /S'
    }

    It 'sépare un exécutable sans guillemets contenant des espaces (Overwolf)' {
        $command = Split-CompanionCommandLine 'C:\Program Files (x86)\Overwolf\OWUninstaller.exe --uninstall-app=pibhbkk'
        $command.Path | Should Be 'C:\Program Files (x86)\Overwolf\OWUninstaller.exe'
        $command.Arguments | Should Be '--uninstall-app=pibhbkk'
    }

    It 'ne coupe pas sur un ".exe" au milieu d''un nom de dossier' {
        $command = Split-CompanionCommandLine 'C:\Tools\my.executable.dir\Uninstall.exe /S'
        $command.Path | Should Be 'C:\Tools\my.executable.dir\Uninstall.exe'
        $command.Arguments | Should Be '/S'
    }

    It 'rend des arguments vides quand il n''y en a pas' {
        $command = Split-CompanionCommandLine '"C:\App\Uninstall.exe"'
        $command.Path | Should Be 'C:\App\Uninstall.exe'
        $command.Arguments | Should Be ''
    }

    It 'garde la ligne entière comme chemin sans .exe ni guillemets' {
        (Split-CompanionCommandLine 'MsiExec /X{GUID}').Path | Should Be 'MsiExec /X{GUID}'
    }
}

Describe 'Wait-CompanionState' {
    Mock Start-Sleep {}

    It 'rend vrai dès que l''état attendu est atteint' {
        $script:polls = 0
        Mock Test-CompanionInstalled { $script:polls++; return ($script:polls -ge 3) }
        Wait-CompanionState (New-TestCompanionApp) -Installed $true -TimeoutSeconds 30 | Should Be $true
        $script:polls | Should Be 3
    }

    It 'rend faux quand l''état attendu n''est pas atteint dans le délai' {
        Mock Test-CompanionInstalled { $false }
        Wait-CompanionState (New-TestCompanionApp) -Installed $true -TimeoutSeconds 0 | Should Be $false
    }

    It 'attend l''absence quand on demande une désinstallation' {
        Mock Test-CompanionInstalled { $false }
        Wait-CompanionState (New-TestCompanionApp) -Installed $false -TimeoutSeconds 5 | Should Be $true
    }

    It 'confie l''attente à OnTick quand il est fourni, sans Start-Sleep' {
        $script:polls = 0; $script:ticks = 0
        Mock Test-CompanionInstalled { $script:polls++; return ($script:polls -ge 3) }
        Wait-CompanionState (New-TestCompanionApp) -Installed $true -TimeoutSeconds 30 -OnTick { $script:ticks++ } | Out-Null
        $script:ticks | Should Be 2
        Assert-MockCalled -Scope It Start-Sleep -Exactly -Times 0
    }
}

# ---------------------------------------------------------------- Signature

Describe 'Test-CompanionCertificateSubject' {
    It 'accepte organisation et pays exacts (RDN sur plusieurs lignes)' {
        Test-CompanionCertificateSubject "C=IL`r`nL=Ramat Gan`r`nO=Overwolf Ltd`r`nCN=Overwolf Ltd" 'Overwolf Ltd' 'IL' | Should Be $true
    }

    It 'accepte une organisation entre guillemets (Blitz, Mobalytics)' {
        Test-CompanionCertificateSubject "C=US`r`nO=`"GAMERS NET, INC.`"`r`nCN=`"GAMERS NET, INC.`"" 'GAMERS NET, INC.' 'US' | Should Be $true
    }

    It 'refuse un "O=" glissé dans le CN d''un autre éditeur' {
        Test-CompanionCertificateSubject "C=US`r`nO=Evil Corp`r`nCN=`"Evil, O=Overwolf Ltd`"" 'Overwolf Ltd' 'IL' | Should Be $false
    }

    It 'refuse une organisation de casse différente' {
        Test-CompanionCertificateSubject "C=IL`r`nO=OVERWOLF LTD`r`nCN=x" 'Overwolf Ltd' 'IL' | Should Be $false
    }

    It 'refuse la bonne organisation dans le mauvais pays' {
        Test-CompanionCertificateSubject "C=GB`r`nO=Overwolf Ltd`r`nCN=x" 'Overwolf Ltd' 'IL' | Should Be $false
    }

    It 'refuse une organisation qui ne correspond que partiellement' {
        Test-CompanionCertificateSubject "C=IL`r`nO=Overwolf Ltd`r`nCN=x" 'Overwolf' 'IL' | Should Be $false
    }
}

Describe 'Test-CompanionBinaryTrusted' {
    $signer = [pscustomobject]@{ organization = 'Vendor'; country = 'US' }
    $existing = "$env:SystemRoot\notepad.exe"

    It 'refuse un chemin relatif' {
        Mock Get-CompanionSignatureSubject { "C=US`r`nO=Vendor" }
        Test-CompanionBinaryTrusted 'uninst.exe' $signer | Should Be $false
        Assert-MockCalled -Scope It Get-CompanionSignatureSubject -Exactly -Times 0
    }

    It 'refuse un fichier qui n''est pas un .exe' {
        Test-CompanionBinaryTrusted "$env:SystemRoot\win.ini" $signer | Should Be $false
    }

    It 'refuse un fichier absent' {
        Test-CompanionBinaryTrusted 'C:\introuvable\x.exe' $signer | Should Be $false
    }

    It 'refuse une signature absente ou invalide' {
        Mock Get-CompanionSignatureSubject { $null }
        Test-CompanionBinaryTrusted $existing $signer | Should Be $false
    }

    It 'accepte un binaire signé par l''éditeur attendu' {
        Mock Get-CompanionSignatureSubject { "C=US`r`nO=Vendor`r`nCN=Vendor" }
        Test-CompanionBinaryTrusted $existing $signer | Should Be $true
    }

    It 'refuse un binaire signé par un autre éditeur' {
        Mock Get-CompanionSignatureSubject { "C=US`r`nO=Someone`r`nCN=Someone" }
        Test-CompanionBinaryTrusted $existing $signer | Should Be $false
    }
}

# ---------------------------------------------------------------- config.json

Describe 'ConvertTo-LaunchCompanionEntry' {
    It 'produit une entrée companionApps avec le chemin de lancement résolu' {
        $entry = ConvertTo-LaunchCompanionEntry (New-TestCompanionApp -Id 'blitz')
        $entry.id | Should Be 'blitz'
        $entry.name | Should Be 'blitz'
        $entry.path | Should Be "$env:TEMP\app.exe"
        $entry.arguments | Should Be '--flag'
    }

    It 'conserve les quatre clés attendues par launch-lol.ps1, dans l''ordre' {
        ((ConvertTo-LaunchCompanionEntry (New-TestCompanionApp)).Keys -join ',') | Should Be 'id,name,path,arguments'
    }
}
