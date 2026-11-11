# Sirena HR security review

Review of the API (`backend/`), the app (`app/`) and the Windows server scripts (`ops/windows/`), November 2026.
Branch `security/hardening`. Nothing here has been deployed. "Server steps" below lists what still has to be run on the live server.

## What was checked

| Area | Result |
|---|---|
| JWT secret, algorithm, expiry | 64-char random secret from `setup.ps1`, 12 h expiry. **Fixed:** the API now refuses to start with a missing, short (<32) or example secret, and only accepts HS256 tokens. |
| Token revocation | **Was missing.** A token stayed valid for 12 h after a password or role change. **Fixed** (see below). Leaving the company (status `EXITED`) already blocked every token. |
| Login rate limit and lockout | 5 failures per account and 30 per IP in 15 min existed. **Fixed:** the lock check was off-by-one after expiry, the maps could grow without limit, a wrong email answered faster than a wrong password (it showed which emails exist), and lockouts weren't logged. Now: HTTP 429, a constant-time path for unknown emails, an audit entry `login-locked`, and the same limit on the current-password check in change-password. |
| Password policy | Only a 10-char minimum. **Fixed:** 10–72 characters (bcrypt ignores anything past 72 bytes), rejects the company name, the shared `Sirena@123` and its variants, common words, digits-only passwords, and passwords containing the person's email or name. Applies to change-password and invite sign-up. |
| Input validation | `whitelist` + `forbidNonWhitelisted` were already on. **Added:** `forbidUnknownValues`, length caps on the auth DTOs, a 256 KB JSON body limit, and caps on the multipart field and file count. |
| Authorization (CASL) | Every admin route checks `assertCan`/`canDo` or super-admin. **Found and fixed:** (1) **account takeover:** anyone with `invites.send` (HR) could send an invite for *any* employee, including a super admin, then accept it and set that person's password. Now only people who have never signed up, with role EMPLOYEE, at the sender's location, unless the sender is a super admin. (2) HR could edit a super admin's record (email, status). (3) Location-scoped HR could move an employee to a location they don't manage. |
| Forced password change | It was enforced only by the app's router; the API answered every call. **Fixed:** while `mustChangePassword` is true, the API allows only `GET /me` and `POST /auth/change-password` and returns 403 for everything else. |
| File upload / download | 50 MB limit with auth-checked downloads already in place. **Fixed:** executables, scripts, HTML and SVG are refused. Downloads are always sent as `application/octet-stream` attachments with `nosniff` and a sandbox CSP, so an uploaded file can't run as a page. Signed download links (60 s) now also respect token revocation. |
| Security headers | No helmet. **Added** the same headers helmet sets for a JSON API, without a new dependency (`backend/src/common/security.ts`): CSP `default-src 'none'`, `nosniff`, `X-Frame-Options DENY`, `no-referrer`, CORP/COOP, `Cache-Control: no-store`. `X-Powered-By` is removed. |
| CORS | **Fixed:** with `CORS_ORIGINS` empty, *any* origin was allowed. Now, in production (`TRUST_PROXY=true`), empty means no cross-origin callers. Credentials are off (the app uses bearer tokens, not cookies). |
| Error messages | Nest returns a generic 500 for unexpected errors; no stack traces or Prisma messages reach clients. OK. |
| Audit log | Login, password change, invites, role and permission changes, employee edits, leave decisions, uploads and downloads were already logged. **Added:** lockouts, client IP on login and password change, and lunch-menu changes. |
| API bind address | It listened on `0.0.0.0`. **Fixed:** it now listens on `127.0.0.1` in production, so only Caddy can reach it. Override with `HOST=`. |
| Web/app: admin pages | **Fixed:** the router now sends people without the permission away from `/admin/*` and `/leave/approvals` (previously an employee could open `/admin/employees` by typing the address). The Employees **Add** button shows only with `manageEmployees`, and Roles & access **Reset** only for super admins. |
| Web/app: tokens | Stored with `flutter_secure_storage` (Android Keystore; on the web, encrypted in `localStorage`). Logout clears memory and storage even if storage throws. After a password change the app stores the new token the server returns. |
| Android | Certificate pinning (`SERVER_CERT_SHA256`, `pinning_io.dart`) is unchanged and still on. **Fixed:** release builds allowed cleartext HTTP and Android backup. Cleartext is now allowed only in debug builds; `allowBackup` is off. |
| Postgres | **Fixed:** `DbExposed` defaulted to *true* when missing from `config.psd1` (the live config sets it to false). The default is now false, so Postgres listens on localhost only. The read-only role `sirena_ro` could read password hashes and live invite tokens; these columns (`passwordHash`, `token` on Employee, Invite, DeviceToken) are now hidden from it, re-applied after every migration by `deploy.ps1`. |
| DB roles / passwords | `sirena_app` (API), `sirena_admin` (people), `sirena_ro` (read-only); 32-char random passwords; scram-sha-256; SSL with TLS ≥ 1.2. OK. Remaining risk: `sirena_app` owns the schema because it runs migrations. |
| Secrets, backups, files, logs | `secrets\` and `certs\` were Administrators+SYSTEM only. **Fixed:** `backups\`, `files\` and `logs\` were open to every local user (database dumps hold all personal data). They're now restricted the same way. |
| Caddy TLS and headers | **Fixed:** TLS is pinned to 1.2/1.3. Added `X-Frame-Options`, `Permissions-Policy`, COOP and a CSP that can't break Flutter (`frame-ancestors`, `object-src`, `base-uri`, `form-action`). Paths like `/.git`, `/.env`, `/backend` and `/ops` return 404. Request bodies are capped at 60 MB. Download tokens (`?t=`) are removed from the access log. |
| Firewall / SSH | HTTPS port open to all, SSH allowlist-only (plus Tailscale if enabled), RDP Tailscale-only, and other allow rules on those ports disabled. OK. **Added** sshd hardening (`MaxAuthTries 3`, `LoginGraceTime 30`, no empty passwords, no challenge-response, no agent/X11/tunnel forwarding). The config is checked with `sshd -t` and the old one is restored if it fails. |
| Windows service accounts | The API and Caddy ran as LocalSystem. **Added** `harden-services.ps1` (opt-in), which moves them to the virtual accounts `NT SERVICE\SirenaApi` and `NT SERVICE\SirenaCaddy` with only the folder rights they need. It switches back automatically if the health check fails. Postgres already runs as its own account. |

Tests: `npx jest` (51 pass, including `backend/src/auth/security.spec.ts`), `flutter analyze` (only the 6 deprecation infos that were already there), `flutter test`, `flutter build web --release` compiles. All `ops/windows` scripts parse. The generated Caddyfile was rendered and read, but not run through `caddy validate` (no Caddy on the laptop); `setup.ps1` and the steps below validate it before use. The new code was not run against a live database.

## Behaviour changes to know before deploying

- Migration `20261109200000_session_revocation` adds `Employee.tokensValidFrom` (nullable). Existing tokens stay valid; nobody is signed out by the deploy.
- Changing a password signs out that person's other devices. Changing someone's role signs them out so the app reloads what they may see.
- **Older Android builds:** after a password change the old app doesn't keep the new token, so the person is sent to sign-in once. Rebuild the APK from this branch.
- A wrong-password lockout now returns HTTP 429 instead of 401 (the app shows the same message).
- Uploads ending in `.exe .bat .cmd .ps1 .js .html .svg …` are refused; zip them to share.
- HR can no longer re-invite someone who already has an account. A super admin can (that's the "reset access" path).

## Server steps (run on the server, Administrator PowerShell, after deploying this branch)

Deploy as usual (git bundle + `deploy.ps1 -SkipFetch`). The deploy runs the migration and re-applies the read-only grants. Then:

1. **Check the JWT secret length before deploying.** The API now refuses to start below 32 characters:
   ```powershell
   (Get-Content C:\sirena\secrets\jwt.txt -Raw).Trim().Length   # expect 64
   ```
2. **Lock down backups, uploaded files and logs:**
   ```powershell
   . C:\sirena\repo\ops\windows\lib\common.ps1
   Protect-Folder C:\sirena\backups; Protect-Folder C:\sirena\files; Protect-Folder C:\sirena\logs
   icacls C:\sirena\backups   # expect only BUILTIN\Administrators and NT AUTHORITY\SYSTEM
   ```
3. **New Caddy config (TLS, headers, log filter):**
   ```powershell
   . C:\sirena\repo\ops\windows\lib\common.ps1
   Copy-Item C:\sirena\Caddyfile C:\sirena\Caddyfile.bak
   Write-CaddyConfig
   & C:\sirena\tools\bin\caddy.exe validate --config C:\sirena\Caddyfile --adapter caddyfile
   Restart-Service SirenaCaddy
   curl.exe -k -sI https://106.51.67.75:8888/ | findstr /i "x-frame content-security strict-transport"
   ```
   If validate fails, put `Caddyfile.bak` back and send the error.
4. **SSH hardening** (re-running `setup.ps1` does this too, but it also restarts Postgres):
   ```powershell
   $c = 'C:\ProgramData\ssh\sshd_config'; Copy-Item $c "$c.bak"
   $add = 'PermitEmptyPasswords no','ChallengeResponseAuthentication no','MaxAuthTries 3','LoginGraceTime 30','AllowAgentForwarding no','GatewayPorts no','PermitTunnel no','X11Forwarding no'
   $keys = $add | ForEach-Object { ($_ -split ' ')[0] }
   $rest = Get-Content $c | Where-Object { $l = $_; -not ($keys | Where-Object { $l -match "^#?\s*$_\s+" }) }
   [IO.File]::WriteAllLines($c, [string[]]($add + $rest))
   & C:\Windows\System32\OpenSSH\sshd.exe -t; if ($LASTEXITCODE -eq 0) { Restart-Service sshd } else { Copy-Item "$c.bak" $c -Force }
   ```
   Keep your current SSH session open and test a new login before closing it.
5. **Run the API and Caddy under their own accounts** (about 10 s of downtime; switches back by itself if unhealthy):
   ```powershell
   C:\sirena\repo\ops\windows\harden-services.ps1        # undo: -Undo
   ```
6. **Verify Postgres and the firewall:**
   ```powershell
   Get-NetTCPConnection -LocalPort 5433 -State Listen | Select LocalAddress   # only 127.0.0.1 / ::1
   Get-NetTCPConnection -LocalPort 3100 -State Listen | Select LocalAddress   # API: only 127.0.0.1
   Get-NetFirewallRule -Name 'Sirena-*' | ForEach-Object { "$($_.Name): $((Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_).LocalPort) from $((Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_).RemoteAddress)" }
   # expect Sirena-SSH 7777 from 106.51.70.71/32 only (no Sirena-Postgres rule), Sirena-HTTPS 8888 from Any
   C:\sirena\repo\ops\windows\sql.ps1 'SELECT "passwordHash" FROM "Employee" LIMIT 1'   # must fail: permission denied
   ```
7. **Remove one-time passwords left on disk** after those accounts have changed their password:
   `Remove-Item C:\sirena\secrets\first-admin-password.txt, C:\sirena\secrets\seed-password.txt -ErrorAction SilentlyContinue`
8. **Off-site backups:** if `OffsiteDir` or `RcloneRemote` is set, the copy is unencrypted. Use an rclone `crypt` remote, or a destination only admins can read.

## Shared default password (`Sirena@123`)

Turn `mustChangePassword` on **in the same statement** that sets the shared password, and only after this branch is deployed (the API now enforces the change itself). That way no account ever has the shared password without the forced change:

```sql
-- run with sql.ps1 -Write; <hash> = output of: node -e "console.log(require('bcryptjs').hashSync('Sirena@123', 12))" (in C:\sirena\repo\backend)
UPDATE "Employee" SET "passwordHash" = '<hash>', "mustChangePassword" = true, "tokensValidFrom" = now()
WHERE status <> 'EXITED' AND role <> 'SUPER_ADMIN';
```

Tell people the same day. Until someone signs in, anyone who knows their email can claim the account first, so check after a few days who still hasn't changed it (`sql.ps1 'SELECT email FROM "Employee" WHERE "mustChangePassword"'`) and follow up. The new password rules stop people from choosing `Sirena@123` (or a variant) again.

## Still open (not fixed here)

- **Android release signing** uses the debug key, and the app id is `com.example.sirena_hr`. Create a real keystore before wider distribution.
- **Self-signed IP certificate:** browsers show a warning and HSTS is ignored on an IP. A domain with a real certificate would fix both.
- **Web token storage:** on the web the token sits in encrypted `localStorage`, readable by any script on the page. Risk is low because the app never renders user-supplied HTML. A strict `script-src` CSP needs testing against Flutter's loader first.
- **Migrations run as `sirena_app`,** the role the API uses, so the API's database role can change the schema. A separate migration role would remove that.
- **Brute-force counters are in memory** and reset when the API restarts. That's fine for one process; it would need Postgres or Redis if the API ever runs more than one instance.
- **No "sign out everywhere" button** yet; `AccessService.revokeSessions` is ready for one.
