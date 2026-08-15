# site_ping.ps1 — Ping dedicado por site/domínio com resolução DNS automática
# Uso: site_ping.ps1 -Target google.com -Metric [latency|loss|jitter] -Count 10
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Target = "google.com",
    [string]$Metric = "latency",
    [int]   $Count  = 10
)

# Resolve hostname para IP
try {
    $ip = ([System.Net.Dns]::GetHostAddresses($Target) |
           Where-Object { $_.AddressFamily -eq "InterNetwork" })[0].ToString()
} catch {
    if ($Metric -eq "loss") { Write-Output 100; exit }
    else                    { Write-Output 9999; exit }
}

$results = @()
$ping    = New-Object System.Net.NetworkInformation.Ping

for ($i = 0; $i -lt $Count; $i++) {
    try {
        $reply = $ping.Send($ip, 2000)
        if ($reply.Status -eq "Success") { $results += $reply.RoundtripTime }
        else                             { $results += $null }
    } catch { $results += $null }
    Start-Sleep -Milliseconds 300
}

$ok   = $results | Where-Object { $_ -ne $null }
$lost = $results | Where-Object { $_ -eq $null }

switch ($Metric) {
    "latency" {
        if ($ok.Count -gt 0) { [math]::Round(($ok | Measure-Object -Average).Average, 2) }
        else                 { 9999 }
    }
    "loss" {
        [math]::Round(($lost.Count / $Count) * 100, 2)
    }
    "jitter" {
        if ($ok.Count -gt 1) {
            $diffs = @()
            for ($i = 1; $i -lt $ok.Count; $i++) {
                $diffs += [math]::Abs($ok[$i] - $ok[$i-1])
            }
            [math]::Round(($diffs | Measure-Object -Average).Average, 2)
        } else { 0 }
    }
}
