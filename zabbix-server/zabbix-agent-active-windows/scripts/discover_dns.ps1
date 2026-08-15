# discover_dns.ps1 — LLD Discovery para combinacoes Dominio x Servidor DNS
# Gera produto cartesiano: cada dominio testado em cada servidor DNS
# Uso: discover_dns.ps1 -Domains "google.com,meusite.com.br" -Servers "8.8.8.8,1.1.1.1"
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Domains = "google.com",
    [string]$Servers = "8.8.8.8,1.1.1.1"
)

$domainList = $Domains -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
$serverList = $Servers -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

$result = @()
foreach ($domain in $domainList) {
    foreach ($server in $serverList) {
        $result += [PSCustomObject]@{
            "{#DNS_DOMAIN}" = $domain
            "{#DNS_SERVER}" = $server
        }
    }
}

$result | ConvertTo-Json -Compress
