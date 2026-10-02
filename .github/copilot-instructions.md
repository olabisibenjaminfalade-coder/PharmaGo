# PharmaGo project guidance

- The active marketplace client is Flutter/Dart in `lib/`; the REST API is Dart Shelf in `backend/`. Root HTML files are the retained predecessor storefront, not the active marketplace.
- Keep catalogue, order totals, stock validation, authentication and authorization on the API. Never store credentials or trust price/role values supplied by a client.
- Do not implement real payment capture without an approved provider and server-side payment verification. Keep the current demo and pay-on-delivery states explicitly labelled as unpaid.
- Preserve seller ownership checks, buyer data isolation, transactional checkout, idempotency and audit events when changing API behavior.
- Use the shared Flutter models, `ApiClient` and `MarketplaceController` rather than duplicating API/state logic in screens.
- Run `dart format` and `dart test` from `backend/`, and `flutter test` and `flutter analyze` from the project root for relevant changes.
- Keep project documentation honest about unperformed stakeholder research, unverified target-platform builds and production limitations.
