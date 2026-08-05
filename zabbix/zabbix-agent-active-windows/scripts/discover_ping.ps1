# discover_ping.ps1 — LLD Discovery para targets de Ping
# Recebe lista de IPs/hosts separados por virgula, retorna JSON LLD para Zabbix
# Uso: discover_ping.ps1 -Targets "8.8.8.8,1.1.1.1,google.com"
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Targets = "8.8.8.8,1.1.1.1"
)

$list = $Targets -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

$result = $list | ForEach-Object {
    [PSCustomObject]@{
        "{#TARGET}" = $_
    }
}

$result | ConvertTo-Json -Compress
