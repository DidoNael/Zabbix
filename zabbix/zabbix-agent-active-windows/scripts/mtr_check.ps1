# mtr_check.ps1 — MTR simulado: múltiplos pings por hop com estatísticas
# Uso: mtr_check.ps1 -Target google.com -Metric [avg_rtt|max_rtt|loss|json]
# Compatível com: Zabbix 6.0 + Windows Agent Active
# ATENÇÃO: Pode demorar 2-5 minutos. Recomenda-se intervalo mínimo de 15 minutos no Zabbix.
param(
    [string]$Target      = "google.com",
    [string]$Metric      = "avg_rtt",
    [int]   $MaxHops     = 30,
    [int]   $PingsPerHop = 10,
    [int]   $Timeout     = 2000
)

function Invoke-MTR {
    param([string]$Target, [int]$MaxHops, [int]$PingsPerHop, [int]$Timeout)

    $report = @()
    $ping   = New-Object System.Net.NetworkInformation.Ping

    # Descobrir IPs de cada hop (1 ping por TTL)
    $hopIPs = @{}
    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $opt = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
        try {
            $r = $ping.Send($Target, $Timeout, [byte[]]@(0x61..0x77), $opt)
            if ($r.Status -eq "TtlExpired" -or $r.Status -eq "Success") {
                $hopIPs[$ttl] = $r.Address.ToString()
            }
        } catch { $hopIPs[$ttl] = "*" }

        $opt2 = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
        try {
            $final = $ping.Send($Target, $Timeout, [byte[]]@(0x61..0x77), $opt2)
            if ($final.Status -eq "Success") { break }
        } catch { }
    }

    # Para cada hop descoberto, enviar múltiplos pings
    foreach ($ttl in ($hopIPs.Keys | Sort-Object)) {
        $ip   = $hopIPs[$ttl]
        $rtts = @()
        $lost = 0

        if ($ip -ne "*") {
            for ($p = 0; $p -lt $PingsPerHop; $p++) {
                try {
                    $r = $ping.Send($ip, $Timeout)
                    if ($r.Status -eq "Success") { $rtts += $r.RoundtripTime }
                    else                          { $lost++ }
                } catch { $lost++ }
                Start-Sleep -Milliseconds 100
            }
        } else {
            $lost = $PingsPerHop
        }

        $avg  = if ($rtts.Count -gt 0) { [math]::Round(($rtts | Measure-Object -Average).Average, 2) } else { $null }
        $max  = if ($rtts.Count -gt 0) { ($rtts | Measure-Object -Maximum).Maximum } else { $null }
        $loss = [math]::Round(($lost / $PingsPerHop) * 100, 1)

        $report += [PSCustomObject]@{
            Hop    = $ttl
            IP     = $ip
            AvgRTT = $avg
            MaxRTT = $max
            Loss   = $loss
        }
    }
    return $report
}

$report    = Invoke-MTR -Target $Target -MaxHops $MaxHops -PingsPerHop $PingsPerHop -Timeout $Timeout
$lastValid = $report | Where-Object { $_.AvgRTT -ne $null } | Select-Object -Last 1

switch ($Metric) {
    "avg_rtt" {
        if ($lastValid) { $lastValid.AvgRTT } else { 9999 }
    }
    "max_rtt" {
        if ($lastValid) { $lastValid.MaxRTT } else { 9999 }
    }
    "loss" {
        if ($lastValid) { $lastValid.Loss } else { 100 }
    }
    "json" {
        $report | ConvertTo-Json -Compress
    }
}
