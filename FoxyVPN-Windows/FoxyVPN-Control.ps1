# FoxyVPN Pro Control Center
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'FoxyVPN Pro Control Center'
$exePath = Join-Path $PSScriptRoot 'firefox-vpn-proxy-windows-amd64.exe'
$accDir = Join-Path $PSScriptRoot 'accounts'
$accMetaFile = Join-Path $PSScriptRoot 'accounts.json'
$globalTokenPath = "$env:USERPROFILE\.firefox-vpn-tokens.json"

if (-not (Test-Path $exePath)) {
    Write-Host '[!] Error: firefox-vpn-proxy-windows-amd64.exe not found' -ForegroundColor Red
    pause
    exit
}

if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir | Out-Null
}

$Global:CurrentCountryCode = ''
$Global:CurrentCountryName = ''

$servers = @(
    @{ Code = 'DE'; Name = 'Germany'; Host = 'muc139.m1.fastly-masque.net' },
    @{ Code = 'NL'; Name = 'Netherlands'; Host = 'ehrd229.m1.fastly-masque.net' },
    @{ Code = 'AT'; Name = 'Austria'; Host = 'vie63.m1.fastly-masque.net' },
    @{ Code = 'BG'; Name = 'Bulgaria'; Host = 'sof151.m1.fastly-masque.net' },
    @{ Code = 'GB'; Name = 'United Kingdom'; Host = 'eglc860.m1.fastly-masque.net' },
    @{ Code = 'FR'; Name = 'France'; Host = 'lfpb115.m1.fastly-masque.net' },
    @{ Code = 'ES'; Name = 'Spain'; Host = 'leto235.m1.fastly-masque.net' },
    @{ Code = 'IT'; Name = 'Italy'; Host = 'mxp69.m1.fastly-masque.net' },
    @{ Code = 'US'; Name = 'United States'; Host = 'us.m1.fastly-masque.net' },
    @{ Code = 'CA'; Name = 'Canada'; Host = 'ca.m1.fastly-masque.net' },
    @{ Code = 'SG'; Name = 'Singapore'; Host = 'wsat188.m1.fastly-masque.net' },
    @{ Code = 'JP'; Name = 'Japan'; Host = 'rjtf770.m1.fastly-masque.net' },
    @{ Code = 'REC'; Name = 'Recommended Anycast'; Host = 'p.m1.fastly-masque.net' }
)

function Fetch-FxaEmail($tokPath) {
    try {
        if (-not (Test-Path $tokPath)) { return 'N/A' }
        $tok = Get-Content $tokPath -Raw | ConvertFrom-Json
        if (-not $tok.access_token) { return 'N/A' }
        $headers = @{ 'Authorization' = "Bearer $($tok.access_token)" }
        $prof = Invoke-RestMethod -Uri 'https://profile.accounts.firefox.com/v1/profile' -Headers $headers -TimeoutSec 3 -ErrorAction Stop
        if ($prof.email) { return $prof.email }
    } catch {}
    return 'N/A'
}

function Fetch-MozillaStatus($tokPath) {
    try {
        if (-not (Test-Path $tokPath)) { return $null }
        $tok = Get-Content $tokPath -Raw | ConvertFrom-Json
        if (-not $tok.access_token) { return $null }
        $headers = @{
            'Authorization' = "Bearer $($tok.access_token)"
            'Content-Type'  = 'application/json'
        }
        return Invoke-RestMethod -Uri 'https://vpn.mozilla.org/api/v1/fpn/status' -Headers $headers -TimeoutSec 3 -ErrorAction Stop
    } catch { return $null }
}

function Get-AccountLifecycle($createdAtStr, $resetDateStr) {
    $now = [DateTime]::Now
    $created = if ($createdAtStr) {
        try { [DateTime]::Parse($createdAtStr).ToLocalTime() } catch { $now }
    } else { $now }

    $reset = if ($resetDateStr) {
        try { [DateTime]::Parse($resetDateStr).ToLocalTime() } catch { (Get-Date -Year $now.Year -Month ($now.Month % 12 + 1) -Day 1) }
    } else { (Get-Date -Year $now.Year -Month ($now.Month % 12 + 1) -Day 1) }

    $elapsed = $now - $created
    $elapsedTotalMins = [math]::Max(1, [int]$elapsed.TotalMinutes)
    $elapsedStr = if ($elapsed.TotalDays -ge 1) {
        "$([int]$elapsed.TotalDays) days ago"
    } elseif ($elapsed.TotalHours -ge 1) {
        "$([int]$elapsed.TotalHours) hours ago"
    } else {
        "$elapsedTotalMins mins ago"
    }

    $daysLeft = [math]::Max(0, [int]($reset - $now).TotalDays)
    return @{
        ActivatedExact = $created.ToString('yyyy-MM-dd HH:mm')
        Age = $elapsedStr
        DaysRemaining = $daysLeft
        ResetDate = $reset.ToString('yyyy-MM-dd')
    }
}

function Draw-Bar($current, $max, $width = 20) {
    if ($max -le 0) { $max = 1 }
    $ratio = [math]::Min(1.0, [math]::Max(0.0, ($current / $max)))
    $filled = [int][math]::Round($ratio * $width)
    $empty = $width - $filled
    $bar = ('#' * $filled) + ('-' * $empty)
    return "[$bar]"
}

function Get-AccountList {
    if (Test-Path $accMetaFile) {
        try {
            $raw = Get-Content $accMetaFile -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json
            if ($json -is [System.Collections.IEnumerable] -and $json.Count -gt 0) {
                return [System.Collections.ArrayList]@($json)
            }
        } catch {}
    }

    $list = New-Object System.Collections.ArrayList
    if (Test-Path $globalTokenPath) {
        $savedFile = 'account_primary.json'
        Copy-Item $globalTokenPath (Join-Path $accDir $savedFile) -Force
        $info = Query-TokenInfo
        $mail = Fetch-FxaEmail $globalTokenPath
        $st = Fetch-MozillaStatus $globalTokenPath
        $createVal = if ($st.created_at) { $st.created_at } else { [DateTime]::UtcNow.ToString('o') }
        $uidVal = if ($info.UID) { $info.UID } else { '8476826' }
        $item = [PSCustomObject]@{
            Id = $uidVal
            Email = $mail
            Name = 'Account 1'
            TokenFile = $savedFile
            LimitBytes = $info.LimitBytes
            RemainingBytes = $info.RemainingBytes
            ResetDate = $info.ResetDate
            CreatedAt = $createVal
            IsActive = $true
        }
        $null = $list.Add($item)
        Save-AccountList $list
    }
    return $list
}

function Save-AccountList($list) {
    $json = $list | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($accMetaFile, $json, [System.Text.Encoding]::UTF8)
}

function Get-ActiveAccount {
    $accounts = Get-AccountList
    $act = $accounts | Where-Object { $_.IsActive -eq $true } | Select-Object -First 1
    if (-not $act -and $accounts.Count -gt 0) {
        $accounts[0].IsActive = $true
        Save-AccountList $accounts
        $act = $accounts[0]
    }
    return $act
}

function Query-TokenInfo {
    $info = @{ UID = ''; LimitBytes = 53687091200; RemainingBytes = 53687091200; ResetDate = '2026-11-01' }
    try {
        $out = & $exePath -print-info 2>&1 | Out-String
        if ($out -match 'UID:\s+(\S+)') { $info.UID = $matches[1] }
        if ($out -match 'Limit:\s+(\d+)') { $info.LimitBytes = [int64]$matches[1] }
        if ($out -match 'Remaining:\s+(\d+)') { $info.RemainingBytes = [int64]$matches[1] }
        if ($out -match 'Resets At:\s+(\S+)') {
            $parts = $matches[1].Split('T')
            $info.ResetDate = $parts[0]
        }
    } catch {}
    return $info
}

function Sync-ActiveTokenToSystem($account) {
    $src = Join-Path $accDir $account.TokenFile
    if (Test-Path $src) {
        Copy-Item $src $globalTokenPath -Force
    }
}

function Switch-Account($targetId) {
    $accounts = Get-AccountList
    $target = $null
    foreach ($a in $accounts) {
        if ($a.Id -eq $targetId) {
            $a.IsActive = $true
            $target = $a
        } else {
            $a.IsActive = $false
        }
    }
    if ($target) {
        Save-AccountList $accounts
        Sync-ActiveTokenToSystem $target
        Write-Host ''
        Write-Host "[OK] Switched to: $($target.Email)" -ForegroundColor Green

        $isRunning = (Get-Process -Name 'firefox-vpn-proxy*' -ErrorAction SilentlyContinue)
        if ($isRunning -and $Global:CurrentCountryCode) {
            Write-Host '[*] Reconnecting VPN on 127.0.0.1:7854...' -ForegroundColor Cyan
            Start-VpnConnection $Global:CurrentCountryCode $Global:CurrentCountryName
        }
    }
}

function Check-AutoSwitchAccount {
    $active = Get-ActiveAccount
    if (-not $active) { return }

    if ($active.RemainingBytes -gt 0 -and $active.RemainingBytes -lt 104857600) {
        $remMb = [math]::Round($active.RemainingBytes / 1MB, 1)
        Write-Host ''
        Write-Host "[!] Quota low on $($active.Email) ($remMb MB remaining)" -ForegroundColor Yellow
        $accounts = Get-AccountList
        $candidate = $accounts | Where-Object { $_.Id -ne $active.Id -and $_.RemainingBytes -gt 524288000 } | Select-Object -First 1
        if ($candidate) {
            Write-Host "[AUTO] Switching to: $($candidate.Email)..." -ForegroundColor Green
            Switch-Account $candidate.Id
        }
    }
}

function Stop-CurrentVpn {
    $existing = Get-Process -Name 'firefox-vpn-proxy*' -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    $Global:CurrentCountryCode = ''
    $Global:CurrentCountryName = ''
}

function Test-AllPings {
    Write-Host ''
    Write-Host '[*] Pinging all servers live...' -ForegroundColor Cyan
    $jobs = foreach ($s in $servers) {
        [powershell]::Create().AddScript({
            param($item)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $lat = 9999
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $c = $tcp.BeginConnect($item.Host, 2499, $null, $null)
                if ($c.AsyncWaitHandle.WaitOne(2500, $false) -and $tcp.Connected) {
                    $sw.Stop()
                    $lat = $sw.ElapsedMilliseconds
                    $tcp.EndConnect($c)
                }
                $tcp.Close()
            } catch {}
            [PSCustomObject]@{
                Code = $item.Code
                Name = $item.Name
                Host = $item.Host
                Latency = $lat
            }
        }).AddArgument($s)
    }

    $tasks = $jobs | ForEach-Object { @{ Pipe = $_; Handle = $_.BeginInvoke() } }
    $results = foreach ($t in $tasks) {
        $res = $t.Pipe.EndInvoke($t.Handle)
        $t.Pipe.Dispose()
        $res
    }
    return ($results | Sort-Object Latency)
}

function Start-VpnConnection($countryCode, $countryName) {
    Check-AutoSwitchAccount
    $active = Get-ActiveAccount
    if ($active) {
        Sync-ActiveTokenToSystem $active
    }

    Stop-CurrentVpn
    Write-Host ''
    Write-Host "[+] Connecting to $countryName on 127.0.0.1:7854..." -ForegroundColor Green
    
    $proc = Start-Process -FilePath $exePath -ArgumentList "-country $countryCode -listen 127.0.0.1:7854 -upstream-conns 4" -WindowStyle Hidden -PassThru
    $Global:CurrentCountryCode = $countryCode
    $Global:CurrentCountryName = $countryName

    Start-Sleep -Seconds 2
    if ($proc.HasExited) {
        Write-Host '[-] Connection stopped unexpectedly.' -ForegroundColor Red
        $Global:CurrentCountryCode = ''
        $Global:CurrentCountryName = ''
    } else {
        Write-Host "[OK] Connected to $countryName [$countryCode]!" -ForegroundColor Green
        Write-Host '[OK] SOCKS5 active on 127.0.0.1:7854 (v2rayN Tun Ready)' -ForegroundColor Yellow
    }
}

function Show-AccountManager {
    while ($true) {
        Clear-Host
        Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
        Write-Host '                       MULTI-ACCOUNT DASHBOARD and MANAGER' -ForegroundColor Yellow
        Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
        
        $accounts = Get-AccountList
        $accCount = $accounts.Count
        Write-Host ''
        Write-Host ('  {0,-4} {1,-3} {2,-25} {3,-9} {4,-9} {5,-10} {6,-12} {7,-10}' -f 'Act', '#', 'Gmail / Email', 'UID', 'Used', 'Remaining', 'Active For', 'Reset Date') -ForegroundColor Cyan
        Write-Host '  ------------------------------------------------------------------------------' -ForegroundColor DarkGray
        
        $i = 1
        $totalRemaining = 0
        foreach ($a in $accounts) {
            $actMark = if ($a.IsActive) { '[*]' } else { '   ' }
            $usedGB = [math]::Round(($a.LimitBytes - $a.RemainingBytes) / 1GB, 2)
            $remGB = [math]::Round($a.RemainingBytes / 1GB, 2)
            $totalRemaining += $a.RemainingBytes
            $color = if ($a.IsActive) { 'Green' } else { 'White' }
            $emailDisp = if ($a.Email -and $a.Email -ne 'N/A') { $a.Email } else { $a.Name }
            if ($emailDisp.Length -gt 24) { $emailDisp = $emailDisp.Substring(0, 21) + '...' }
            
            $lifecycle = Get-AccountLifecycle $a.CreatedAt $a.ResetDate

            Write-Host ('  {0,-4} [{1,-1}] {2,-25} {3,-9} {4,-9} {5,-10} {6,-12} {7,-10}' -f $actMark, $i, $emailDisp, $a.Id, "$usedGB GB", "$remGB GB", $lifecycle.Age, $a.ResetDate) -ForegroundColor $color
            $i++
        }
        
        $totGB = [math]::Round($totalRemaining / 1GB, 2)
        Write-Host '  ------------------------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "  >> Total Bandwidth Pool: $totGB GB across $accCount account(s)" -ForegroundColor Yellow
        Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
        Write-Host '  [1] Switch Active Account        (Ã˜Â§Ã™â€ Ã˜ÂªÃ˜Â®Ã˜Â§Ã˜Â¨ Ã™Ë† Ã™ÂÃ˜Â¹Ã˜Â§Ã™â€žÃ¢â‚¬Å’Ã˜Â³Ã˜Â§Ã˜Â²Ã›Å’ Ã˜Â§ÃšÂ©Ã˜Â§Ã™â€ Ã˜Âª Ã˜Â¯Ã›Å’ÃšÂ¯Ã˜Â±)' -ForegroundColor White
        Write-Host '  [2] Login New Account            (ورود به اکانت و ثبت در برنامه)' -ForegroundColor White
        Write-Host '  [3] Register New Account         (Ã˜Â§Ã›Å’Ã˜Â¬Ã˜Â§Ã˜Â¯ Ã˜Â§ÃšÂ©Ã˜Â§Ã™â€ Ã˜Âª Ã˜Â¬Ã˜Â¯Ã›Å’Ã˜Â¯ - Ã˜Â¨Ã˜Â§Ã˜Â² ÃšÂ©Ã˜Â±Ã˜Â¯Ã™â€  Ã˜ÂµÃ™ÂÃ˜Â­Ã™â€¡ Ã˜Â«Ã˜Â¨Ã˜Âª Ã™â€ Ã˜Â§Ã™â€¦)' -ForegroundColor White
        Write-Host '  [4] Refresh Quotas and Info      (بروزرسانی وضعیت حجم و روزها)' -ForegroundColor White
        Write-Host '  [5] Delete Account               (Ã˜Â­Ã˜Â°Ã™Â Ã›Å’ÃšÂ© Ã˜Â§ÃšÂ©Ã˜Â§Ã™â€ Ã˜Âª Ã˜Â§Ã˜Â² Ã™â€žÃ›Å’Ã˜Â³Ã˜Âª)' -ForegroundColor White
        Write-Host '  [0] Back to Main Menu            (بازگشت به منوی اصلی)' -ForegroundColor White
        Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
        
        $action = Read-Host "`n  Select option [1, 2, 3, 4, 5, 0]"
        
        if ($action -eq '1') {
            $idx = Read-Host "  Enter account number to switch [1-$($accounts.Count)]"
            $num = 0
            if ([int]::TryParse($idx, [ref]$num) -and $num -ge 1 -and $num -le $accounts.Count) {
                Switch-Account $accounts[$num - 1].Id
            }
            Start-Sleep -Seconds 1
        }
        elseif ($action -eq '2') {
            Clear-Host
            Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
            Write-Host '                     Sign In to Existing Firefox Account' -ForegroundColor Yellow
            Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
            Write-Host '  A browser window will open for sign-in.' -ForegroundColor White
            Write-Host '  Please sign in with your other Firefox account in your browser.' -ForegroundColor White
            Write-Host '  Once login succeeds, return to this window.`n' -ForegroundColor Yellow

            $accName = Read-Host '  Enter a friendly label for this account (or press Enter)'
            if (-not $accName) { $accName = "Account $($accounts.Count + 1)" }

            Stop-CurrentVpn

            Write-Host ''
            Write-Host '  [*] Launching Firefox login...' -ForegroundColor Cyan
            & $exePath -login

            if (Test-Path $globalTokenPath) {
                Write-Host '  [*] Retrieving account info and email...' -ForegroundColor Cyan
                $info = Query-TokenInfo
                $email = Fetch-FxaEmail $globalTokenPath
                $st = Fetch-MozillaStatus $globalTokenPath
                $createVal = if ($st.created_at) { $st.created_at } else { [DateTime]::UtcNow.ToString('o') }
                $accId = if ($info.UID) { $info.UID } else { [Guid]::NewGuid().ToString().Substring(0, 8) }
                $tokenFileName = "account_$accId.json"
                Copy-Item $globalTokenPath (Join-Path $accDir $tokenFileName) -Force

                $newAcc = [PSCustomObject]@{
                    Id = $accId
                    Email = $email
                    Name = $accName
                    TokenFile = $tokenFileName
                    LimitBytes = $info.LimitBytes
                    RemainingBytes = $info.RemainingBytes
                    ResetDate = $info.ResetDate
                    CreatedAt = $createVal
                    IsActive = $false
                }
                $accounts = Get-AccountList
                $null = $accounts.Add($newAcc)
                Save-AccountList $accounts
                Write-Host ''
                Write-Host "  [OK] Successfully added: $email (UID: $accId) with 50 GB!" -ForegroundColor Green
            } else {
                Write-Host '  [-] Login failed or cancelled.' -ForegroundColor Red
            }
            Write-Host "`n  Press Enter to continue..."
            [void][System.Console]::ReadLine()
        }
        elseif ($action -eq '3') {
            Write-Host ''
            Write-Host '  [*] Opening https://accounts.firefox.com/signup in your default browser...' -ForegroundColor Cyan
            Start-Process 'https://accounts.firefox.com/signup'
            Write-Host ''
            Write-Host '  [OK] Sign-up page opened! Create your free Firefox account there.' -ForegroundColor Green
            Write-Host '  >> After creating, use option [2] to log in and add it to the manager.' -ForegroundColor Yellow
            Write-Host "`n  Press Enter to continue..."
            [void][System.Console]::ReadLine()
        }
        elseif ($action -eq '4') {
            Write-Host "`n  [*] Updating quotas and emails from Mozilla..." -ForegroundColor Cyan
            $accounts = Get-AccountList
            foreach ($a in $accounts) {
                Sync-ActiveTokenToSystem $a
                $info = Query-TokenInfo
                $mail = Fetch-FxaEmail $globalTokenPath
                $st = Fetch-MozillaStatus $globalTokenPath
                if ($st.created_at) { $a.CreatedAt = $st.created_at }
                if ($mail -and $mail -ne 'N/A') { $a.Email = $mail }
                $a.RemainingBytes = $info.RemainingBytes
                $a.LimitBytes = $info.LimitBytes
                $a.ResetDate = $info.ResetDate
            }
            Save-AccountList $accounts
            $act = Get-ActiveAccount
            if ($act) { Sync-ActiveTokenToSystem $act }
            Write-Host '  [OK] Quotas and cycle refreshed!' -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        elseif ($action -eq '5') {
            $idx = Read-Host "  Enter account number to delete [1-$($accounts.Count)]"
            $num = 0
            if ([int]::TryParse($idx, [ref]$num) -and $num -ge 1 -and $num -le $accounts.Count) {
                $target = $accounts[$num - 1]
                if ($accounts.Count -le 1) {
                    Write-Host '  [-] Cannot delete the only existing account.' -ForegroundColor Red
                } else {
                    $accounts.RemoveAt($num - 1)
                    if ($target.IsActive) { $accounts[0].IsActive = $true }
                    Save-AccountList $accounts
                    $fileToDelete = Join-Path $accDir $target.TokenFile
                    if (Test-Path $fileToDelete) { Remove-Item $fileToDelete -Force }
                    Write-Host "  [OK] Deleted $($target.Email)." -ForegroundColor Yellow
                }
            }
            Start-Sleep -Seconds 1
        }
        elseif ($action -eq '0') {
            break
        }
    }
}

# Main Loop
while ($true) {
    Clear-Host
    Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
    Write-Host '                   >>>  FOXYVPN PRO LIVE CONTROL CENTER  <<<' -ForegroundColor Yellow
    Write-Host '              Engine for v2rayN and Tun  |  GitHub: IrMaho/FoxyVPN' -ForegroundColor DarkGray
    Write-Host '  ==============================================================================' -ForegroundColor DarkCyan
    
    $isRunning = (Get-Process -Name 'firefox-vpn-proxy*' -ErrorAction SilentlyContinue)
    $activeAcc = Get-ActiveAccount
    
    Write-Host ''
    Write-Host '  +--[ CONNECTION STATUS ]-------------------------------------------------------+' -ForegroundColor DarkCyan
    if ($isRunning) {
        $locStr = if ($Global:CurrentCountryName) { "$($Global:CurrentCountryName) [$($Global:CurrentCountryCode)]" } else { "Connected" }
        Write-Host ('  |  Status:  [CONNECTED] -> {0,-50}|' -f $locStr) -ForegroundColor Green
        Write-Host '  |  Tunnel:  Local SOCKS5 on 127.0.0.1:7854  |  v2rayN Tun: ACTIVE              |' -ForegroundColor White
    } else {
        Write-Host '  |  Status:  [DISCONNECTED]                                                     |' -ForegroundColor Red
        Write-Host '  |  Tunnel:  Local SOCKS5 on 127.0.0.1:7854  |  v2rayN Tun: Standby             |' -ForegroundColor DarkGray
    }
    Write-Host '  +------------------------------------------------------------------------------+' -ForegroundColor DarkCyan

    if ($activeAcc) {
        $remGB = [math]::Round($activeAcc.RemainingBytes / 1GB, 2)
        $limGB = [math]::Round($activeAcc.LimitBytes / 1GB, 2)
        $usedGB = [math]::Round(($activeAcc.LimitBytes - $activeAcc.RemainingBytes) / 1GB, 2)
        $emailStr = if ($activeAcc.Email -and $activeAcc.Email -ne 'N/A') { $activeAcc.Email } else { 'irmahodev@gmail.com' }
        $lifecycle = Get-AccountLifecycle $activeAcc.CreatedAt $activeAcc.ResetDate

        $dataBar = Draw-Bar $activeAcc.RemainingBytes $activeAcc.LimitBytes 20

        Write-Host ''
        Write-Host '  +--[ ACTIVE ACCOUNT DETAILS ]--------------------------------------------------+' -ForegroundColor DarkCyan
        Write-Host ('  |  Gmail:     {0,-64}|' -f $emailStr) -ForegroundColor White
        Write-Host ('  |  UID:       {0,-20} Total Accounts: {1,-34}|' -f $activeAcc.Id, (Get-AccountList).Count) -ForegroundColor DarkGray
        Write-Host '  |                                                                              |' -ForegroundColor DarkCyan
        Write-Host ('  |  Quota:     {0}  {1} GB left of {2} GB (Used: {3} GB)       |' -f $dataBar, $remGB, $limGB, $usedGB) -ForegroundColor Yellow
        Write-Host ('  |  Activated: Today ({0}) on {1,-38}|' -f $lifecycle.Age, $lifecycle.ActivatedExact) -ForegroundColor Cyan
        Write-Host ('  |  Renewal:   {0} days remaining until 50 GB monthly reset ({1})   |' -f $lifecycle.DaysRemaining, $lifecycle.ResetDate) -ForegroundColor Green
        Write-Host '  +------------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    }

    Write-Host ''
    Write-Host '  +--[ DASHBOARD ACTIONS ]-------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |  [1] Live Ping and Switch Location (Ping all servers and switch country)     |' -ForegroundColor White
    Write-Host '  |  [2] Quick Connect Fastest Server  (Connect to lowest ping automatically)    |' -ForegroundColor White
    Write-Host '  |  [3] Multi-Account Manager         (View quotas, switch, login, create acc)  |' -ForegroundColor White
    Write-Host '  |  [4] GitHub Project and Updates    (Open https://github.com/IrMaho/FoxyVPN)  |' -ForegroundColor White
    Write-Host '  |  [5] Disconnect                    (Stop VPN engine)                         |' -ForegroundColor White
    Write-Host '  |  [0] Exit                          (Close program)                           |' -ForegroundColor White
    Write-Host '  +------------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
    
    $choice = Read-Host '  Select option [1, 2, 3, 4, 5, 0]'
    
    if ($choice -eq '1') {
        $pingList = Test-AllPings
        Write-Host ''
        Write-Host '  --- LIVE PING RANKING ---' -ForegroundColor Yellow
        $i = 1
        foreach ($p in $pingList) {
            $color = if ($p.Latency -lt 150) { 'Green' } elseif ($p.Latency -lt 300) { 'Yellow' } else { 'Red' }
            $latText = if ($p.Latency -eq 9999) { 'Timeout' } else { "$($p.Latency) ms" }
            Write-Host ('    [{0,2}] {1,-18} [{2,-3}] : {3,8}' -f $i, $p.Name, $p.Code, $latText) -ForegroundColor $color
            $i++
        }
        Write-Host ''
        $sel = Read-Host "  Select server number to connect [1-$($pingList.Count)] or Enter to cancel"
        $selNum = 0
        if ([int]::TryParse($sel, [ref]$selNum) -and $selNum -ge 1 -and $selNum -le $pingList.Count) {
            $target = $pingList[$selNum - 1]
            Start-VpnConnection $target.Code $target.Name
        }
        Start-Sleep -Seconds 1
    }
    elseif ($choice -eq '2') {
        $pingList = Test-AllPings
        $fastest = $pingList | Where-Object { $_.Latency -lt 9999 } | Select-Object -First 1
        if ($fastest) {
            Write-Host ''
            Write-Host "  [*] Fastest server: $($fastest.Name) [$($fastest.Code)] ($($fastest.Latency) ms)" -ForegroundColor Green
            Start-VpnConnection $fastest.Code $fastest.Name
        } else {
            Write-Host ''
            Write-Host '  [-] All servers timed out.' -ForegroundColor Red
        }
        Start-Sleep -Seconds 2
    }
    elseif ($choice -eq '3') {
        Show-AccountManager
    }
    elseif ($choice -eq '4') {
        Write-Host ''
        Write-Host '  [*] Opening https://github.com/IrMaho/FoxyVPN in your browser...' -ForegroundColor Cyan
        Start-Process 'https://github.com/IrMaho/FoxyVPN'
        Start-Sleep -Seconds 1
    }
    elseif ($choice -eq '5') {
        Stop-CurrentVpn
        Write-Host ''
        Write-Host '  [*] Disconnected.' -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    elseif ($choice -eq '0') {
        Stop-CurrentVpn
        Write-Host ''
        Write-Host '  Exiting. Goodbye!' -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        exit
    }
}
