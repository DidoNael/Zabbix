# dns_check.ps1 — Tempo de resolução DNS
# Uso: dns_check.ps1 -Domain www.google.com -DnsServer 8.8.8.8
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Domain    = "www.google.com",
    [string]$DnsServer = "8.8.8.8"
)

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Resolve-DnsName -Name $Domain -Server $DnsServer -ErrorAction Stop -Type A
    $sw.Stop()

    if ($result) {
        [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
    } else {
        9999
    }
} catch {
    9999
}
