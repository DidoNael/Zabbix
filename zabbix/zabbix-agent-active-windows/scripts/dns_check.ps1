# dns_check.ps1 — Tempo de resolucao DNS e status
# Uso: dns_check.ps1 -Domain google.com -DnsServer 8.8.8.8 -Metric [resolve_time|status]
# Compativel com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Domain    = "google.com",
    [string]$DnsServer = "8.8.8.8",
    [string]$Metric    = "resolve_time"
)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

try {
    $sw     = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Resolve-DnsName -Name $Domain -Server $DnsServer -ErrorAction Stop -Type A
    $sw.Stop()

    $success = ($result -and $result.Count -gt 0)

    switch ($Metric) {
        "resolve_time" {
            if ($success) { [math]::Round($sw.Elapsed.TotalMilliseconds, 2) }
            else          { 9999 }
        }
        "status" {
            if ($success) { 1 } else { 0 }
        }
        default { -1 }
    }
} catch {
    switch ($Metric) {
        "resolve_time" { 9999 }
        "status"       { 0 }
        default        { -1 }
    }
}
