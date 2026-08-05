# ping_check.ps1 — Latência, perda de pacotes e jitter via ICMP
# Uso: ping_check.ps1 -Target 8.8.8.8 -Metric [latency|loss|jitter] -Count 10
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Target  = "8.8.8.8",
    [string]$Metric  = "latency",
    [int]   $Count   = 10
)

$results = @()

for ($i = 0; $i -lt $Count; $i++) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $ping.Send($Target, 2000)
        if ($reply.Status -eq "Success") {
            $results += $reply.RoundtripTime
        } else {
            $results += $null
        }
    } catch {
        $results += $null
    }
    Start-Sleep -Milliseconds 200
}

$successful = $results | Where-Object { $_ -ne $null }
$lost       = $results | Where-Object { $_ -eq $null }

switch ($Metric) {
    "latency" {
        if ($successful.Count -gt 0) {
            [math]::Round(($successful | Measure-Object -Average).Average, 2)
        } else { 9999 }
    }
    "loss" {
        [math]::Round(($lost.Count / $Count) * 100, 2)
    }
    "jitter" {
        if ($successful.Count -gt 1) {
            $diffs = @()
            for ($i = 1; $i -lt $successful.Count; $i++) {
                $diffs += [math]::Abs($successful[$i] - $successful[$i-1])
            }
            [math]::Round(($diffs | Measure-Object -Average).Average, 2)
        } else { 0 }
    }
}
