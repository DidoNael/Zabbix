# http_check.ps1 — Tempo de resposta HTTP e código de status
# Uso: http_check.ps1 -Url https://www.google.com [-ReturnCode]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Url        = "https://www.google.com",
    [switch]$ReturnCode = $false
)

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $sw.Stop()

    if ($ReturnCode) {
        [int]$response.StatusCode
    } else {
        [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
    }
} catch {
    if ($ReturnCode) { 0 } else { 9999 }
}
