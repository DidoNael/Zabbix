# discover_tracert.ps1 — LLD Discovery para targets de Traceroute
# Recebe lista de IPs/hosts separados por virgula, retorna JSON LLD para Zabbix
# Uso: discover_tracert.ps1 -Targets "google.com,cloudflare.com"
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Targets = "google.com"
)

$list = $Targets -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

$result = $list | ForEach-Object {
    [PSCustomObject]@{
        "{#TARGET}" = $_
    }
}

$result | ConvertTo-Json -Compress
