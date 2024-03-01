#Requires -Version 7

# 1. Update $ExsHosts and SNMP settings
# 2. Connect to the vCenter or the host via "Connect-VIServer -Server server-name" before running the script

# $EsxHosts = @('host1.example.com')
$EsxHosts = @('host2.example.com', 'host2.example.com')
# $EsxHosts = @(Get-VMHost -Location (Get-Cluster -Name 'example_cluster'))

# SNMP settings - begin
$ENGINE_STRING = 'x'
$USER = 'x'
$AUTH_PASSWORD = 'x'
$AUTH_PROTOCOL = 'SHA1'
$PRIV_PASSWORD = 'x'
$PRIV_PROTOCOL = 'AES128'
$SNMP_TARGET = ''  # if $SNMP_TARGET is set, the script configures the agent to send SNMP v3 traps
$SNMP_PORT = '161'
# SNMP settings - end

$SERVICE_NAME = 'snmpd'
$EngineID = ($ENGINE_STRING | Format-Hex).HexBytes -replace ' '

function Get-EsxSnmpInfo {
  [CmdletBinding()]
  param (
    [string]$EsxHost
  )

  $EsxCli = Get-EsxCli -V2 -VMHost $EsxHost
  $SnmpInfo = $EsxCli.system.snmp.get.Invoke()

  return $SnmpInfo
}

function Get-EsxServiceStatus {
  [CmdletBinding()]
  param (
    [string]$EsxHost,
    [string]$ServiceName
  )

  $ServiceStatus = (Get-VMHostService -VMHost $EsxHost | Where-Object { $_.Key -eq $ServiceName }).Running

  return $ServiceStatus

}

function Set-EsxSnmpv3 {
  [CmdletBinding()]
  param (
    [string]$EsxHost
  )

  $EsxCli = Get-EsxCli -V2 -VMHost $EsxHost

  # before configuing, return agent configuration to factory default to clear the existing configuration
  $SnmpArgs = $EsxCli.system.snmp.set.CreateArgs()
  $SnmpArgs['reset'] = 'true'
  $EsxCli.system.snmp.set.Invoke($SnmpArgs) | Out-Null

  $SnmpArgs = $EsxCli.system.snmp.set.CreateArgs()
  $SnmpArgs['engineid'] = $EngineID
  $SnmpArgs['authentication'] = $AUTH_PROTOCOL
  $SnmpArgs['privacy'] = $PRIV_PROTOCOL
  $EsxCli.system.snmp.set.Invoke($SnmpArgs) | Out-Null

  $HashArgs = $EsxCli.system.snmp.hash.CreateArgs()
  $HashArgs['authhash'] = $AUTH_PASSWORD
  $HashArgs['privhash'] = $PRIV_PASSWORD
  $HashArgs['rawsecret'] = 'true'
  $SnmpHash = $EsxCli.system.snmp.hash.Invoke($HashArgs)

  $SnmpArgs = $EsxCli.system.snmp.set.CreateArgs()
  $SnmpArgs['users'] = "$USER/$($SnmpHash.authhash)/$($SnmpHash.privhash)/priv"
  if ($SNMP_TARGET -ne '') {
    $SnmpArgs['v3targets'] = "$SNMP_TARGET@$SNMP_PORT/$USER/priv/trap"
  }
  $SnmpArgs['enable'] = 'true'
  $EsxCli.system.snmp.set.Invoke($SnmpArgs) | Out-Null
}

foreach ($EsxHost in $EsxHosts) {
  Write-Output "${EsxHost}: Checking SNMP info ..."
  $EsxHostSnmpInfo = Get-EsxSnmpInfo -EsxHost $EsxHost
  $EsxServiceStatus = Get-EsxServiceStatus -EsxHost $EsxHost -ServiceName $SERVICE_NAME

  # based on the Esx host's SNMP service status (running), policy (on), and Engine ID
  # to determine if the host requires to be configured
  if (($EsxServiceStatus -eq 'true') -and
      ($EsxHostSnmpInfo.enable -eq 'true') -and
      ($EsxHostSnmpInfo.engineid -eq $EngineID)) {
    Write-Output "${EsxHost}: SNMP is configured"
  }
  else {
    Write-Output "${EsxHost}: SNMP is not configured. Configuing SNMP ..."
    Set-EsxSnmpv3 -EsxHost $EsxHost
  }

  $EsxHostSnmpInfo = Get-EsxSnmpInfo -EsxHost $EsxHost
  Write-Output "${EsxHost}: SNMP info ..." $($EsxHostSnmpInfo)
}
