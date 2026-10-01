# Quota service (first manual-data development version)

The quota service is intentionally independent from `server/index.js` and the portfolio Web app.

## Start on Windows LAN

```powershell
$env:QUOTA_ADMIN_PASSWORD = 'replace-with-a-long-local-password'
$env:QUOTA_PORT = '4100'
$env:QUOTA_HOST = '0.0.0.0'
node quota-service/index.js
```

Open `http://127.0.0.1:4100` on the PC. From a phone on the same WiFi use `http://<PC-LAN-IP>:4100`.

The first version does not crawl any upstream site. Use the management page to enter fund code, name, category, channel, status, daily limit and fee rate.

## API

- `GET /health`
- `GET /api/quotas` (public app snapshot)
- `POST /api/corrections` (app user correction suggestion)
- `POST /api/admin/login`
- `GET/PUT /api/admin/quotas/:code`
- `GET/PUT /api/admin/settings`
- `GET /api/admin/corrections`
- `GET /api/admin/audit`
- `POST /api/admin/corrections/:id/revoke`

Corrections are counted by a salted server-side hash of the client IP. The service applies a correction only when both the minimum support count and agreement ratio are met. The default is 3 sources, 80%, within 72 hours. The thresholds are editable in the management page.

## App build address

The Flutter app integration will use a separate `QUOTA_SERVICE_URL`, so the quota service can run on a different host and port from the portfolio API:

```powershell
flutter run --dart-define=QUOTA_SERVICE_URL=http://192.168.31.143:4100
```

Do not use `change-me-now` outside local development.
