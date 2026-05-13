#requires -RunAsAdministrator

$PingTarget = "223.5.5.5"
$PingCount = 2

function Color {
    param($text, $color)
    Write-Host $text -ForegroundColor $color -NoNewline
}

function Get-NetCardInfo {
    $rawAdapters = Get-NetAdapter | Where-Object { $_.Name -notlike "Loopback*" }
    $adapters = $rawAdapters | Sort-Object -Property @{E={$_.Status -eq 'Up'}; A=$true}, @{E={
        $ls = $_.LinkSpeed
        $num = [double]($ls -replace '[^\d.]+')
        if ($ls -match 'Gbps') { $num * 1000 }
        elseif ($ls -match 'Mbps') { $num }
        else { 0 }
    }; A=$true}
    $result = @()
    foreach ($ad in $adapters) {
        $iface = Get-NetIPInterface -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $ipInfo = Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $ip = if ($ipInfo) { $ipInfo.IPAddress } else { "-" }
        $metric = if ($iface) {
            if ($iface.AutomaticMetric) { "自动" } else { "$($iface.InterfaceMetric)" }
        } else { "-" }
        $statusText = if ($ad.Status -eq "Up") { "已连" } else { "断开" }

        $result += [PSCustomObject]@{
            Index = $result.Count + 1
            Name = $ad.Name
            Status = $statusText
            IP = $ip
            Metric = $metric
            Speed = if ($ad.LinkSpeed) { $ad.LinkSpeed } else { "-" }
            PingMs = "-"
            LossPct = "-"
            IsUp = $ad.Status -eq "Up"
            IfIndex = $ad.ifIndex
        }
    }
    return $result
}

function Do-PingAll {
    param($cards)
    $online = $cards | Where-Object { $_.IsUp }
    if ($online.Count -eq 0) { return }

    $pingResults = @{}
    $jobs = @()
    foreach ($c in $online) {
        $jobs += Start-Job -ScriptBlock {
            param($target, $count, $idx)
            $rtts = @()
            $lost = 0
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $p = Test-Connection -ComputerName $target -Count 1 -ErrorAction Stop
                    $rtts += $p.ResponseTime
                } catch { $lost++ }
            }
            $avg = if ($rtts.Count -gt 0) { [math]::Round(($rtts | Measure-Object -Average).Average, 1) } else { $null }
            $lossPct = if ($count -gt 0) { [math]::Round($lost / $count * 100, 0) } else { 100 }
            return @{ Index = $idx; Avg = $avg; Loss = $lossPct }
        } -ArgumentList $PingTarget, $PingCount, $c.Index
    }

    $jobs | Wait-Job -Timeout 3 | Out-Null
    foreach ($j in $jobs) {
        if ($j.State -eq "Completed") {
            $r = Receive-Job $j
            $pingResults[$r.Index] = @{ Avg = $r.Avg; Loss = $r.Loss }
        }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
    }

    foreach ($c in $online) {
        if ($pingResults.ContainsKey($c.Index)) {
            $r = $pingResults[$c.Index]
            $c.PingMs = if ($r.Avg -ne $null) { "$($r.Avg)" } else { "-" }
            $c.LossPct = "$($r.Loss)%"
        }
    }
}

function Set-Metric {
    param($name, $metric)
    $iface = Get-NetIPInterface -InterfaceAlias $name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $iface) { return $false }
    if ($metric -eq "auto") {
        $iface | Set-NetIPInterface -AutomaticMetric Enabled
        Color "  [恢复自动] " Yellow; Write-Host $name
    } else {
        $iface | Set-NetIPInterface -InterfaceMetric $metric -AutomaticMetric Disabled
        Color "  [优先] " Green; Write-Host "$name -> 跃点 $metric"
    }
    return $true
}

Write-Host "`n"
Color "=== " Cyan; Color "NetMetric" White; Color " - 网卡跃点管理 ===" Cyan
Write-Host ""

$cards = Get-NetCardInfo
if ($cards.Count -eq 0) { Write-Host "未找到网卡。"; exit 1 }

#Write-Host "[debug] 排序后网卡顺序：" -ForegroundColor DarkGray
#$cards | ForEach-Object { Write-Host "  $_($($_.Index)): $($_.Name) $($_.Speed)" -ForegroundColor DarkGray }

Do-PingAll -cards $cards

$maxIdxLen = ($cards[-1].Index).ToString().Length
$idxFmt = "{$($maxIdxLen),$maxIdxLen}"

foreach ($c in $cards) {
    $idxStr = "序号$($c.Index)"
    Write-Host ""
    Color "$idxStr" Cyan; Write-Host ""

    if ($c.IsUp) {
        Color "  $($c.Name)`n" Green
        Color "  $($c.IP)`n" White
        Color "  $($c.Speed)`n" Magenta
        Color "  Ping: " White; Color "$($c.PingMs)" Yellow; Color "  Loss: " White; Color "$($c.LossPct)`n" $(
            if ($c.LossPct -eq "0%") { "Green" } else { "Red" }
        )
        Color "  跃点: " White; Color "$($c.Metric)`n" Gray
    } else {
        Color "  $($c.Name)`n" DarkGray
        Color "  $($c.IP)`n" DarkGray
        Color "  $($c.Speed)`n" DarkGray
        Color "  断开`n" DarkGray
        Color "  跃点: $($c.Metric)`n" DarkGray
    }
}

$connected = $cards | Where-Object { $_.IsUp }
if ($connected.Count -eq 0) { Write-Host "没有已连接的网卡。"; exit 1 }

Color "`n请选择优先网卡（输入序号，0为并列模式）: " Cyan

$inputOrder = Read-Host
$indices = $inputOrder -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ }
$parallelMode = $indices -contains 0
$indices = $indices | Where-Object { $_ -ne 0 }

$validCards = @()
foreach ($idx in $indices) {
    $matched = $connected | Where-Object { $_.Index -eq $idx }
    if ($matched) { $validCards += $matched }
}

Write-Host ""
Color "--- " Yellow; Color "变更预览" White; Color " ---" Yellow
Write-Host ""

if ($parallelMode) {
    Color "并列模式：所有网卡跃点设为 1" Yellow
    Write-Host ""
    foreach ($c in $cards) { Color "  $($c.Name) : " White; Color "$($c.Metric)" Yellow; Color " -> " White; Color "1`n" Green }
} elseif ($validCards.Count -gt 0) {
    $sn = $validCards | ForEach-Object { $_.Name }
    foreach ($c in $cards | Where-Object { $_.Name -in $sn }) {
        Color "  [优先] " Green; Color "$($c.Name) : " White; Color "$($c.Metric)" Yellow; Color " -> " White; Color "1`n" Green
    }
    foreach ($c in $cards | Where-Object { $_.Name -notin $sn -and $_.Metric -ne "自动" }) {
        Color "  [恢复自动] " Yellow; Write-Host $c.Name
    }
} else {
    Write-Host "无效输入。"; exit 1
}

Color "`n确认执行？" White; Color "(Y/n): " Cyan
$confirm = Read-Host
if ($confirm -eq "n" -or $confirm -eq "N") { Write-Host "已取消。"; exit 0 }

Write-Host ""
Color "--- " Yellow; Color "执行中" White; Color " ---" Yellow
Write-Host ""

if ($parallelMode) {
    foreach ($c in $cards) { Set-Metric -name $c.Name -metric 1 }
} else {
    $sn = $validCards | ForEach-Object { $_.Name }
    foreach ($c in $cards) {
        if ($c.Name -in $sn) { Set-Metric -name $c.Name -metric 1 } else { Set-Metric -name $c.Name -metric "auto" }
    }
}

Write-Host ""
Color "--- " Yellow; Color "完成" White; Color " ---" Yellow
Write-Host ""
$cards | ForEach-Object {
    $iface = Get-NetIPInterface -InterfaceAlias $_.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($iface) {
        $m = if ($iface.AutomaticMetric) { "自动" } else { "$($iface.InterfaceMetric)" }
        if ($iface.InterfaceMetric -eq 1) { Color "  $($_.Name) : 跃点 $m`n" Green }
        else { Color "  $($_.Name) : 跃点 $m`n" DarkGray }
    }
}