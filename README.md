# PharmaGo Marketplace

PharmaGo is a pharmacy marketplace prototype for buyers, sellers and administrators. The cross-platform client is built with Flutter; the development API is Dart Shelf with SQLite. The original root-level HTML storefront files are retained as a historical prototype. Use the Flutter commands below to run the current application.

## Current capabilities

- Buyer and seller registration, sign-in and role-specific screens.
- Signed, expiring API sessions backed by revocable server-side sessions; access tokens are stored using Flutter Secure Storage.
- Pharmacy product search, category filters, details and stock-aware cart.
- Seller product listing create/edit/deactivate, seller approval and seller-specific fulfilment updates.
- Transactional checkout, server-side price/stock calculation, order history and idempotency keys.
- Administrator seller approval, product moderation, category management, account activation and summary reporting.
- Responsive Flutter layouts targeting web, Windows, Linux, macOS, Android and iOS.

The development payment flow is simulation only. It does not collect card/bank credentials, process payments or mark an order as paid. Production payments need a contracted provider and server-side signed verification.

## Requirements

- Flutter stable SDK and the Dart SDK bundled with it.
- Git.
- Development API: Dart 3.5 or later, Dart pub packages, and a filesystem writable by the API process.
- Android builds: Android Studio/Android SDK and supported JDK.
- Windows desktop builds: Visual Studio with the Desktop development with C++ workload.
- Linux desktop builds: Flutter's documented Linux desktop build dependencies.
- macOS/iOS builds: macOS with Xcode; iOS signing and App Store submission require Apple developer configuration.

## Run locally on Windows

### 1. Install dependencies

From the project root:

```powershell
flutter pub get
Push-Location .\backend
dart pub get
Pop-Location
```

### 2. Start the development API

In a PowerShell terminal, set a unique secret of at least 32 bytes and allowed web origin(s), then run the service:

```powershell
$env:PHARMAGO_JWT_SECRET = "<generate a unique random secret; do not commit it>"
$env:PHARMAGO_ALLOWED_ORIGINS = "http://localhost:5000"
Push-Location .\backend
dart run .\bin\server.dart
```

The API creates `pharmago.sqlite` in the backend working directory and seeds the initial catalogue. To create the first administrator, set `PHARMAGO_ADMIN_EMAIL` and a unique `PHARMAGO_ADMIN_PASSWORD` (minimum 15 characters) before the first startup. Never put production credentials in source control. Seller accounts remain pending until an administrator approves them.

### 3. Run the Flutter client

Open another terminal at the project root:

```powershell
flutter run -d web-server --web-port 5000 --dart-define=PHARMAGO_API_URL=http://127.0.0.1:8080
```

For an Android emulator, use the emulator host alias as the API URL, for example `http://10.0.2.2:8080`; a physical device must use a reachable development-server address. For production, use HTTPS and configure allowed origins explicitly.

## Tests and build

```powershell
flutter test
Push-Location .\backend
dart test
Pop-Location
flutter build web --dart-define=PHARMAGO_API_URL=https://<your-api-host>
```

Run desktop/mobile builds only after installing the matching platform toolchain. Check `flutter doctor` for missing host dependencies.

## Configuration and security

- `PHARMAGO_API_URL` is a compile-time client setting; it is public and must not contain a secret.
- `PHARMAGO_JWT_SECRET`, admin bootstrap credentials, database credentials and payment-provider keys belong in a secret manager or process environment, never in Flutter assets or client code.
- Configure `PHARMAGO_ALLOWED_ORIGINS` with exact trusted origins. Native clients do not send a browser origin.
- The SQLite database is for local development. Use a managed PostgreSQL deployment, migrations, backups, TLS, monitoring, rate limits at the edge, and a reviewed production session/key-rotation strategy before launch.
- The included payment modes are not real payment methods. Do not use them to fulfil or mark a real paid order.
- Pharmacy product listings and the seeded catalogue are demonstration data. A pharmacist/compliance owner must validate product identity, claims, licensing and any prescription restrictions before operation.

## Project report

See [PROJECT_REPORT.md](./PROJECT_REPORT.md) for feasibility, fact-finding limitations, SRS, algorithms, flowcharts, pseudocode, data model, user manuals, test plan and evidence status. No stakeholder interview/questionnaire results are fabricated; those activities remain to be conducted and documented.
