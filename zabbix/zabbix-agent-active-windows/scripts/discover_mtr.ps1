# discover_mtr.ps1 — LLD Discovery para targets de MTR
# Recebe lista de IPs/hosts separados por virgula, retorna JSON LLD para Zabbix
# Uso: discover_mtr.ps1 -Targets "google.com"
# ATENCAO: MTR pode demorar 2-5 min por target. Use poucos targets.
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
