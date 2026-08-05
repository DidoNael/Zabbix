# speedtest.ps1 — Velocidade de download e upload via Speedtest CLI (Ookla)
# Pré-requisito: winget install Ookla.Speedtest
# Uso: speedtest.ps1 -Metric [download|upload]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Metric = "download"
)

try {
    $json = & "C:\Program Files\Speedtest CLI\speedtest.exe" --format=json --accept-license --accept-gdpr 2>$null
    $data = $json | ConvertFrom-Json

    switch ($Metric) {
        "download" { [math]::Round($data.download.bandwidth / 125000, 2) }
        "upload"   { [math]::Round($data.upload.bandwidth   / 125000, 2) }
        default    { 0 }
    }
} catch {
    0
}
