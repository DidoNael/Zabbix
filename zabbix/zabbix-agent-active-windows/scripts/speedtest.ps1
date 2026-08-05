# speedtest.ps1 — Velocidade de download e upload via Speedtest CLI (Ookla)
# Pre-requisito: winget install Ookla.Speedtest.CLI
# Uso: speedtest.ps1 -Metric [download|upload]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Metric = "download"
)

[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Localizar o executavel — copiar para C:\zabbix\scripts\ para acesso pelo servico SYSTEM
$exe = "C:\zabbix\scripts\speedtest.exe"
if (-not (Test-Path $exe)) { $exe = (Get-Command speedtest -ErrorAction SilentlyContinue).Source }
if (-not $exe -or -not (Test-Path $exe)) { Write-Output 0; exit 0 }

try {
    $ErrorActionPreference = 'SilentlyContinue'
    $raw  = $exe | ForEach-Object { & $_ --format=json --accept-license --accept-gdpr }
    $json = ($raw | Where-Object { $_ -match '^\{' }) -join ''
    $data = $json | ConvertFrom-Json

    switch ($Metric) {
        "download" { [math]::Round($data.download.bandwidth / 125000, 2) }
        "upload"   { [math]::Round($data.upload.bandwidth   / 125000, 2) }
        default    { 0 }
    }
} catch {
    0
}
