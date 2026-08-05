# mtr_check.ps1 — MTR via NextTrace (nexttrace.exe)
# Pre-requisito: nexttrace.exe + WinDivert em C:\zabbix\scripts\
#   Inicializar WinDivert (uma vez, como Admin): nexttrace.exe --init
# Download: https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_windows_amd64.exe
# Uso: mtr_check.ps1 -Target google.com -Metric [avg_rtt|loss|report]
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Target  = "google.com",
    [string]$Metric  = "avg_rtt",
    [int]   $Queries = 8
)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$exe = "C:\zabbix\scripts\nexttrace.exe"
if (-not (Test-Path $exe)) {
    if ($Metric -eq "report") { Write-Output "nexttrace.exe nao encontrado em C:\zabbix\scripts\" }
    else { Write-Output 9999 }
    exit 0
}

function Get-StDev($values) {
    if ($values.Count -lt 2) { return 0.0 }
    $avg  = ($values | Measure-Object -Average).Average
    $sum  = ($values | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Sum).Sum
    [math]::Round([math]::Sqrt($sum / ($values.Count - 1)), 1)
}

try {
    # TCP 443 mostra hops intermediarios que ICMP nao revela (ISPs filtram ICMP TTL-exceeded)
    # Requer WinDivert: nexttrace.exe --init (executar uma vez como Admin)
    $raw  = & $exe --tcp --port 443 --json --queries $Queries --no-rdns $Target 2>$null
    $json = ($raw | Where-Object { $_ -match '^\{' }) -join ''
    $data = $json | ConvertFrom-Json

    # Busca o hop que contem o IP de destino
    $lastHop = $null
    foreach ($hop in $data.Hops) {
        if (@($hop | Where-Object { $_.Address -and $_.Address.IP -eq $Target }).Count -gt 0) {
            $lastHop = $hop
            break
        }
    }
    # Se destino nao respondeu ao TCP (ex: porta fechada), usa ultimo hop com resposta
    if (-not $lastHop) {
        $lastHop = $data.Hops | Where-Object {
            ($_ | Where-Object { $_.Success -eq $true }).Count -gt 0
        } | Select-Object -Last 1
    }

    if (-not $lastHop) {
        if ($Metric -eq "report") { Write-Output "Sem rota para $Target" }
        else { Write-Output 9999 }
        exit 0
    }

    switch ($Metric) {
        "avg_rtt" {
            $ok    = $lastHop | Where-Object { $_.Success }
            $avgNs = ($ok | Measure-Object -Property RTT -Average).Average
            [math]::Round($avgNs / 1000000, 2)
        }
        "loss" {
            $lost  = ($lastHop | Where-Object { -not $_.Success }).Count
            [math]::Round(($lost / $lastHop.Count) * 100, 1)
        }
        "report" {
            $hostname = $env:COMPUTERNAME
            $start    = Get-Date -Format "ddd MMM  d HH:mm:ss yyyy"
            $lines    = @("Start: $start", "HOST: $hostname$((' ' * [math]::Max(1, 30 - $hostname.Length)))Loss%   Snt   Last   Avg  Best  Wrst StDev")

            $hopNum = 1
            foreach ($hop in $data.Hops) {
                $ok    = @($hop | Where-Object { $_.Success })
                $total = $hop.Count
                $lost  = $total - $ok.Count
                $lossP = [math]::Round(($lost / $total) * 100, 1)

                if ($ok.Count -gt 0) {
                    $rtts  = $ok | ForEach-Object { [math]::Round($_.RTT / 1000000, 1) }
                    $last  = $rtts[-1]
                    $avg   = [math]::Round(($rtts | Measure-Object -Average).Average, 1)
                    $best  = [math]::Round(($rtts | Measure-Object -Minimum).Minimum, 1)
                    $wrst  = [math]::Round(($rtts | Measure-Object -Maximum).Maximum, 1)
                    $stdev = Get-StDev $rtts
                    $addr  = $ok[0].Address.IP
                    if (-not $addr) { $addr = "???" }
                } else {
                    # Pular hops sem resposta
                    $hopNum++
                    continue
                }

                $pad   = ' ' * [math]::Max(1, 36 - $addr.Length)
                $lines += "{0,3}.|-- {1}{2}{3,5}%{4,6}{5,7}{6,7}{7,7}{8,7}{9,7}" -f `
                    $hopNum, $addr, $pad, $lossP, $total, $last, $avg, $best, $wrst, $stdev
                $hopNum++
            }
            $lines -join "`n"
        }
        default { 9999 }
    }
} catch {
    if ($Metric -eq "report") { Write-Output "Erro: $_" } else { 9999 }
}
