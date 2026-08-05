# discover_http.ps1 — LLD Discovery para targets HTTP
# Recebe lista de URLs separadas por virgula, retorna JSON LLD com {#URL} e {#HOST}
# Uso: discover_http.ps1 -Targets "https://google.com,https://meusite.com.br"
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Targets = "https://www.google.com"
)

$list = $Targets -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

$result = $list | ForEach-Object {
    $url = $_
    try {
        $uri  = [System.Uri]$url
        $host = $uri.Host
    } catch {
        $host = $url -replace "https?://", "" -replace "/.*", ""
    }
    [PSCustomObject]@{
        "{#URL}"  = $url
        "{#HOST}" = $host
    }
}

$result | ConvertTo-Json -Compress
