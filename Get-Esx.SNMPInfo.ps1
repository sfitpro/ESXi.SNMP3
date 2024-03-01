# $EsxHosts = @('host1.example.com')
$EsxHosts = @('host2.example.com', 'host2.example.com')
# $EsxHosts = @(Get-VMHost -Location (Get-Cluster -Name 'example_cluster'))

function Get-EsxSnmpInfo {
  [CmdletBinding()]
  param (
    [string]$EsxHost
  )

  $EsxCli = Get-EsxCli -V2 -VMHost $EsxHost
  $SnmpInfo = $EsxCli.system.snmp.get.Invoke()

  return $SnmpInfo
}

foreach ($EsxHost in $EsxHosts) {
  Write-Output "${EsxHost}: Checking SNMP info ..."
  $EsxHostSnmpInfo = Get-EsxSnmpInfo -EsxHost $EsxHost
  Write-Output $EsxHostSnmpInfo
}
