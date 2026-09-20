<#
.SYNOPSIS
    Fenêtre du Riot Client : la masquer une fois le jeu lancé, pour ne laisser que son icône près de l'horloge.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\riot-window.lib.ps1')

    Une fois le jeu lancé, on demande à la fenêtre de se fermer, comme un clic sur sa croix. Tant qu'une partie
    tourne, le Riot Client ne quitte pas : il se replie sur son icône de zone de notification. Mesuré le
    2026-09-20 : 7 process → 1, 1 088 Mo → 493 Mo, icône conservée, et son API répond toujours (GET 200,
    PUT 201) — le prochain lancement gardera donc le chemin rapide.

    Simplement masquer la fenêtre (ShowWindow SW_HIDE) a été essayé d'abord : l'affichage disparaît aussi, mais
    l'interface Chromium reste chargée — pas un mégaoctet rendu, 0,4 % d'un cœur économisé. Sans intérêt.

    ⚠ Ne jamais fermer cette fenêtre tant que le jeu n'est pas lancé : sans partie en cours, le Riot Client
    quitterait pour de bon, et en démarrage manuel elle sert encore à cliquer sur Jouer.

    Le Riot Client offre à chacun de choisir ce que fait sa croix : quitter, ou se réduire dans la zone de
    notification. Les deux réglages nous conviennent ici, puisqu'une partie est en cours au moment où l'on ferme.
    La différence se voit au lancement suivant : réglé sur « quitter », le Riot Client s'arrête dès que le jeu se
    ferme, et le prochain lancement le redémarre (Assert-RiotClientRunning) ; réglé sur « réduire », il reste
    disponible et le lancement suivant est plus rapide.

    La fenêtre est portée par le process « Riot Client » (avec une espace), classe Chrome_WidgetWin_1 ;
    `RiotClientServices`, lui, n'a jamais de fenêtre visible, seulement une TrayIconClass. Rien de tout cela ne
    se devine : relevé par énumération des fenêtres le 2026-09-20.

    INVARIANT : masquer est un confort. Une fenêtre introuvable, une API Windows qui refuse, et le jeu tourne
    quand même — aucun échec, aucun avertissement bloquant.
#>

$RiotClientWindowProcessName = 'Riot Client'
$RiotClientWindowClassName   = 'Chrome_WidgetWin_1'
$WindowMessageClose = 0x0010

if (-not ([Management.Automation.PSTypeName]'HexLauncher.NativeWindow').Type) {
    Add-Type -Namespace HexLauncher -Name NativeWindow -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
'@
}

function Get-WindowClassName([IntPtr]$Handle) {
    $buffer = New-Object Text.StringBuilder 256
    [void][HexLauncher.NativeWindow]::GetClassNameW($Handle, $buffer, 256)
    return $buffer.ToString()
}

function Get-WindowProcessName([IntPtr]$Handle) {
    $processId = 0
    [void][HexLauncher.NativeWindow]::GetWindowThreadProcessId($Handle, [ref]$processId)
    try { return (Get-Process -Id $processId -ErrorAction Stop).Name }
    catch { return '' }
}

# La fenêtre visible du Riot Client, ou IntPtr::Zero : ni MainWindowHandle ni le nom du process ne suffisent,
# le premier vaut 0 sur une application Chromium et le second n'est pas celui qu'on croit
function Find-RiotClientWindow {
    $script:FoundRiotWindow = [IntPtr]::Zero
    $callback = [HexLauncher.NativeWindow+EnumWindowsProc] {
        param($Handle, $Parameter)
        if (-not [HexLauncher.NativeWindow]::IsWindowVisible($Handle)) { return $true }
        if ((Get-WindowClassName $Handle) -ne $RiotClientWindowClassName) { return $true }
        if ((Get-WindowProcessName $Handle) -ne $RiotClientWindowProcessName) { return $true }
        $script:FoundRiotWindow = $Handle
        return $false
    }
    [void][HexLauncher.NativeWindow]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:FoundRiotWindow
}

# Rend vrai si une fenêtre était ouverte et a reçu la demande de fermeture. À n'appeler qu'une fois le client
# de jeu lancé : c'est la partie en cours qui garantit que le Riot Client se replie au lieu de quitter.
function Close-RiotClientWindow {
    try {
        $handle = Find-RiotClientWindow
        if ($handle -eq [IntPtr]::Zero) { return $false }
        [void][HexLauncher.NativeWindow]::PostMessage($handle, $WindowMessageClose, [IntPtr]::Zero, [IntPtr]::Zero)
        return $true
    } catch {
        return $false
    }
}
