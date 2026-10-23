# Sirena HR

People, leave, check-in, lunch booking, projects and policies for Sirena Technologies.
One Flutter codebase for Android, iOS and the website, plus a NestJS + PostgreSQL API that runs on your own machine. No Docker.

```
backend/   NestJS API, Prisma schema, seed data, local Postgres runner
app/       Flutter app (Android, iOS, web)
```

## 1. Run the API on your machine

Needs Node.js 20+.

```bash
cd backend
npm install
cp .env.example .env          # then set JWT_SECRET to a long random string
npm run db:dev                # terminal 1: starts a local Postgres on port 5433 (data in backend/.pgdata)
npm run db:deploy             # terminal 2: creates the tables
npm run db:seed               # sample company: 9 people, 2 projects, leave types, 2026 holidays
npm run start:dev             # API on http://localhost:3000/api
```

`npm run db:dev` uses the `embedded-postgres` package, so nothing else needs installing for development.
Check it's up: `curl http://localhost:3000/api/health`.

Seeded logins all share the password in `SEED_PASSWORD` in `prisma/seed.ts` (local testing only). Some useful accounts:

| Login | Role |
|---|---|
| ravi.shankar@sirena.in | Super admin |
| meena.k@sirena.in | HR admin |
| arjun.mehta@sirena.in | Manager (Karthik, Divya, Priya report to him) |
| karthik.s@sirena.in | Employee |
| kavya.reddy@sirena.in | Finance |

## 2. Run the app

Install the Flutter SDK (https://docs.flutter.dev/get-started/install), then once:

```bash
cd app
flutter create . --platforms=android,ios,web --project-name sirena_hr   # adds the platform folders; keeps lib/ and pubspec.yaml
flutter pub get
```

Then:

```bash
flutter run -d chrome                                              # website
flutter run -d android --dart-define=API_BASE=http://10.0.2.2:3000/api   # Android emulator (10.0.2.2 = your PC)
flutter run -d <phone> --dart-define=API_BASE=http://<PC LAN IP>:3000/api # real phone on the same Wi-Fi
```

Build the website: `flutter build web --dart-define=API_BASE=https://hr.sirenatech.com/api` and serve `app/build/web`.

### Platform settings for Wi-Fi check-in

Auto check-in reads the Wi-Fi name / BSSID, which needs location permission.

**Android** — `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
```

For local http testing also add `android:usesCleartextTraffic="true"` on `<application>` (not needed with https).

**iOS** — in Xcode enable the *Access Wi-Fi Information* capability, and add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to check you in automatically when you're on the office Wi-Fi.</string>
```

**Web** — browsers can't read Wi-Fi, so the website uses manual check-in. Manual "office" check-ins are matched against the office public IP instead (set `publicIp` on the office network) and flagged for HR when they don't match.

Set the real office SSID / BSSIDs / public IP in the `OfficeNetwork` table (the seed has placeholders).

## 3. Production on your machine with a public IP (no Docker)

1. **PostgreSQL** — install PostgreSQL 16 as a Windows service (EnterpriseDB installer) or `apt install postgresql` on Linux. Create a database and user, point `DATABASE_URL` in `backend/.env` at it, and keep port 5432 closed to the internet (only the API talks to it).
2. **API** — `npm ci && npm run build && npm run db:deploy`, then run `node dist/main` as a service (NSSM on Windows, systemd on Linux, or `pm2`).
3. **HTTPS** — put Caddy in front. Point a DNS name (e.g. `hr.sirenatech.com`) at your public IP, open ports 80/443 on the router, and use this `Caddyfile`:

   ```
   hr.sirenatech.com {
     handle /api/* {
       reverse_proxy localhost:3000
     }
     handle {
       root * C:/sirena-hr/web      # contents of app/build/web
       file_server
     }
   }
   ```

   Caddy gets the certificate automatically. Keep `TRUST_PROXY=true` so the API sees real client IPs.
4. **Backups** — schedule `pg_dump` nightly and copy `backend/storage/` (project files) somewhere off the machine.

## Monthly HR jobs

- `POST /api/leave/accrue {year, month}` — credit monthly leave (HR).
- `POST /api/leave/open-year {year}` — carry forward and open the new year (HR).

## What's in it

- **Check-in / out** — automatic on office Wi-Fi (BSSID match) or a manual tap; WFH supported; out-of-office manual check-ins are flagged.
- **Lunch** — veg / non-veg / skip, only on office days, before the cut-off (`MEAL_CUTOFF`); approved leave cancels bookings; kitchen counts and menu for the cafeteria.
- **Leave** — balances as a ledger, half days, sandwich rule, notice and max-days rules, holidays per location, manager → HR approval chain, team calendar.
- **Projects** — members and roles, milestones, tasks, folders with restricted folders for leads, versioned file uploads, one-minute download links.
- **Policies** — versions, publish with notification, acknowledgement tracking and reminders.
- **Access (ABAC)** — rules use role, location, reporting line and project membership (`backend/src/access/access.service.ts`).
