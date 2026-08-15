# site_http.ps1 — Tempo de resposta HTTP, código de status e validade SSL por site
# Uso: site_http.ps1 -Url https://site.com -Metric [time|status|ssl_days]
# Compatível com: Zabbix 6.0 + Windows Agent Active
param(
    [string]$Url    = "https://www.google.com",
    [string]$Metric = "time"
)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Ignora erros de certificado para medição de tempo
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAll : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) { return true; }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
[System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12

# ─── Tempo de resposta e código HTTP ─────────────────────────────────────────
if ($Metric -eq "time" -or $Metric -eq "status") {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout   = 15000
        $req.Method    = "GET"
        $req.UserAgent = "ZabbixMonitor/1.0"
        $resp = $req.GetResponse()
        $sw.Stop()
        $code = [int]$resp.StatusCode
        $resp.Close()

        if ($Metric -eq "time")   { [math]::Round($sw.Elapsed.TotalMilliseconds, 2) }
        if ($Metric -eq "status") { $code }
    } catch [System.Net.WebException] {
        $code = [int]$_.Exception.Response.StatusCode
        if ($Metric -eq "time")   { 9999 }
        if ($Metric -eq "status") { if ($code) { $code } else { 0 } }
    } catch {
        if ($Metric -eq "time")   { 9999 }
        if ($Metric -eq "status") { 0 }
    }
}

# ─── Dias restantes do certificado SSL ───────────────────────────────────────
if ($Metric -eq "ssl_days") {
    try {
        $uri       = [System.Uri]$Url
        $tcpClient = New-Object System.Net.Sockets.TcpClient($uri.Host, 443)
        $ssl = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false,
            { param($s,$c,$ch,$e) $true })
        $ssl.AuthenticateAsClient($uri.Host)
        $cert   = $ssl.RemoteCertificate
        $expiry = [DateTime]::Parse($cert.GetExpirationDateString())
        $days   = ($expiry - (Get-Date)).Days
        $ssl.Close(); $tcpClient.Close()
        $days
    } catch {
        -1
    }
}
