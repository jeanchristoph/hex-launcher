<#
.SYNOPSIS
    Décompression zstd par la bibliothèque officielle libzstd.dll (x64), vérifiée avant chargement.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\zstd.lib.ps1')

    Les manifests RMAN et les chunks du CDN Riot sont compressés en zstd, que .NET Framework ne sait pas lire.
    native\libzstd.dll vient de la release officielle facebook/zstd (BSD, licence à côté) : tools\fetch-libzstd.ps1
    la récupère et en vérifie l'empreinte.

    INVARIANT : la DLL n'est chargée que si son SHA-256 est exactement $ZstdLibrarySha256 — un fichier remplacé
    n'est jamais exécuté. Elle est chargée par son chemin absolu (LoadLibraryW), jamais cherchée dans le PATH.
    Toute erreur lève une exception : l'appelant renonce au texte forcé et lance le jeu normalement.

    Usage :
        Initialize-ZstdLibrary
        $bytes = [HexLauncher.Zstd]::Decompress($source, $offset, $count, $expectedSize)
#>

$ZstdLibraryPath   = Join-Path $PSScriptRoot 'native\libzstd.dll'
$ZstdLicensePath   = Join-Path $PSScriptRoot 'native\libzstd.LICENSE.txt'
$ZstdLibrarySha256 = '8F07E1112ED283E5CD2798833E9A3C32D8961381BC36DA04AF57A1B0CA9BD40B'   # zstd 1.5.7 win64

# Compilé au premier Initialize-ZstdLibrary seulement : un lancement sans texte forcé ne paie pas csc
$ZstdTypeDefinition = @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace HexLauncher {
    public static class Zstd {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr LoadLibraryW(string path);
        [DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern UIntPtr ZSTD_decompress(IntPtr dst, UIntPtr dstCapacity, IntPtr src, UIntPtr srcSize);
        [DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern uint ZSTD_isError(UIntPtr code);
        [DllImport("libzstd.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr ZSTD_getErrorName(UIntPtr code);

        // Une fois chargée par son chemin, la DLL est trouvée par son nom par les DllImport ci-dessus
        public static void Load(string path) {
            if (LoadLibraryW(path) == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        // Une trame zstd lue dans source[offset .. offset+count[ ; sa taille décompressée est connue d'avance
        public static byte[] Decompress(byte[] source, int offset, int count, int expectedSize) {
            if (source == null) throw new ArgumentNullException("source");
            if (offset < 0 || count < 0 || offset + count > source.Length) throw new ArgumentOutOfRangeException("count");
            if (expectedSize < 0) throw new ArgumentOutOfRangeException("expectedSize");
            byte[] target = new byte[expectedSize];
            GCHandle src = GCHandle.Alloc(source, GCHandleType.Pinned);
            GCHandle dst = GCHandle.Alloc(target, GCHandleType.Pinned);
            try {
                UIntPtr written = ZSTD_decompress(dst.AddrOfPinnedObject(), (UIntPtr)expectedSize,
                                                  src.AddrOfPinnedObject() + offset, (UIntPtr)count);
                if (ZSTD_isError(written) != 0)
                    throw new InvalidDataException("zstd : " + Marshal.PtrToStringAnsi(ZSTD_getErrorName(written)));
                if ((ulong)written != (ulong)expectedSize)
                    throw new InvalidDataException("zstd : " + written + " octets décompressés, " + expectedSize + " attendus");
                return target;
            }
            finally { src.Free(); dst.Free(); }
        }
    }
}
'@

$script:ZstdLibraryLoaded = $false

function Test-ZstdLibraryTrusted([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $ZstdLibrarySha256
}

# DLL x64 : un PowerShell 32 bits (SysWOW64) ne peut pas la charger
function Test-ZstdProcessSupported {
    return [IntPtr]::Size -eq 8
}

function Initialize-ZstdLibrary {
    if ($script:ZstdLibraryLoaded) { return }
    if (-not (Test-ZstdProcessSupported)) { throw 'zstd : PowerShell 64 bits requis' }
    if (-not (Test-ZstdLibraryTrusted $ZstdLibraryPath)) { throw "zstd : $ZstdLibraryPath absente ou empreinte inattendue" }
    if (-not ([Management.Automation.PSTypeName]'HexLauncher.Zstd').Type) { Add-Type -TypeDefinition $ZstdTypeDefinition }
    [HexLauncher.Zstd]::Load($ZstdLibraryPath)
    $script:ZstdLibraryLoaded = $true
}
