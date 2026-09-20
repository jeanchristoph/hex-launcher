<#
.SYNOPSIS
    Tests Pester 3.4 de lib\launch-config.lib.ps1 : lecture/écriture de config.json et migration du format.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\launch-config.lib.ps1')
. (Join-Path $here 'companion-test-helpers.ps1')

Describe 'Read-LaunchConfig' {
    AfterEach { Remove-TestTempFiles }

    It 'échoue si le fichier est absent' {
        { Read-LaunchConfig 'C:\introuvable\config.json' } | Should Throw
    }

    It 'migre un ancien bloc companionApp activé en liste companionApps d''une entrée' {
        $config = Read-LaunchConfig (New-TempLegacyConfig)
        @($config.companionApps).Count | Should Be 1
        $config.companionApps[0].id | Should Be 'opgg'
        $config.companionApps[0].processNames -join ',' | Should Be 'OP.GG'
        $config.companionApps[0].name | Should Be 'OP.GG'
        $config.companionApps[0].path | Should Be 'C:\old\OP.GG.exe'
        $config.PSObject.Properties['companionApp'] | Should BeNullOrEmpty
    }

    It 'migre un ancien bloc désactivé en liste vide' {
        $path = New-TempFile 'config-test' '{ "riotClientPath": "C:\\r.exe", "productSettingsPath": "C:\\y", "companionApp": { "enabled": false } }'
        @((Read-LaunchConfig $path).companionApps).Count | Should Be 0
    }

    It 'lit une liste companionApps de plusieurs entrées' {
        $path = New-TempConfig '[{ "id": "blitz", "name": "Blitz", "path": "C:\\b.exe", "arguments": "" }, { "id": "opgg", "name": "OP.GG", "path": "C:\\o.exe", "arguments": "" }]'
        $config = Read-LaunchConfig $path
        (@($config.companionApps) | ForEach-Object { $_.id }) -join ',' | Should Be 'blitz,opgg'
    }

    It 'rend un tableau vide sans aucune appli compagnon' {
        $path = New-TempFile 'config-test' '{ "riotClientPath": "C:\\r.exe", "productSettingsPath": "C:\\y" }'
        @((Read-LaunchConfig $path).companionApps).Count | Should Be 0
    }

    It 'conserve les chemins Riot' {
        $config = Read-LaunchConfig (New-TempLegacyConfig)
        $config.riotClientPath | Should Be 'C:\Riot\RiotClientServices.exe'
        $config.productSettingsPath | Should Be 'C:\yaml'
    }
}

Describe 'Write-LaunchConfig' {
    AfterEach { Remove-TestTempFiles }

    It 'réécrit le fichier en UTF-8 sans BOM et relisible' {
        $path   = New-TempLegacyConfig
        $config = Read-LaunchConfig $path
        Write-LaunchConfig $config $path
        ([IO.File]::ReadAllBytes($path))[0] | Should Be ([byte][char]'{')
        $again = Read-LaunchConfig $path
        @($again.companionApps).Count | Should Be 1
        $again.PSObject.Properties['companionApp'] | Should BeNullOrEmpty
    }
}

Describe 'ConvertTo-CompanionId' {
    It 'dérive l''identifiant du catalogue depuis le nom affiché' {
        ConvertTo-CompanionId 'OP.GG' | Should Be 'opgg'
        ConvertTo-CompanionId 'Porofessor' | Should Be 'porofessor'
    }
}

Describe 'Find-LaunchCompanion' {
    $config = [pscustomobject]@{ companionApps = @([pscustomobject]@{ id = 'blitz'; name = 'Blitz'; path = 'C:\b.exe'; arguments = '' }) }

    It 'retrouve une appli par identifiant' {
        (Find-LaunchCompanion $config 'blitz').name | Should Be 'Blitz'
    }

    It 'rend null pour un identifiant absent ou vide' {
        Find-LaunchCompanion $config 'opgg' | Should BeNullOrEmpty
        Find-LaunchCompanion $config '' | Should BeNullOrEmpty
    }
}

Describe 'Get-OtherCompanionProcessNames' {
    $config = [pscustomobject]@{ companionApps = @(
        [pscustomobject]@{ id = 'porofessor'; name = 'Porofessor'; path = 'C:\Overwolf\OverwolfLauncher.exe'; arguments = ''; processNames = @('Overwolf') },
        [pscustomobject]@{ id = 'blitz'; name = 'Blitz'; path = 'C:\Programs\Blitz\Blitz.exe'; arguments = ''; processNames = @() },
        [pscustomobject]@{ id = 'opgg'; name = 'OP.GG'; path = 'C:\Programs\OP.GG\OP.GG.exe'; arguments = '' }
    ) }

    It 'liste les process de toutes les applis sauf celle du raccourci' {
        (Get-OtherCompanionProcessNames $config 'blitz') -join ',' | Should Be 'Overwolf,OP.GG'
    }

    It 'liste toutes les applis quand le raccourci n''en demande aucune' {
        (Get-OtherCompanionProcessNames $config '') -join ',' | Should Be 'Overwolf,Blitz,OP.GG'
    }

    It 'déduit le nom de process de l''exécutable quand l''entrée ne le déclare pas' {
        (Get-OtherCompanionProcessNames $config 'porofessor') -join ',' | Should Be 'Blitz,OP.GG'
    }

    It 'rend une liste vide sans aucune appli compagnon' {
        @(Get-OtherCompanionProcessNames ([pscustomobject]@{ companionApps = @() }) 'blitz').Count | Should Be 0
    }
}

Describe 'Test-LaunchCompanionAppsEqual' {
    $blitz = [pscustomobject]@{ id = 'blitz'; name = 'Blitz'; path = 'C:\b.exe'; arguments = '' }
    $opgg  = [pscustomobject]@{ id = 'opgg'; name = 'OP.GG'; path = 'C:\o.exe'; arguments = '' }

    It 'considère égales deux listes identiques' {
        Test-LaunchCompanionAppsEqual @($blitz, $opgg) @($blitz, $opgg) | Should Be $true
    }

    It 'considère différentes deux listes de contenu différent' {
        Test-LaunchCompanionAppsEqual @($blitz) @($opgg) | Should Be $false
        Test-LaunchCompanionAppsEqual @($blitz) @() | Should Be $false
    }

    It 'considère égales deux listes vides' {
        Test-LaunchCompanionAppsEqual @() @() | Should Be $true
    }
}

Describe 'Get-LaunchUseLocalApi' {
    It 'privilégie le lancement direct quand le poste n''a rien choisi' {
        Get-LaunchUseLocalApi (Read-LaunchConfig (New-TempConfig)) | Should Be $true
    }

    It 'respecte le lancement classique choisi dans setup' {
        $config = Read-LaunchConfig (New-TempConfig)
        Set-LaunchUseLocalApi $config $false
        Get-LaunchUseLocalApi $config | Should Be $false
    }
}

Describe 'Save-LaunchUseLocalApi' {
    AfterEach { Remove-TestTempFiles }

    It 'écrit config.json quand le choix change, et le relit tel quel' {
        $path = New-TempConfig
        $config = Read-LaunchConfig $path
        Save-LaunchUseLocalApi $config $path $false | Should Be $true
        Get-LaunchUseLocalApi (Read-LaunchConfig $path) | Should Be $false
    }

    It 'n''écrit rien quand le choix est déjà celui du fichier' {
        $path = New-TempConfig
        $config = Read-LaunchConfig $path
        Save-LaunchUseLocalApi $config $path $true | Should Be $false
    }
}
