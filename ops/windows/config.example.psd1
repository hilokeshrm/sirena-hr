# Copy to config.psd1 (same folder), edit, then run setup.ps1.
# setup.ps1 copies it to C:\sirena\config.psd1, which every other script reads.
@{
  # Public website + API (Cloudflare, proxied / orange cloud)
  Domain       = 'hr.sirenatech.com'
  # Optional direct-IP mode. Set DirectAccess = $true only when intentionally
  # serving the site without Cloudflare.
  DirectAccess = $false
  PublicIp     = ''
  PublicPort   = 443
  # Database host name (Cloudflare, DNS only / grey cloud)
  DbHost       = 'db.sirenatech.com'

  # Code. setup.ps1 creates a read-only deploy key for this repo.
  RepoSsh      = 'git@github.com:hilokeshrm/sirena-hr.git'
  Branch       = 'main'

  PgMajor      = 17
  PgPort       = 5432
  # DbExposed = $false   # keep Postgres on localhost only (no remote access)
  # SshPort   = 22       # port sshd listens on
  # UseTailscale = $false   # skip Tailscale sign-in (default true)
  # SshPasswordAuth = $true   # allow Windows account passwords over SSH (default false: keys only)
  # ApiPort   = 3000   # local API port; change if 3000 is used by another app

  # Lunch booking closes at this local time on the day itself
  MealCutoff   = '10:30'

  # Remote Desktop, reachable over Tailscale only
  EnableRdp    = $true

  # Backups
  BackupTime   = '02:00'
  DailyKeep    = 14
  WeeklyKeep   = 8
  # Optional second copy off this disk, e.g. 'D:\SirenaBackups' or '\\nas\backups\sirena'
  OffsiteDir   = ''
  # Optional rclone remote, e.g. 'b2:sirena-backups' (install rclone and run "rclone config" first)
  RcloneRemote = ''
  # Optional Healthchecks.io ping URL; you get an alert if a night's backup doesn't arrive
  BackupPingUrl = ''
}
