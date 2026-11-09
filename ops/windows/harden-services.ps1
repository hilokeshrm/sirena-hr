<#
.SYNOPSIS
  Runs the API and Caddy under their own limited Windows accounts instead of LocalSystem.

.DESCRIPTION
  LocalSystem can do anything on this machine, so a bug in the API or Caddy would give an attacker
  the whole server. Virtual service accounts (NT SERVICE\SirenaApi, NT SERVICE\SirenaCaddy) have no
  password and can only touch what is granted: the API reads its .env and writes uploaded files and
  logs; Caddy reads the TLS certificate and writes its logs. PostgreSQL already runs as its own account.

  The services restart (about 10 seconds of downtime). If the API or website does not come back,
  both are switched back to LocalSystem automatically.

.EXAMPLE
  .\harden-services.ps1          # switch to the limited accounts
  .\harden-services.ps1 -Undo    # back to LocalSystem
#>
param([switch]$Undo)

. "$PSScriptRoot\lib\common.ps1"
Assert-Admin
$cfg = Get-SirenaConfig

function Set-Account([string]$Service, [string]$Account) {
  if ($Account -eq 'LocalSystem') { Invoke-Native sc.exe @('config', $Service, 'obj=', 'LocalSystem') | Out-Null }
  else { Invoke-Native sc.exe @('config', $Service, 'obj=', $Account, 'password=', '') | Out-Null }
}

function Restart-Both {
  Stop-ApiService
  Restart-Service $CaddyService -Force
  Start-Service $ApiService
}

function Test-Website {
  $url = Get-PublicUrl
  $a = @('-k', '-fsS', '-o', 'NUL', '--max-time', '10')
  if ($cfg.DirectAccess) { $a += @('--resolve', "$($cfg.PublicIp):$($cfg.PublicPort):127.0.0.1") }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & curl.exe @a "$url/api/health" 2>&1 | Out-Null
  $ok = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $old
  $ok
}

if ($Undo) {
  Write-Step 'Switching services back to LocalSystem'
  Set-Account $ApiService 'LocalSystem'
  Set-Account $CaddyService 'LocalSystem'
  Restart-Both
  Write-Ok "API healthy: $(Test-ApiHealth)"
  return
}

Write-Step 'Granting the service accounts what they need'
Invoke-Native (Join-Path $ToolsBin 'nssm.exe') @('set', $CaddyService, 'AppEnvironmentExtra', "XDG_DATA_HOME=$CaddyDataDir", "XDG_CONFIG_HOME=$CaddyDataDir") | Out-Null
Grant-ServiceAccess
Write-Ok "$ApiAccount and $CaddyAccount granted access"

Write-Step 'Switching services to their own accounts'
Set-Account $ApiService $ApiAccount
Set-Account $CaddyService $CaddyAccount
Restart-Both

if ((Test-ApiHealth) -and (Test-Website)) {
  Write-Ok "API runs as $ApiAccount, Caddy as $CaddyAccount; site healthy"
} else {
  Write-Note 'The API or website did not come back; switching both to LocalSystem. Check C:\sirena\logs\api.log and caddy.log.'
  Set-Account $ApiService 'LocalSystem'
  Set-Account $CaddyService 'LocalSystem'
  Restart-Both
  throw "Still on LocalSystem (API healthy: $(Test-ApiHealth))."
}
