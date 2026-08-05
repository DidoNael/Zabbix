# nslookup_check.ps1 — Resolução DNS avançada com múltiplos servidores e tipos de registro
# Uso: nslookup_check.ps1 -Domain google.com -DnsServer 8.8.8.8 -Type A -Metric [time|ip|count|status]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Domain    = "google.com",
    [string]$DnsServer = "8.8.8.8",
    [string]$Type      = "A",      # Suporte: A, AAAA, MX, NS, TXT, CNAME
    [string]$Metric    = "time"
)

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $result = Resolve-DnsName -Name $Domain -Server $DnsServer -Type $Type `
              -ErrorAction Stop -DnsOnly

    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalMilliseconds, 2)

    $records = $result | Where-Object {
        $_.QueryType -eq $Type -or $_.Type -eq $Type
    }

    switch ($Metric) {
        "time" {
            $elapsed
        }
        "ip" {
            $ip = ($result | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
            if ($ip) { $ip } else { "N/A" }
        }
        "count" {
            if ($records) { @($records).Count }
            else          { ($result | Where-Object { $_.IPAddress -or $_.NameHost -or $_.Name }).Count }
        }
        "status" {
            if ($result -and $result.Count -gt 0) { 1 } else { 0 }
        }
    }
} catch {
    $sw.Stop()
    switch ($Metric) {
        "time"   { 9999 }
        "ip"     { "FAILED" }
        "count"  { 0 }
        "status" { 0 }
    }
}
