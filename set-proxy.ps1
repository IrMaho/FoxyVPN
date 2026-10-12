param([switch]$Disable)

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

if ($Disable) {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0
    Write-Host "[+] Windows System Proxy: DISABLED" -ForegroundColor Yellow
} else {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value "socks=127.0.0.1:1080"
    Write-Host "[+] Windows System Proxy: ENABLED (socks=127.0.0.1:1080)" -ForegroundColor Green
}

$csharp = @'
using System;
using System.Runtime.InteropServices;
public class WinInetRefresh {
    [DllImport("wininet.dll")]
    public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);
    public static void Notify() {
        InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
    }
}
'@

try {
    Add-Type -TypeDefinition $csharp -ErrorAction SilentlyContinue
    [WinInetRefresh]::Notify()
} catch {}
