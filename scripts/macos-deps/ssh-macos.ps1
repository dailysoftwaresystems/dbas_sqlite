param(
    [Parameter(Mandatory = $true)][string]$HostName,
    [Parameter(Mandatory = $true)][string]$UserName
)

$ip = (Test-Connection $HostName -Count 1 -ErrorAction SilentlyContinue | Select-Object -First 1).IPv4Address.IPAddressToString

if (!$ip) {
    Write-Error "❌ It was not possible to resolve '$HostName' in current network."
}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$UserName@$ip"
