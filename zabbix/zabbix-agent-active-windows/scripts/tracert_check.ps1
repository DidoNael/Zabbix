# tracert_check.ps1 — Traceroute com extração de métricas por hop
# Uso: tracert_check.ps1 -Target google.com -Metric [hops|last_rtt|max_rtt|json]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Target  = "google.com",
    [string]$Metric  = "hops",
    [int]   $MaxHops = 30,
    [int]   $Timeout = 3000
)

function Invoke-Traceroute {
    param([string]$Target, [int]$MaxHops, [int]$Timeout)

    $hops = @()
    $ping = New-Object System.Net.NetworkInformation.Ping

    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $options = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
        $rtts    = @()
        $hopIp   = "*"

        # 3 tentativas por hop (padrão tracert)
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                $reply = $ping.Send($Target, $Timeout, [byte[]]@(0x61..0x77), $options)
                if ($reply.Status -eq "TtlExpired" -or $reply.Status -eq "Success") {
                    $hopIp = $reply.Address.ToString()
                    $rtts += $reply.RoundtripTime
                }
            } catch { }
        }

        $avg = if ($rtts.Count -gt 0) {
            [math]::Round(($rtts | Measure-Object -Average).Average, 2)
        } else { $null }

        $hops += [PSCustomObject]@{
            Hop    = $ttl
            IP     = $hopIp
            RTTs   = $rtts
            AvgRTT = $avg
        }

        # Verifica se chegou ao destino
        $reply2 = $null
        try {
            $opt2   = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
            $reply2 = $ping.Send($Target, $Timeout, [byte[]]@(0x61..0x77), $opt2)
        } catch { }
        if ($reply2 -and $reply2.Status -eq "Success") { break }
    }
    return $hops
}

$hops      = Invoke-Traceroute -Target $Target -MaxHops $MaxHops -Timeout $Timeout
$validHops = $hops | Where-Object { $_.AvgRTT -ne $null }

switch ($Metric) {
    "hops" {
        $hops.Count
    }
    "last_rtt" {
        if ($validHops.Count -gt 0) { ($validHops | Select-Object -Last 1).AvgRTT }
        else                        { 9999 }
    }
    "max_rtt" {
        if ($validHops.Count -gt 0) {
            ($validHops | Measure-Object -Property AvgRTT -Maximum).Maximum
        } else { 9999 }
    }
    "json" {
        $output = $hops | ForEach-Object {
            [PSCustomObject]@{
                hop    = $_.Hop
                ip     = $_.IP
                avg_ms = $_.AvgRTT
            }
        }
        $output | ConvertTo-Json -Compress
    }
}
