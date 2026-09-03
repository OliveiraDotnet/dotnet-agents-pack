param(
    [Parameter(Mandatory = $true)]
    [string]$Server,

    [int]$Port = 1433,

    [int]$TimeoutMs = 3000
)

$ErrorActionPreference = "Stop"

$result = [ordered]@{
    Server = $Server
    Port = $Port
    DnsResolved = $false
    Addresses = @()
    TcpReachable = $false
    ElapsedMs = $null
    LikelyIssue = $null
    Recommendation = $null
    Notes = @()
}

if ($Server -match "\\") {
    $result.Notes += "Named instance detected. SQL Browser or a dynamic port may be involved; specify the actual TCP port when known."
}

try {
    $addresses = [System.Net.Dns]::GetHostAddresses($Server)
    $result.DnsResolved = $addresses.Count -gt 0
    $result.Addresses = $addresses | ForEach-Object { $_.IPAddressToString }
} catch {
    $result.LikelyIssue = "DNS resolution failed"
    $result.Recommendation = "Confirm VPN/private DNS is connected, server name is correct, or use a resolvable host/IP. Do not retry database login until DNS works."
    [pscustomobject]$result
    exit 0
}

$client = [System.Net.Sockets.TcpClient]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $connectTask = $client.ConnectAsync($Server, $Port)
    if (-not $connectTask.Wait($TimeoutMs)) {
        $result.LikelyIssue = "TCP connection timed out"
        $result.Recommendation = "Confirm VPN, firewall, port, SQL Server listener, and network route. Switch to user-run metadata collection if Codex is sandboxed away from the network."
    } elseif ($client.Connected) {
        $result.TcpReachable = $true
        $result.LikelyIssue = "Network path is reachable"
        $result.Recommendation = "Proceed only with authorized read-only metadata collection. This preflight did not authenticate or query SQL Server."
    }
} catch {
    $result.LikelyIssue = "TCP connection failed"
    $result.Recommendation = "Confirm VPN, firewall, SQL Server port, server alias, and whether access must happen from the user's machine outside the sandbox."
    $result.Notes += $_.Exception.Message
} finally {
    $stopwatch.Stop()
    $result.ElapsedMs = $stopwatch.ElapsedMilliseconds
    $client.Dispose()
}

[pscustomobject]$result
