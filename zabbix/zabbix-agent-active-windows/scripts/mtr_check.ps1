# mtr_check.ps1 — MTR via NextTrace (nexttrace.exe)
# Pre-requisito: nexttrace.exe em C:\zabbix\scripts\
# Download: https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_windows_amd64.exe
# Uso: mtr_check.ps1 -Target google.com -Metric [avg_rtt|loss]
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Target  = "google.com",
    [string]$Metric  = "avg_rtt",
    [int]   $Queries = 5
)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$exe = "C:\zabbix\scripts\nexttrace.exe"
if (-not (Test-Path $exe)) { Write-Output 9999; exit 0 }

try {
    $raw  = & $exe --json --queries $Queries --no-rdns $Target 2>$null
    $json = ($raw | Where-Object { $_ -match '^\{' }) -join ''
    $data = $json | ConvertFrom-Json

    # Ultimo hop com pelo menos uma probe bem-sucedida
    $lastHop = $data.Hops | Where-Object {
        ($_ | Where-Object { $_.Success -eq $true }).Count -gt 0
    } | Select-Object -Last 1

    if (-not $lastHop) { Write-Output 9999; exit 0 }

    $successful = $lastHop | Where-Object { $_.Success -eq $true }
    $total      = $lastHop.Count

    switch ($Metric) {
        "avg_rtt" {
            # RTT em nanosegundos -> milissegundos
            $avgNs = ($successful | Measure-Object -Property RTT -Average).Average
            [math]::Round($avgNs / 1000000, 2)
        }
        "loss" {
            $lost = ($lastHop | Where-Object { $_.Success -eq $false }).Count
            [math]::Round(($lost / $total) * 100, 1)
        }
        default { 9999 }
    }
} catch {
    9999
}
