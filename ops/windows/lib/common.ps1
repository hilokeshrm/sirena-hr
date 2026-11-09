# Shared helpers for the Sirena HR server scripts. Dot-source this file; don't run it.
# Works in Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SirenaRoot = 'C:\sirena'
$ConfigPath = Join-Path $SirenaRoot 'config.psd1'
$SecretsDir = Join-Path $SirenaRoot 'secrets'
$LogsDir = Join-Path $SirenaRoot 'logs'
$RepoDir = Join-Path $SirenaRoot 'repo'
$WwwDir = Join-Path $SirenaRoot 'www'
$BackupsDir = Join-Path $SirenaRoot 'backups'
$PgDataDir = Join-Path $SirenaRoot 'pgdata'
$ToolsBin = Join-Path $SirenaRoot 'tools\bin'
$FlutterBat = Join-Path $SirenaRoot 'tools\flutter\bin\flutter.bat'
$AllowlistPath = Join-Path $SirenaRoot 'allowlist.json'
$CloudflareIpsPath = Join-Path $SirenaRoot 'cloudflare-ips.txt'
$AdminKeysPath = 'C:\ProgramData\ssh\administrators_authorized_keys'
$TailscaleRange = '100.64.0.0/10'

$PgService = 'sirena-postgres'
$ApiService = 'SirenaApi'
$CaddyService = 'SirenaCaddy'
$DbName = 'sirena_hr'

# Which secret file holds each database role's password.
$RoleSecrets = @{ postgres = 'pg-superuser'; sirena_app = 'db-app'; sirena_admin = 'db-admin'; sirena_ro = 'db-ro' }

# ── Output ──────────────────────────────────────────────────────────────

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "    $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an Administrator PowerShell (right-click PowerShell > Run as administrator).'
  }
}

function Get-SirenaConfig {
  if (-not (Test-Path $ConfigPath)) { throw "No config at $ConfigPath. Run setup.ps1 first." }
  Import-PowerShellDataFile $ConfigPath
}

# False skips the Tailscale sign-in and drops the Tailscale range from the SSH rule. Defaults to true.
function Test-UseTailscale { $c = Get-SirenaConfig; if ($null -eq $c.UseTailscale) { $true } else { [bool]$c.UseTailscale } }

# True lets SSH accept Windows account passwords as well as keys. Defaults to false (keys only).
function Test-SshPasswordAuth { $c = Get-SirenaConfig; if ($null -eq $c.SshPasswordAuth) { $false } else { [bool]$c.SshPasswordAuth } }

# Port sshd listens on. Defaults to 22.
function Get-SshPort { $c = Get-SirenaConfig; if ($c.SshPort) { [int]$c.SshPort } else { 22 } }

# False keeps Postgres on localhost only: no remote listener, firewall rule or pg_hba entries.
# Defaults to false: reach the database through an SSH tunnel unless DbExposed = $true is set on purpose.
function Test-DbExposed { $c = Get-SirenaConfig; if ($null -eq $c.DbExposed) { $false } else { [bool]$c.DbExposed } }

# Local port the API listens on. Defaults to 3000; set ApiPort in config.psd1 if something else uses it.
function Get-ApiPort { $c = Get-SirenaConfig; if ($c.ApiPort) { [int]$c.ApiPort } else { 3000 } }

# Address browsers and the app use: https://<PublicIp>:<PublicPort> in direct mode, else https://<Domain>.
function Get-PublicUrl {
  $c = Get-SirenaConfig
  if ($c.DirectAccess) { "https://$($c.PublicIp):$($c.PublicPort)" } else { "https://$($c.Domain)" }
}

function Update-PathFromRegistry {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ── Native commands ─────────────────────────────────────────────────────

# Runs a program, returns its output lines, and throws with the output if it exits non-zero.
# Native stderr is captured as text so it doesn't trip $ErrorActionPreference = 'Stop'.
function Invoke-Native {
  param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @(), [string]$WorkDir, [int[]]$OkCodes = @(0))
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  if ($WorkDir) { Push-Location $WorkDir }
  try {
    $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally {
    if ($WorkDir) { Pop-Location }
    $ErrorActionPreference = $old
  }
  if ($OkCodes -notcontains $code) {
    $tail = ($out | Select-Object -Last 40) -join "`n"
    throw "$Exe $($Arguments -join ' ') exited with $code`n$tail"
  }
  $out
}

# ── Secrets ─────────────────────────────────────────────────────────────

function New-RandomString([int]$Length = 32) {
  # Letters and digits only, so values are safe in URLs, SQL literals and .env files.
  $chars = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  $bytes = New-Object byte[] $Length
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# Restricts a folder to Administrators and SYSTEM (by SID, so it works on any Windows language).
function Protect-Folder([string]$Path) {
  Invoke-Native icacls.exe @($Path, '/inheritance:r', '/grant:r', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F') | Out-Null
}

function Get-Secret([string]$Name) {
  $file = Join-Path $SecretsDir "$Name.txt"
  if (-not (Test-Path $file)) { throw "Missing secret $file" }
  (Get-Content $file -Raw).Trim()
}

# Creates the secret once; later runs keep the existing value.
function Initialize-Secret([string]$Name, [int]$Length = 32) {
  $file = Join-Path $SecretsDir "$Name.txt"
  if (-not (Test-Path $file)) { [IO.File]::WriteAllText($file, (New-RandomString $Length)) }
  Get-Secret $Name
}

# ── PostgreSQL ──────────────────────────────────────────────────────────

function Get-PgBin {
  $cfg = Get-SirenaConfig
  "C:\Program Files\PostgreSQL\$($cfg.PgMajor)\bin"
}

# Runs SQL through psql on this machine. Defaults to the postgres superuser.
function Invoke-Psql {
  param([Parameter(Mandatory)][string]$Sql, [string]$Database = 'postgres', [string]$User = 'postgres', [switch]$Scalar, [switch]$Table, [int]$Port = 0)
  $cfg = Get-SirenaConfig
  if (-not $Port) { $Port = $cfg.PgPort }
  $tmp = [IO.Path]::GetTempFileName()
  [IO.File]::WriteAllText($tmp, $Sql, (New-Object Text.UTF8Encoding $false))
  $env:PGPASSWORD = Get-Secret $RoleSecrets[$User]
  try {
    $a = @('-h', '127.0.0.1', '-p', "$Port", '-U', $User, '-d', $Database, '-v', 'ON_ERROR_STOP=1', '-X', '-f', $tmp)
    if ($Scalar) { $a += @('-t', '-A') } elseif (-not $Table) { $a += '-q' }
    Invoke-Native (Join-Path (Get-PgBin) 'psql.exe') $a
  } finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
}

# Creates the database and roles if missing, and (re)applies passwords and grants. Safe to re-run.
function Initialize-Database {
  $app = Get-Secret 'db-app'; $admin = Get-Secret 'db-admin'; $ro = Get-Secret 'db-ro'
  Invoke-Psql @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sirena_app') THEN CREATE ROLE sirena_app LOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sirena_admin') THEN CREATE ROLE sirena_admin LOGIN CREATEROLE; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sirena_ro') THEN CREATE ROLE sirena_ro LOGIN; END IF;
END `$`$;
ALTER ROLE sirena_app PASSWORD '$app' CONNECTION LIMIT 50;
ALTER ROLE sirena_admin PASSWORD '$admin';
ALTER ROLE sirena_ro PASSWORD '$ro' CONNECTION LIMIT 10;
GRANT sirena_app TO sirena_admin;
"@ | Out-Null
  $exists = Invoke-Psql "SELECT 1 FROM pg_database WHERE datname = '$DbName';" -Scalar
  if (-not $exists) { Invoke-Psql "CREATE DATABASE $DbName OWNER sirena_app;" | Out-Null }
  Invoke-Psql @"
REVOKE ALL ON DATABASE $DbName FROM PUBLIC;
GRANT CONNECT ON DATABASE $DbName TO sirena_app, sirena_admin, sirena_ro;
"@ | Out-Null
  Grant-ReadOnly
}

# Gives sirena_ro read access to every table, including ones future migrations create,
# except secrets: password hashes, invite links and device tokens stay out of read-only reach.
# Runs after every migration (deploy.ps1), so new columns on those tables are picked up.
function Grant-ReadOnly {
  Invoke-Psql -Database $DbName @'
ALTER SCHEMA public OWNER TO sirena_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO sirena_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sirena_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE sirena_app IN SCHEMA public GRANT SELECT ON TABLES TO sirena_ro;
DO $$
DECLARE t text; cols text;
BEGIN
  FOREACH t IN ARRAY ARRAY['Employee', 'Invite', 'DeviceToken'] LOOP
    IF to_regclass(format('public.%I', t)) IS NOT NULL THEN
      EXECUTE format('REVOKE SELECT ON public.%I FROM sirena_ro', t);
      SELECT string_agg(quote_ident(column_name), ', ') INTO cols FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = t AND column_name NOT IN ('passwordHash', 'token');
      IF cols IS NOT NULL THEN EXECUTE format('GRANT SELECT (%s) ON public.%I TO sirena_ro', cols, t); END IF;
    END IF;
  END LOOP;
END $$;
'@ | Out-Null
}

# ── Allowlist (who may reach Postgres and SSH from the internet) ─────────

function Get-Allowlist {
  if (-not (Test-Path $AllowlistPath)) { return @() }
  $raw = Get-Content $AllowlistPath -Raw
  if (-not $raw.Trim()) { return @() }
  # Windows PowerShell 5.1 emits a JSON array as one object; going through a variable unrolls it.
  $parsed = ConvertFrom-Json $raw
  @($parsed)
}

function Save-Allowlist($Entries) {
  $json = ConvertTo-Json @($Entries) -Depth 3
  if (@($Entries).Count -eq 0) { $json = '[]' }
  [IO.File]::WriteAllText($AllowlistPath, $json)
}

# Accepts 1.2.3.4, 1.2.3.0/24, or IPv6; returns it in CIDR form.
function ConvertTo-Cidr([string]$Ip) {
  $parts = $Ip.Trim().Split('/')
  $addr = $null
  if (-not [Net.IPAddress]::TryParse($parts[0], [ref]$addr)) { throw "Not an IP address: $Ip" }
  if ($parts.Count -gt 1) { return "$($addr)/$([int]$parts[1])" }
  if ($addr.AddressFamily -eq 'InterNetworkV6') { "$addr/128" } else { "$addr/32" }
}

# Replaces an inbound allow rule. With no addresses the rule is removed, so the port is closed.
function Set-InboundRule([string]$Name, [int]$Port, [string[]]$RemoteAddress) {
  Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  if (@($RemoteAddress).Count -eq 0) { return }
  New-NetFirewallRule -Name $Name -DisplayName "Sirena HR: $Name" -Direction Inbound -Action Allow -Protocol TCP `
    -LocalPort $Port -RemoteAddress $RemoteAddress -Profile Any | Out-Null
}

# Turns off any other inbound allow rule on the port (e.g. the default "OpenSSH Server" rule that allows everyone).
function Disable-OtherInboundRules([int]$Port) {
  Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq "$Port" } |
    Get-NetFirewallRule |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' -and $_.Name -notlike 'Sirena-*' } |
    Disable-NetFirewallRule
}

# Writes the allowlist into the firewall and pg_hba.conf, then reloads Postgres.
function Sync-Allowlist {
  $cfg = Get-SirenaConfig
  $list = Get-Allowlist
  $dbIps = if (Test-DbExposed) { @($list | Where-Object { $_.db } | ForEach-Object { $_.ip }) } else { @() }
  $sshIps = @($list | Where-Object { $_.ssh } | ForEach-Object { $_.ip }) + $(if (Test-UseTailscale) { $TailscaleRange })

  Set-InboundRule 'Sirena-Postgres' $cfg.PgPort $dbIps
  $sshPort = Get-SshPort
  Set-InboundRule 'Sirena-SSH' $sshPort $sshIps
  if (Test-DbExposed) { Disable-OtherInboundRules $cfg.PgPort }
  Disable-OtherInboundRules $sshPort
  if ($sshPort -ne 22) { Disable-OtherInboundRules 22 }

  # Remote logins: only the admin and read-only roles, only to sirena_hr, only over SSL, only from listed IPs.
  $hba = Join-Path $PgDataDir 'pg_hba.conf'
  $lines = Get-Content $hba
  $start = [array]::IndexOf($lines, '# BEGIN SIRENA ALLOWLIST')
  $end = [array]::IndexOf($lines, '# END SIRENA ALLOWLIST')
  if ($start -lt 0 -or $end -lt $start) { throw "Allowlist markers missing from $hba. Re-run setup.ps1." }
  $block = if (-not (Test-DbExposed)) { @() } else { @($list | Where-Object { $_.db } | ForEach-Object { "hostssl  $DbName  sirena_admin,sirena_ro  $($_.ip)  scram-sha-256  # $($_.label)" }) }
  $new = @($lines[0..$start]) + $block + @($lines[$end..($lines.Count - 1)])
  [IO.File]::WriteAllLines($hba, [string[]]$new)
  Invoke-Psql 'SELECT pg_reload_conf();' | Out-Null
}

# ── Cloudflare and Caddy ────────────────────────────────────────────────

function Update-CloudflareRanges {
  $v4 = (Invoke-RestMethod 'https://www.cloudflare.com/ips-v4') -split "`n" | Where-Object { $_.Trim() }
  $v6 = (Invoke-RestMethod 'https://www.cloudflare.com/ips-v6') -split "`n" | Where-Object { $_.Trim() }
  $all = @($v4 + $v6 | ForEach-Object { $_.Trim() })
  if ($all.Count -lt 10) { throw 'Cloudflare IP list looks wrong; not applying it.' }
  [IO.File]::WriteAllLines($CloudflareIpsPath, [string[]]$all)
  $all
}

# Port 443 accepts only Cloudflare, so nobody can skip Cloudflare by hitting the IP directly.
function Write-CaddyConfig {
  $cfg = Get-SirenaConfig
  $root = $SirenaRoot -replace '\\', '/'
  if ($cfg.DirectAccess) {
    if (-not $cfg.PublicIp) { throw 'DirectAccess requires PublicIp in config.psd1.' }
    $site = "https://$($cfg.PublicIp):$($cfg.PublicPort)"
  } else {
    $cf = @(Get-Content $CloudflareIpsPath | Where-Object { $_.Trim() })
    $site = $cfg.Domain
  }
  $tls = "tls $root/certs/origin.pem $root/certs/origin.key {`n`t`tprotocols tls1.2 tls1.3`n`t}"
  $global = if ($cfg.DirectAccess) {
    "{`n`tauto_https disable_redirects`n`t# Clients that connect by IP send no SNI; serve the IP certificate to them.`n`tdefault_sni $($cfg.PublicIp)`n}"
  } else {
    @"
{
	auto_https disable_redirects
	servers {
		trusted_proxies static $($cf -join ' ')
		client_ip_headers CF-Connecting-IP
	}
}
"@
  }
  $caddyfile = @"
$global

$site {
	$tls
	encode zstd gzip

	header {
		Strict-Transport-Security "max-age=31536000"
		X-Content-Type-Options nosniff
		X-Frame-Options DENY
		Referrer-Policy strict-origin-when-cross-origin
		Permissions-Policy "geolocation=(self), camera=(), microphone=(), payment=(), usb=()"
		Cross-Origin-Opener-Policy same-origin
		# Only restricts what can't break the Flutter app: no framing, plugins, foreign <base> or form targets.
		Content-Security-Policy "frame-ancestors 'none'; object-src 'none'; base-uri 'self'; form-action 'self'"
		-Server
		-X-Powered-By
	}

	# Nothing on this site lives under these; refuse probes for source or secrets outright.
	@hidden path /.git/* /.env* */.env /backend/* /ops/*
	handle @hidden {
		respond 404
	}

	handle /api/* {
		# Uploads are capped at 50 MB by the API; refuse anything far larger before it reaches it.
		request_body {
			max_size 60MB
		}
		reverse_proxy 127.0.0.1:$(Get-ApiPort) {
			# The API trusts X-Forwarded-For from loopback; give it the real visitor IP.
			header_up X-Forwarded-For {client_ip}
		}
	}

	handle {
		root * $root/www
		try_files {path} /index.html
		file_server
	}

	log {
		output file $root/logs/caddy-access.log {
			roll_size 20MiB
			roll_keep 10
		}
		# One-minute download links carry a token in ?t=; keep it out of the log.
		format filter {
			wrap json
			fields {
				request>uri query {
					delete t
				}
			}
		}
	}
}
"@
  [IO.File]::WriteAllText((Join-Path $SirenaRoot 'Caddyfile'), $caddyfile)
  if ($cfg.DirectAccess) {
    Set-InboundRule 'Sirena-HTTPS' $cfg.PublicPort 'Any'
    Disable-OtherInboundRules $cfg.PublicPort
  } else {
    Set-InboundRule 'Sirena-HTTPS' 443 $cf
    Disable-OtherInboundRules 443
  }
}

# ── Services ────────────────────────────────────────────────────────────

# Each service's own virtual account (no password, no rights beyond what is granted here).
$ApiAccount = "NT SERVICE\$ApiService"
$CaddyAccount = "NT SERVICE\$CaddyService"
$CaddyDataDir = Join-Path $SirenaRoot 'caddy-data'

function Test-ServiceAccount([string]$Service) {
  (Get-CimInstance Win32_Service -Filter "Name='$Service'" -ErrorAction SilentlyContinue).StartName -like 'NT SERVICE\*'
}

# What the API and Caddy need when they run as their own accounts instead of LocalSystem:
# API reads its .env and writes uploaded files; Caddy reads the TLS key and keeps its own data; both write logs.
# Safe to re-run (setup.ps1 rewrites .env and folder permissions, so it calls this again).
function Grant-ServiceAccess {
  if (Get-Service $ApiService -ErrorAction SilentlyContinue) {
    Invoke-Native icacls.exe @("$RepoDirackend\.env", '/grant', "${ApiAccount}:R") | Out-Null
    Invoke-Native icacls.exe @("$SirenaRootiles", '/grant', "${ApiAccount}:(OI)(CI)M") | Out-Null
    Invoke-Native icacls.exe @($LogsDir, '/grant', "${ApiAccount}:(OI)(CI)M") | Out-Null
  }
  if (Get-Service $CaddyService -ErrorAction SilentlyContinue) {
    New-Item -ItemType Directory -Force $CaddyDataDir | Out-Null
    Invoke-Native icacls.exe @("$SirenaRoot\certs", '/grant', "${CaddyAccount}:(OI)(CI)R") | Out-Null
    Invoke-Native icacls.exe @($CaddyDataDir, '/grant', "${CaddyAccount}:(OI)(CI)M") | Out-Null
    Invoke-Native icacls.exe @($LogsDir, '/grant', "${CaddyAccount}:(OI)(CI)M") | Out-Null
  }
}

# Stop-Service can sit in StopPending forever when the service wrapper hangs.
# Ask politely, then end the wrapper and its node process.
function Stop-ApiService([int]$TimeoutSeconds = 30) {
  $svc = Get-Service $ApiService -ErrorAction SilentlyContinue
  if (-not $svc -or $svc.Status -eq 'Stopped') { return }
  Stop-Service $ApiService -NoWait -ErrorAction SilentlyContinue
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if ((Get-Service $ApiService).Status -eq 'Stopped') { return }
    Start-Sleep -Seconds 1
  }
  $wrapperPid = (Get-CimInstance Win32_Service -Filter "Name='$ApiService'").ProcessId
  if ($wrapperPid) {
    Write-Note "API service did not stop in $TimeoutSeconds s; ending it"
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$wrapperPid" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $wrapperPid -Force -ErrorAction SilentlyContinue
  }
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Service $ApiService).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
}

function Test-ApiHealth([int]$TimeoutSeconds = 45) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-RestMethod "http://127.0.0.1:$(Get-ApiPort)/api/health" -TimeoutSec 5
      if ($r.ok) { return $true }
    } catch { }
    Start-Sleep -Seconds 2
  }
  $false
}
